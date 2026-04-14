import Foundation

// MARK: - On-disk layout (per project folder)

public enum DotProjectLayout {
    /// Hidden folder at the root of a tracked project (e.g. git repo).
    public static let dotDirectoryName = ".dot"
    public static let manifestFileName = "arya-retrace.json"
    public static let tasksFileName = "tasks.json"
}

// MARK: - Manifest

public struct DotProjectManifest: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var projectId: UUID
    public var rootPath: String
    public var displayName: String
    public var createdAt: Date

    public init(schemaVersion: Int = 1, projectId: UUID, rootPath: String, displayName: String, createdAt: Date) {
        self.schemaVersion = schemaVersion
        self.projectId = projectId
        self.rootPath = rootPath
        self.displayName = displayName
        self.createdAt = createdAt
    }
}

// MARK: - Tasks

public enum PMTaskStatus: String, Codable, Sendable, CaseIterable {
    case planned
    case active
    case done
    case blocked
}

public struct PMTimeSegment: Codable, Sendable, Equatable {
    public var start: Date
    public var end: Date?

    public init(start: Date, end: Date? = nil) {
        self.start = start
        self.end = end
    }

    public var durationOrOpen: TimeInterval {
        let endDate = end ?? Date()
        return endDate.timeIntervalSince(start)
    }
}

public struct PMTaskRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var status: PMTaskStatus
    public var blockerNote: String?
    public var segments: [PMTimeSegment]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        status: PMTaskStatus = .planned,
        blockerNote: String? = nil,
        segments: [PMTimeSegment] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.blockerNote = blockerNote
        self.segments = segments
        self.createdAt = createdAt
    }

    /// Total tracked time across closed segments plus open segment if any.
    public var totalTrackedSeconds: TimeInterval {
        segments.reduce(0) { $0 + $1.durationOrOpen }
    }

    public var activeSegment: PMTimeSegment? {
        segments.last(where: { $0.end == nil })
    }
}

public struct PMTaskDocument: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var tasks: [PMTaskRecord]

    public init(schemaVersion: Int = 1, tasks: [PMTaskRecord] = []) {
        self.schemaVersion = schemaVersion
        self.tasks = tasks
    }
}
