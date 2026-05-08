import Database
import Foundation
import SQLCipher
import Shared

public struct RecoveryAuditRequest: Sendable {
    public let sourcePaths: [String]
    public let includeDefaultSources: Bool
    public let copyDestinationPath: String?
    public let confirmCopy: Bool
    public let rewindCutoffDate: Date?

    public init(
        sourcePaths: [String] = [],
        includeDefaultSources: Bool = true,
        copyDestinationPath: String? = nil,
        confirmCopy: Bool = false,
        rewindCutoffDate: Date? = nil
    ) {
        self.sourcePaths = sourcePaths
        self.includeDefaultSources = includeDefaultSources
        self.copyDestinationPath = copyDestinationPath
        self.confirmCopy = confirmCopy
        self.rewindCutoffDate = rewindCutoffDate
    }
}

public struct RecoveryAuditManifest: Codable, Sendable {
    public let generatedAt: Date
    public let privacy: String
    public let sources: [RecoverySourceReport]
    public let databaseCandidates: [RecoveryDatabaseReport]
    public let settings: RecoverySettingsReport
    public let warnings: [String]
    public let copyResults: [RecoveryCopyResult]
}

public struct RecoverySourceReport: Codable, Sendable {
    public let sourcePath: String
    public let expandedPath: String
    public let exists: Bool
    public let isDirectory: Bool
    public let detectedKinds: [RecoveryDetectedKind]
    public let fileCount: Int
    public let totalBytes: Int64
    public let databasePaths: [String]
    public let chunkDirectories: [String]
    public let settingsPaths: [String]
    public let warnings: [String]
}

public enum RecoveryDetectedKind: String, Codable, Sendable {
    case missing
    case retraceStorageRoot
    case rewindStorageRoot
    case retraceDatabase
    case rewindEncryptedDatabase
    case rewindLegacyDatabase
    case chunksDirectory
    case segmentsDirectory
    case sqliteWALSidecar
    case sqliteSHMSidecar
    case preferencesPlist
    case binaryCookies
    case appBundle
    case unknown
}

public struct RecoveryDatabaseReport: Codable, Sendable {
    public let path: String
    public let kind: RecoveryDatabaseKind
    public let exists: Bool
    public let isReadable: Bool
    public let timestampFormat: RecoveryTimestampFormat?
    public let earliestFrameDate: Date?
    public let latestFrameDate: Date?
    public let framesBeforeCutoff: Int?
    public let framesAtOrAfterCutoff: Int?
    public let tables: [String: Int]
    public let missingTables: [String]
    public let hasWAL: Bool
    public let hasSHM: Bool
    public let warnings: [String]
}

public enum RecoveryDatabaseKind: String, Codable, Sendable {
    case retrace
    case rewind
    case rewindLegacy
    case unknown
}

public enum RecoveryTimestampFormat: String, Codable, Sendable {
    case millisecondsInteger
    case iso8601Text
    case unknown
}

public struct RecoverySettingsReport: Codable, Sendable {
    public let appSuite: String
    public let useRewindData: Bool
    public let rewindCutoffDate: Date?
    public let customRetraceDBLocation: String?
    public let encryptionEnabled: Bool
}

public struct RecoveryCopyResult: Codable, Sendable {
    public let sourcePath: String
    public let destinationPath: String
    public let copied: Bool
    public let warning: String?
}

public final class RecoveryDataAuditor {
    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let calendar: Calendar

    private let rewindPassword = "soiZ58XZJhdka55hLUp18yOtTUTDXz7Diu7Z4JzuwhRwGG13N6Z9RTVU1fGiKkuF"
    private let rewindCipherCompatibility = 4

