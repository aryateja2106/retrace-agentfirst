import Foundation
import Shared

public struct PortableExportRequest: Sendable {
    public let destinationPath: String
    public let includeRewind: Bool
    public let confirmExport: Bool

    public init(
        destinationPath: String,
        includeRewind: Bool = true,
        confirmExport: Bool = false
    ) {
        self.destinationPath = destinationPath
        self.includeRewind = includeRewind
        self.confirmExport = confirmExport
    }
}

public struct PortableExportManifest: Codable, Sendable {
    public let generatedAt: Date
    public let destinationPath: String
    public let privacy: String
    public let items: [PortableExportItem]
    public let settings: RecoverySettingsReport
    public let warnings: [String]
}

public struct PortableExportItem: Codable, Sendable {
    public let sourcePath: String
    public let relativePath: String
    public let kind: PortableExportItemKind
    public let bytes: Int64
    public let copied: Bool
    public let warning: String?
}

public enum PortableExportItemKind: String, Codable, Sendable {
    case retraceDatabase
    case retraceDatabaseWAL
    case retraceDatabaseSHM
    case retraceChunks
    case retraceSegments
    case rewindDatabase
    case rewindDatabaseWAL
    case rewindDatabaseSHM
    case rewindLegacyDatabase
    case rewindChunks
    case settings
    case readme
}

public final class PortableDataExporter {
    private let fileManager: FileManager
    private let auditor: RecoveryDataAuditor

    public init(
        fileManager: FileManager = .default,
        auditor: RecoveryDataAuditor = RecoveryDataAuditor()
    ) {
        self.fileManager = fileManager
        self.auditor = auditor
    }

    public func export(request: PortableExportRequest) throws -> PortableExportManifest {
        guard request.confirmExport else {
            throw PortableExportError.confirmationRequired
        }

        let destinationURL = URL(fileURLWithPath: expandTilde(request.destinationPath), isDirectory: true)
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        let audit = try auditor.audit(request: RecoveryAuditRequest())
        var warnings = audit.warnings
        var items: [PortableExportItem] = []

        for candidate in exportCandidates(includeRewind: request.includeRewind) {
            items.append(copyCandidate(candidate, destinationRoot: destinationURL))
        }

        let settingsItem = try writeSettings(audit.settings, destinationRoot: destinationURL)
        items.append(settingsItem)

        let readmeItem = try writeReadme(destinationRoot: destinationURL)
        items.append(readmeItem)

        warnings.append(contentsOf: items.compactMap(\.warning))

        let manifest = PortableExportManifest(
            generatedAt: Date(),
            destinationPath: destinationURL.path,
            privacy: "Portable export includes databases, sidecars, chunk folders, settings, and README only. It does not include keychain secrets or decrypted OCR text outside the database.",
            items: items,
            settings: audit.settings,
            warnings: Array(Set(warnings)).sorted()
        )

        try writeJSON(manifest, to: destinationURL.appendingPathComponent("manifest.json"))
        return manifest
    }

    private func exportCandidates(includeRewind: Bool) -> [ExportCandidate] {
        var candidates: [ExportCandidate] = [
            ExportCandidate(path: AppPaths.databasePath, relativePath: "Retrace/retrace.db", kind: .retraceDatabase),
            ExportCandidate(path: "\(AppPaths.databasePath)-wal", relativePath: "Retrace/retrace.db-wal", kind: .retraceDatabaseWAL),
            ExportCandidate(path: "\(AppPaths.databasePath)-shm", relativePath: "Retrace/retrace.db-shm", kind: .retraceDatabaseSHM),
            ExportCandidate(path: "\(AppPaths.expandedStorageRoot)/chunks", relativePath: "Retrace/chunks", kind: .retraceChunks),
            ExportCandidate(path: "\(AppPaths.expandedStorageRoot)/segments", relativePath: "Retrace/segments", kind: .retraceSegments)
        ]

        if includeRewind {
            candidates.append(contentsOf: [
                ExportCandidate(path: AppPaths.rewindDBPath, relativePath: "Rewind/db-enc.sqlite3", kind: .rewindDatabase),
                ExportCandidate(path: "\(AppPaths.rewindDBPath)-wal", relativePath: "Rewind/db-enc.sqlite3-wal", kind: .rewindDatabaseWAL),
                ExportCandidate(path: "\(AppPaths.rewindDBPath)-shm", relativePath: "Rewind/db-enc.sqlite3-shm", kind: .rewindDatabaseSHM),
                ExportCandidate(path: AppPaths.rewindUnencryptedDBPath, relativePath: "Rewind/rewind.db", kind: .rewindLegacyDatabase),
                ExportCandidate(path: AppPaths.rewindChunksPath, relativePath: "Rewind/chunks", kind: .rewindChunks)
            ])
        }

        return candidates
    }

