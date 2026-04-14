import Database
import Foundation
import Shared

public enum ProjectTaskServiceError: LocalizedError, Sendable {
    case invalidProjectRoot(String)
    case ioFailed(String)
    case taskNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .invalidProjectRoot(let message): return message
        case .ioFailed(let message): return message
        case .taskNotFound(let id): return "Task not found: \(id.uuidString)"
        }
    }
}

/// Persists PM tasks and time segments under each project’s `\(DotProjectLayout.dotDirectoryName)` folder.
public final class ProjectTaskService: @unchecked Sendable {
    private let database: DatabaseManager?
    private let lock = NSLock()
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(database: DatabaseManager?) {
        self.database = database
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    // MARK: - Paths

    public static func dotDirectoryURL(forProjectRoot root: URL) -> URL {
        root.standardizedFileURL.appendingPathComponent(DotProjectLayout.dotDirectoryName, isDirectory: true)
    }

    private func manifestURL(for root: URL) -> URL {
        Self.dotDirectoryURL(forProjectRoot: root).appendingPathComponent(DotProjectLayout.manifestFileName)
    }

    private func tasksURL(for root: URL) -> URL {
        Self.dotDirectoryURL(forProjectRoot: root).appendingPathComponent(DotProjectLayout.tasksFileName)
    }

    // MARK: - Public API

    @discardableResult
    public func registerProject(at root: URL, displayName: String?) throws -> DotProjectManifest {
        try ensureDotLayout(at: root)
        let standardized = root.standardizedFileURL
        let path = standardized.path
        if fileManager.fileExists(atPath: manifestURL(for: standardized).path) {
            let existing = try loadManifest(for: standardized)
            recordMetric(.pmProjectRegistered, metadata: #"{"path":"\#(path)"}"#)
            return existing
        }
        let name = displayName ?? standardized.lastPathComponent
        let manifest = DotProjectManifest(
            projectId: UUID(),
            rootPath: path,
            displayName: name,
            createdAt: Date()
        )
        try writeManifest(manifest, for: standardized)
        let doc = PMTaskDocument()
        try writeTasksDocument(doc, for: standardized)
        recordMetric(.pmProjectRegistered, metadata: #"{"path":"\#(path)","new":true}"#)
        return manifest
    }

    public func loadManifest(for root: URL) throws -> DotProjectManifest {
        let url = manifestURL(for: root.standardizedFileURL)
        let data = try Data(contentsOf: url)
        return try decoder.decode(DotProjectManifest.self, from: data)
    }

    public func listTasks(for root: URL) throws -> [PMTaskRecord] {
        try loadTasksDocument(for: root.standardizedFileURL).tasks
    }

    @discardableResult
    public func startTask(for root: URL, title: String) throws -> PMTaskRecord {
        let rootURL = root.standardizedFileURL
        try ensureDotLayout(at: rootURL)
        if !fileManager.fileExists(atPath: manifestURL(for: rootURL).path) {
            _ = try registerProject(at: rootURL, displayName: nil)
        }
        var doc = try loadTasksDocument(for: rootURL)
        // Stop any other active tasks in this project.
        for i in doc.tasks.indices {
            if doc.tasks[i].status == .active, doc.tasks[i].activeSegment != nil {
                doc.tasks[i] = try stopTaskMutation(doc.tasks[i], at: Date())
            }
        }
        let task = PMTaskRecord(title: title, status: .active, segments: [PMTimeSegment(start: Date(), end: nil)])
        doc.tasks.append(task)
        try writeTasksDocument(doc, for: rootURL)
        recordMetric(.pmTaskTimerStart, metadata: #"{"title":"\#(escapeJSON(title))"}"#)
        return doc.tasks.last!
    }

    @discardableResult
    public func stopTask(for root: URL) throws -> PMTaskRecord? {
        let rootURL = root.standardizedFileURL
        var doc = try loadTasksDocument(for: rootURL)
        guard let idx = doc.tasks.lastIndex(where: { $0.status == .active && $0.activeSegment != nil }) else {
            return nil
        }
        let updated = try stopTaskMutation(doc.tasks[idx], at: Date())
        doc.tasks[idx] = updated
        try writeTasksDocument(doc, for: rootURL)
        let seconds = Int(updated.totalTrackedSeconds)
        recordMetric(.pmTaskTimerStop, metadata: #"{"taskId":"\#(updated.id.uuidString)","seconds":\#(seconds)}"#)
        return updated
    }

    public func markBlocked(for root: URL, taskId: UUID, note: String?) throws {
        let rootURL = root.standardizedFileURL
        var doc = try loadTasksDocument(for: rootURL)
        guard let idx = doc.tasks.firstIndex(where: { $0.id == taskId }) else {
            throw ProjectTaskServiceError.taskNotFound(taskId)
        }
        var t = doc.tasks[idx]
        if t.activeSegment != nil {
            t = try stopTaskMutation(t, at: Date())
        }
        t.status = .blocked
        t.blockerNote = note
        doc.tasks[idx] = t
        try writeTasksDocument(doc, for: rootURL)
        let payload = note.map { #"{"taskId":"\#(taskId.uuidString)","note":"\#(escapeJSON($0))"}"# }
            ?? #"{"taskId":"\#(taskId.uuidString)"}"#
        recordMetric(.pmTaskBlocked, metadata: payload)
    }

    public func activeTask(for root: URL) throws -> PMTaskRecord? {
        try listTasks(for: root).first { $0.status == .active && $0.activeSegment != nil }
    }

    // MARK: - IO

    private func ensureDotLayout(at root: URL) throws {
        let dot = Self.dotDirectoryURL(forProjectRoot: root)
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: root.path, isDirectory: &isDir), !isDir.boolValue {
            throw ProjectTaskServiceError.invalidProjectRoot("Not a directory: \(root.path)")
        }
        do {
            try fileManager.createDirectory(at: dot, withIntermediateDirectories: true)
        } catch {
            throw ProjectTaskServiceError.ioFailed(error.localizedDescription)
        }
    }

    private func loadTasksDocument(for root: URL) throws -> PMTaskDocument {
        let url = tasksURL(for: root)
        guard fileManager.fileExists(atPath: url.path) else {
            return PMTaskDocument()
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(PMTaskDocument.self, from: data)
    }

    private func writeTasksDocument(_ doc: PMTaskDocument, for root: URL) throws {
        let url = tasksURL(for: root)
        do {
            let data = try encoder.encode(doc)
            try data.write(to: url, options: [.atomic])
        } catch {
            throw ProjectTaskServiceError.ioFailed(error.localizedDescription)
        }
    }

    private func writeManifest(_ manifest: DotProjectManifest, for root: URL) throws {
        let url = manifestURL(for: root)
        do {
            let data = try encoder.encode(manifest)
            try data.write(to: url, options: [.atomic])
        } catch {
            throw ProjectTaskServiceError.ioFailed(error.localizedDescription)
        }
    }

    private func stopTaskMutation(_ task: PMTaskRecord, at end: Date) throws -> PMTaskRecord {
        var t = task
        guard let lastIdx = t.segments.lastIndex(where: { $0.end == nil }) else {
            return t
        }
        t.segments[lastIdx].end = end
        t.status = .done
        return t
    }

    private func escapeJSON(_ s: String) -> String {
        s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private func recordMetric(_ type: DailyMetricsQueries.MetricType, metadata: String?) {
        guard let database else { return }
        Task {
            try? await database.recordMetricEvent(metricType: type, metadata: metadata)
        }
    }
}