    public init(
        fileManager: FileManager = .default,
        defaults: UserDefaults = UserDefaults(suiteName: "io.retrace.app") ?? .standard,
        calendar: Calendar = .current
    ) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.calendar = calendar
    }

    public func audit(request: RecoveryAuditRequest = RecoveryAuditRequest()) throws -> RecoveryAuditManifest {
        let sourcePaths = normalizedSourcePaths(from: request)
        let cutoff = request.rewindCutoffDate ?? ServiceContainer.rewindCutoffDate(in: defaults, calendar: calendar)
        var copyResults: [RecoveryCopyResult] = []
        var warnings: [String] = []

        let sources = sourcePaths.map { inspectSource(path: $0) }
        let databases = sources.flatMap { source in
            source.databasePaths.map { probeDatabase(path: $0, cutoffDate: cutoff) }
        }

        if request.copyDestinationPath != nil, !request.confirmCopy {
            warnings.append("copy_destination_provided_without_confirmation; pass --yes to copy sources")
        }
        if let copyDestinationPath = request.copyDestinationPath, request.confirmCopy {
            copyResults = sourcePaths.map { copySource(path: $0, destinationRoot: copyDestinationPath) }
        }

        warnings.append(contentsOf: sources.flatMap(\.warnings))
        warnings.append(contentsOf: databases.flatMap(\.warnings))

        return RecoveryAuditManifest(
            generatedAt: Date(),
            privacy: "Manifest contains filesystem metadata and database counts only; raw OCR text and screenshots are not exported.",
            sources: sources,
            databaseCandidates: databases,
            settings: RecoverySettingsReport(
                appSuite: "io.retrace.app",
                useRewindData: defaults.bool(forKey: "useRewindData"),
                rewindCutoffDate: cutoff,
                customRetraceDBLocation: defaults.string(forKey: "customRetraceDBLocation"),
                encryptionEnabled: defaults.object(forKey: "encryptionEnabled") as? Bool ?? false
            ),
            warnings: Array(Set(warnings)).sorted(),
            copyResults: copyResults
        )
    }

    private func normalizedSourcePaths(from request: RecoveryAuditRequest) -> [String] {
        var paths = request.sourcePaths
        if paths.isEmpty, request.includeDefaultSources {
            paths.append(AppPaths.expandedStorageRoot)
            paths.append(AppPaths.expandedRewindStorageRoot)
        }
        return Array(Set(paths.map(expandTilde))).sorted()
    }

    private func inspectSource(path: String) -> RecoverySourceReport {
        let expandedPath = expandTilde(path)
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: expandedPath, isDirectory: &isDirectory)

        guard exists else {
            return RecoverySourceReport(
                sourcePath: path,
                expandedPath: expandedPath,
                exists: false,
                isDirectory: false,
                detectedKinds: [.missing],
                fileCount: 0,
                totalBytes: 0,
                databasePaths: [],
                chunkDirectories: [],
                settingsPaths: [],
                warnings: ["source_missing: \(expandedPath)"]
            )
        }

        var detectedKinds: Set<RecoveryDetectedKind> = [classifyPath(expandedPath, isDirectory: isDirectory.boolValue)]
        var fileCount = 0
        var totalBytes: Int64 = 0
        var databasePaths: Set<String> = []
        var chunkDirectories: Set<String> = []
        var settingsPaths: Set<String> = []
        var warnings: [String] = []

        let urls = enumerateURLs(at: URL(fileURLWithPath: expandedPath), isDirectory: isDirectory.boolValue, warnings: &warnings)
        for url in urls {
            let itemPath = url.path
            var itemIsDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: itemPath, isDirectory: &itemIsDirectory) else { continue }

            let kind = classifyPath(itemPath, isDirectory: itemIsDirectory.boolValue)
            detectedKinds.insert(kind)

            if itemIsDirectory.boolValue {
                if kind == .chunksDirectory || kind == .segmentsDirectory {
                    chunkDirectories.insert(itemPath)
                }
                continue
            }

            fileCount += 1
            totalBytes += fileSize(at: url)

            switch kind {
            case .retraceDatabase, .rewindEncryptedDatabase, .rewindLegacyDatabase:
                databasePaths.insert(itemPath)
            case .sqliteWALSidecar, .sqliteSHMSidecar, .preferencesPlist, .binaryCookies:
                if kind == .preferencesPlist || kind == .binaryCookies {
                    settingsPaths.insert(itemPath)
                }
            default:
                break
            }
        }

        return RecoverySourceReport(
            sourcePath: path,
            expandedPath: expandedPath,
            exists: true,
            isDirectory: isDirectory.boolValue,
            detectedKinds: Array(detectedKinds).sorted(by: { $0.rawValue < $1.rawValue }),
            fileCount: fileCount,
            totalBytes: totalBytes,
            databasePaths: Array(databasePaths).sorted(),
            chunkDirectories: Array(chunkDirectories).sorted(),
            settingsPaths: Array(settingsPaths).sorted(),
            warnings: warnings
        )
    }

    private func enumerateURLs(at root: URL, isDirectory: Bool, warnings: inout [String]) -> [URL] {
        guard isDirectory else { return [root] }
        do {
            _ = try fileManager.contentsOfDirectory(atPath: root.path)
        } catch {
            warnings.append("could_not_read_directory: \(root.path) (\(error.localizedDescription))")
        }

        var enumerationWarnings: [String] = []
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: { url, error in
                enumerationWarnings.append("could_not_enumerate_item: \(url.path) (\(error.localizedDescription))")
                return true
            }
        ) else {
            warnings.append("could_not_enumerate: \(root.path)")
            return [root]
        }

        var urls = [root]
        for case let url as URL in enumerator {
            urls.append(url)
        }
        warnings.append(contentsOf: enumerationWarnings)
        return urls
    }

    private func classifyPath(_ path: String, isDirectory: Bool) -> RecoveryDetectedKind {
        let name = URL(fileURLWithPath: path).lastPathComponent

        if isDirectory {
            if name == "Retrace" { return .retraceStorageRoot }
            if name == "com.memoryvault.MemoryVault" { return .rewindStorageRoot }
            if name == "chunks" { return .chunksDirectory }
            if name == "segments" { return .segmentsDirectory }
            if name.hasSuffix(".app") { return .appBundle }
            return .unknown
        }

        switch name {
        case "retrace.db":
            return .retraceDatabase
        case "db-enc.sqlite3":
            return .rewindEncryptedDatabase
        case "rewind.db":
            return .rewindLegacyDatabase
        default:
            if name.hasSuffix("-wal") || name.hasSuffix(".db-wal") || name.hasSuffix(".sqlite3-wal") {
                return .sqliteWALSidecar
            }
            if name.hasSuffix("-shm") || name.hasSuffix(".db-shm") || name.hasSuffix(".sqlite3-shm") {
                return .sqliteSHMSidecar
            }
            if name.hasSuffix(".plist") {
                return .preferencesPlist
            }
            if name.hasSuffix(".binarycookies") {
                return .binaryCookies
            }
            return .unknown
        }
    }

    private func probeDatabase(path: String, cutoffDate: Date?) -> RecoveryDatabaseReport {
        let expandedPath = expandTilde(path)
        let kind = databaseKind(for: expandedPath)
        let hasWAL = fileManager.fileExists(atPath: "\(expandedPath)-wal")
        let hasSHM = fileManager.fileExists(atPath: "\(expandedPath)-shm")
        let exists = fileManager.fileExists(atPath: expandedPath)

        guard exists else {
            return RecoveryDatabaseReport(
                path: expandedPath,
                kind: kind,
                exists: false,
                isReadable: false,
                timestampFormat: nil,
                earliestFrameDate: nil,
                latestFrameDate: nil,
                framesBeforeCutoff: nil,
                framesAtOrAfterCutoff: nil,
                tables: [:],
                missingTables: expectedTables,
                hasWAL: hasWAL,
                hasSHM: hasSHM,
                warnings: ["database_missing: \(expandedPath)"]
            )
        }

        do {
            let connection = try makeConnection(for: kind, path: expandedPath)
            defer { close(connection) }
            guard let db = connection.getConnection() else {
                throw CLIProbeError("database connection pointer was nil")
            }

            let tables = try tableCounts(db: db)
            let missingTables = expectedTables.filter { tables[$0] == nil }
            let timestampInfo = try frameTimestampInfo(db: db, kind: kind, cutoffDate: cutoffDate)
            var warnings = missingTables.map { "missing_table: \($0)" }
            if !hasWAL, kind == .retrace {
                warnings.append("retrace database has no WAL sidecar; recent uncheckpointed frames may be missing from this copy")
            }

            return RecoveryDatabaseReport(
                path: expandedPath,
                kind: kind,
                exists: true,
                isReadable: true,
                timestampFormat: timestampInfo.format,
                earliestFrameDate: timestampInfo.earliest,
                latestFrameDate: timestampInfo.latest,
                framesBeforeCutoff: timestampInfo.beforeCutoff,
                framesAtOrAfterCutoff: timestampInfo.atOrAfterCutoff,
                tables: tables,
                missingTables: missingTables,
                hasWAL: hasWAL,
                hasSHM: hasSHM,
                warnings: warnings
            )
        } catch {
            return RecoveryDatabaseReport(
                path: expandedPath,
                kind: kind,
                exists: true,
                isReadable: false,
                timestampFormat: nil,
                earliestFrameDate: nil,
                latestFrameDate: nil,
                framesBeforeCutoff: nil,
                framesAtOrAfterCutoff: nil,
                tables: [:],
                missingTables: expectedTables,
                hasWAL: hasWAL,
                hasSHM: hasSHM,
                warnings: ["\(kind.rawValue) database could not be read: \(error.localizedDescription)"]
            )
        }
    }

    private func databaseKind(for path: String) -> RecoveryDatabaseKind {
        let name = URL(fileURLWithPath: path).lastPathComponent
        switch name {
        case "retrace.db":
            return .retrace
        case "db-enc.sqlite3":
            return .rewind
        case "rewind.db":
            return .rewindLegacy
        default:
            return .unknown
        }
    }

    private func makeConnection(for kind: RecoveryDatabaseKind, path: String) throws -> DatabaseConnection {
        switch kind {
        case .retrace, .unknown:
            return try SQLiteReadOnlyConnectionFactory.makeRetraceConnection(databasePath: path)
        case .rewind, .rewindLegacy:
            return try SQLiteReadOnlyConnectionFactory.makeRewindConnection(
                databasePath: path,
                password: rewindPassword,
                cipherCompatibility: rewindCipherCompatibility
            )
        }
    }

    private func tableCounts(db: OpaquePointer) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        let existing = Set(try stringColumnValues(db: db, sql: "SELECT name FROM sqlite_master WHERE type IN ('table', 'view')"))
        for table in expectedTables where existing.contains(table) {
            counts[table] = try intValue(db: db, sql: "SELECT COUNT(*) FROM \(table)")
        }
        return counts
    }

    private func frameTimestampInfo(
        db: OpaquePointer,
        kind: RecoveryDatabaseKind,
        cutoffDate: Date?
    ) throws -> (format: RecoveryTimestampFormat?, earliest: Date?, latest: Date?, beforeCutoff: Int?, atOrAfterCutoff: Int?) {
        let column = try frameCreatedAtColumn(db: db)
        guard let column else {
            return (nil, nil, nil, nil, nil)
        }

        let rawValues = try stringColumnValues(db: db, sql: "SELECT \(column) FROM frame WHERE \(column) IS NOT NULL ORDER BY \(column) ASC")
        guard !rawValues.isEmpty else {
            return (kind == .retrace ? .millisecondsInteger : .iso8601Text, nil, nil, nil, nil)
        }

        let parsed = rawValues.compactMap { parseTimestamp($0, preferredKind: kind) }
        let format = timestampFormat(for: rawValues[0], kind: kind)
        let earliest = parsed.min()
        let latest = parsed.max()
        let before = cutoffDate.map { cutoff in parsed.filter { $0 < cutoff }.count }
        let after = cutoffDate.map { cutoff in parsed.filter { $0 >= cutoff }.count }
        return (format, earliest, latest, before, after)
    }

    private func frameCreatedAtColumn(db: OpaquePointer) throws -> String? {
        let columns = Set(try stringColumnValues(db: db, sql: "PRAGMA table_info(frame)", columnIndex: 1))
        if columns.contains("createdAt") { return "createdAt" }
        if columns.contains("timestamp") { return "timestamp" }
        return nil
    }

    private func timestampFormat(for value: String, kind: RecoveryDatabaseKind) -> RecoveryTimestampFormat {
        if Int64(value) != nil { return .millisecondsInteger }
        if DatabaseConfig.rewindDateFormatter.date(from: value) != nil || ISO8601DateFormatter().date(from: value) != nil {
            return .iso8601Text
        }
        return kind == .retrace ? .millisecondsInteger : .unknown
    }

    private func parseTimestamp(_ value: String, preferredKind: RecoveryDatabaseKind) -> Date? {
        if let milliseconds = Int64(value) {
            return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
        }
        if let date = DatabaseConfig.rewindDateFormatter.date(from: value) {
            return date
        }
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }
        return preferredKind == .retrace ? Date(timeIntervalSince1970: 0) : nil
    }

    private func copySource(path: String, destinationRoot: String) -> RecoveryCopyResult {
        let sourcePath = expandTilde(path)
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let destinationRootURL = URL(fileURLWithPath: expandTilde(destinationRoot), isDirectory: true)
        let destinationURL = destinationRootURL
            .appendingPathComponent(safeCopyDirectoryName(for: sourceURL), isDirectory: true)

        do {
            try fileManager.createDirectory(at: destinationRootURL, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destinationURL.path) {
                return RecoveryCopyResult(
                    sourcePath: sourcePath,
                    destinationPath: destinationURL.path,
                    copied: false,
                    warning: "destination_exists"
                )
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return RecoveryCopyResult(
                sourcePath: sourcePath,
                destinationPath: destinationURL.path,
                copied: true,
                warning: nil
            )
        } catch {
            return RecoveryCopyResult(
                sourcePath: sourcePath,
                destinationPath: destinationURL.path,
                copied: false,
                warning: error.localizedDescription
            )
        }
    }

    private func safeCopyDirectoryName(for sourceURL: URL) -> String {
        let name = sourceURL.lastPathComponent.isEmpty ? "source" : sourceURL.lastPathComponent
        let stamp = Self.copyNameFormatter.string(from: Date())
        let sanitized = name
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return "\(sanitized)-\(stamp)"
    }

    private func fileSize(at url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else { return 0 }
        return Int64(values.fileSize ?? 0)
    }

    private func stringColumnValues(db: OpaquePointer, sql: String, columnIndex: Int32 = 0) throws -> [String] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CLIProbeError(String(cString: sqlite3_errmsg(db)))
        }

        var values: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, columnIndex) {
                values.append(String(cString: text))
            }
        }
        return values
    }

    private func intValue(db: OpaquePointer, sql: String) throws -> Int {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CLIProbeError(String(cString: sqlite3_errmsg(db)))
        }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func close(_ connection: DatabaseConnection) {
        if let db = connection.getConnection() {
            sqlite3_close_v2(db)
        }
    }

    private func expandTilde(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }

    private var expectedTables: [String] {
        ["segment", "frame", "video", "node", "searchRanking_content", "daily_metrics"]
    }

    private static let copyNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

private struct CLIProbeError: Error, LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