    private func copyCandidate(_ candidate: ExportCandidate, destinationRoot: URL) -> PortableExportItem {
        let sourcePath = expandTilde(candidate.path)
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let destinationURL = destinationRoot.appendingPathComponent(candidate.relativePath)

        guard fileManager.fileExists(atPath: sourcePath) else {
            return PortableExportItem(
                sourcePath: sourcePath,
                relativePath: candidate.relativePath,
                kind: candidate.kind,
                bytes: 0,
                copied: false,
                warning: "missing_source: \(sourcePath)"
            )
        }

        do {
            try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return PortableExportItem(
                sourcePath: sourcePath,
                relativePath: candidate.relativePath,
                kind: candidate.kind,
                bytes: byteCount(at: destinationURL),
                copied: true,
                warning: nil
            )
        } catch {
            return PortableExportItem(
                sourcePath: sourcePath,
                relativePath: candidate.relativePath,
                kind: candidate.kind,
                bytes: 0,
                copied: false,
                warning: error.localizedDescription
            )
        }
    }

    private func writeSettings(_ settings: RecoverySettingsReport, destinationRoot: URL) throws -> PortableExportItem {
        let url = destinationRoot.appendingPathComponent("settings/retrace-settings.json")
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeJSON(settings, to: url)
        return PortableExportItem(
            sourcePath: "UserDefaults(io.retrace.app)",
            relativePath: "settings/retrace-settings.json",
            kind: .settings,
            bytes: byteCount(at: url),
            copied: true,
            warning: nil
        )
    }

    private func writeReadme(destinationRoot: URL) throws -> PortableExportItem {
        let url = destinationRoot.appendingPathComponent("README.md")
        let readme = """
        # Retrace Portable Export

        This folder is a local-only Retrace data export.

        ## Contents

        - `Retrace/`: native Retrace database, WAL/SHM sidecars when present, and video chunk/segment folders when present.
        - `Rewind/`: Rewind/MemoryVault database and chunks when present and included.
        - `settings/retrace-settings.json`: non-secret settings needed to understand data source visibility.
        - `manifest.json`: privacy-safe inventory of copied items and warnings.

        ## Privacy

        This export does not include Keychain secrets or decrypted OCR text outside the copied databases. Encrypted databases may still require the original machine's recovery material or Keychain-backed keys to read.

        """
        try readme.write(to: url, atomically: true, encoding: .utf8)
        return PortableExportItem(
            sourcePath: "generated",
            relativePath: "README.md",
            kind: .readme,
            bytes: byteCount(at: url),
            copied: true,
            warning: nil
        )
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func byteCount(at url: URL) -> Int64 {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if isDirectory.boolValue {
            guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
                return 0
            }
            var total: Int64 = 0
            for case let childURL as URL in enumerator {
                total += Int64((try? childURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
            return total
        }
        return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    private func expandTilde(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }
}

private struct ExportCandidate {
    let path: String
    let relativePath: String
    let kind: PortableExportItemKind
}

public enum PortableExportError: Error, LocalizedError {
    case confirmationRequired

    public var errorDescription: String? {
        switch self {
        case .confirmationRequired:
            return "portable export requires explicit confirmation"
        }
    }
}
