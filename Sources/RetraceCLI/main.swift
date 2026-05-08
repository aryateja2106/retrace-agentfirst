import App
import Darwin
import Database
import Foundation
import Shared

@main
struct RetraceCLI {
    static func main() async {
        do {
            try await Command(arguments: Array(CommandLine.arguments.dropFirst())).run()
        } catch let error as CLIError {
            fputs("retrace-cli: \(error.message)\n", stderr)
            exit(error.exitCode)
        } catch {
            fputs("retrace-cli: \(error)\n", stderr)
            exit(1)
        }
    }
}

private struct Command {
    var arguments: [String]

    func run() async throws {
        guard let group = arguments.first else {
            print(Self.help)
            return
        }

        switch group {
        case "-h", "--help", "help":
            print(Self.help)
        case "context":
            try runContext(Array(arguments.dropFirst()))
        case "journal":
            try await runJournal(Array(arguments.dropFirst()))
        case "recording":
            try runRecording(Array(arguments.dropFirst()))
        case "storage":
            try runStorage(Array(arguments.dropFirst()))
        case "ollama":
            try await runOllama(Array(arguments.dropFirst()))
        default:
            throw CLIError("unknown command '\(group)'. Run retrace-cli --help.", exitCode: 64)
        }
    }

    private func runContext(_ args: [String]) throws {
        guard let subcommand = args.first else {
            print(Self.contextHelp)
            return
        }
        let options = Options(Array(args.dropFirst()))
        let range = try options.dateRange(defaultHours: subcommand == "search" ? 24 : 1)
        let limit = options.int("limit", defaultValue: subcommand == "search" ? 20 : 50)
        let maxChars = options.int("max-chars-per-frame", defaultValue: 1_500)
        let outputJSON = options.flag("json")
        let connection = try SQLiteReadOnlyConnectionFactory.makeRetraceConnection(
            databasePath: options.string("db", defaultValue: AppPaths.databasePath)
        )

        let samples: [ActivityContextQueries.Sample]
        switch subcommand {
        case "recent":
            samples = try ActivityContextQueries.fetchSamples(
                connection: connection,
                from: range.start,
                to: range.end,
                limit: limit,
                maxTextLength: maxChars,
                newestFirst: true
            )
        case "search":
            let query = options.positionals.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                throw CLIError("context search requires a query. Example: retrace-cli context search \"pull request\" --json", exitCode: 64)
            }
            samples = try ActivityContextQueries.searchSamples(
                connection: connection,
                query: query,
                from: range.start,
                to: range.end,
                limit: limit,
                maxTextLength: maxChars
            )
        case "-h", "--help", "help":
            print(Self.contextHelp)
            return
        default:
            throw CLIError("unknown context command '\(subcommand)'", exitCode: 64)
        }

        if outputJSON {
            try printJSON(ContextResponse(samples: samples))
        } else {
            print(samples.map(Self.renderSample).joined(separator: "\n\n"))
        }
    }

    private func runJournal(_ args: [String]) async throws {
        guard let subcommand = args.first else {
            print(Self.journalHelp)
            return
        }
        let options = Options(Array(args.dropFirst()))
        let folder = URL(
            fileURLWithPath: options.string(
                "folder",
                defaultValue: DailyJournalConfiguration.defaultJournalFolderPath()
            ),
            isDirectory: true
        )
        let writer = DailyJournalWriter(folder: folder)

        switch subcommand {
        case "today":
            try printJournalFile(writer.fileURL(for: Date()), json: options.flag("json"))
        case "day":
            guard let day = options.string("date") else {
                throw CLIError("journal day requires --date YYYY-MM-DD", exitCode: 64)
            }
            guard let date = Self.dayFormatter.date(from: day) else {
                throw CLIError("invalid --date '\(day)'; expected YYYY-MM-DD", exitCode: 64)
            }
            try printJournalFile(writer.fileURL(for: date), json: options.flag("json"))
        case "append":
            let text = try readAppendText(options)
            guard options.flag("yes") else {
                throw CLIError("journal append writes local markdown; pass --yes to confirm", exitCode: 64)
            }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let fileURL = writer.fileURL(for: Date())
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try """
                ---
                source: retrace-cli
                privacy: local-only
                ---

                # \(Self.displayDayFormatter.string(from: Date()))

                """.write(to: fileURL, atomically: true, encoding: .utf8)
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("\n## Manual Note\n\n\(text)\n".utf8))
            try handle.close()
            try printJSONOrText(["path": fileURL.path], json: options.flag("json"))
        case "generate":
            guard options.flag("yes") || options.flag("dry-run") else {
                throw CLIError("journal generate may call local Ollama and write markdown; pass --yes or --dry-run", exitCode: 64)
            }
            let result = try await generateJournal(options: options, folder: folder)
            if options.flag("json") {
                try printJSON(result)
            } else {
                print(result.filePath ?? result.reason ?? result.status.rawValue)
            }
        case "-h", "--help", "help":
            print(Self.journalHelp)
        default:
            throw CLIError("unknown journal command '\(subcommand)'", exitCode: 64)
        }
    }

    private func runRecording(_ args: [String]) throws {
        guard args.first == "status" || args.first == nil || args.first == "--help" else {
            throw CLIError("unknown recording command. Try retrace-cli recording status --json", exitCode: 64)
        }
        let defaults = UserDefaults(suiteName: "io.retrace.app") ?? .standard
        let response = RecordingStatusResponse(
            shouldAutoStart: AppCoordinator.shouldAutoStartRecording(),
            wasRecordingBeforeLastExit: defaults.bool(forKey: "wasRecordingBeforeLastExit")
        )
        if Options(Array(args.dropFirst())).flag("json") || args.contains("--json") {
            try printJSON(response)
        } else {
            print("auto-start: \(response.shouldAutoStart)")
            print("was-recording-before-last-exit: \(response.wasRecordingBeforeLastExit)")
        }
    }

    private func runStorage(_ args: [String]) throws {
        guard let subcommand = args.first else {
            print(Self.storageHelp)
            return
        }

        switch subcommand {
        case "inspect":
            let options = Options(Array(args.dropFirst()))
            let dbPath = options.string("db", defaultValue: AppPaths.databasePath)
            let response = StorageInspectResponse(
                storageRoot: AppPaths.expandedStorageRoot,
                databasePath: dbPath,
                databaseExists: FileManager.default.fileExists(atPath: NSString(string: dbPath).expandingTildeInPath),
                journalFolder: options.string("folder", defaultValue: DailyJournalConfiguration.defaultJournalFolderPath())
            )
            if options.flag("json") || args.contains("--json") {
                try printJSON(response)
            } else {
                print("storage-root: \(response.storageRoot)")
                print("database: \(response.databasePath) exists=\(response.databaseExists)")
                print("journal-folder: \(response.journalFolder)")
            }
        case "audit", "recover-audit":
            try runStorageAudit(Array(args.dropFirst()))
        case "export":
            try runStorageExport(Array(args.dropFirst()))
        case "adopt":
            try runStorageAdopt(Array(args.dropFirst()))
        case "-h", "--help", "help":
            print(Self.storageHelp)
        default:
            throw CLIError("unknown storage command. Try retrace-cli storage audit --help", exitCode: 64)
        }
    }

    private func runStorageExport(_ args: [String]) throws {
        let options = Options(args)
        if options.flag("help") || options.flag("h") {
            print(Self.storageExportHelp)
            return
        }
        guard let destinationPath = options.string("to") else {
            throw CLIError("storage export requires --to PATH. Example: retrace-cli storage export --to ~/Retrace-Export --yes", exitCode: 64)
        }
        guard options.flag("yes") else {
            throw CLIError("storage export copies local data; pass --yes to confirm", exitCode: 64)
        }

        let manifest = try PortableDataExporter().export(
            request: PortableExportRequest(
                destinationPath: destinationPath,
                includeRewind: !options.flag("exclude-rewind"),
                confirmExport: true
            )
        )

        if options.flag("json") {
            try printJSON(manifest)
        } else {
            print("export: \(manifest.destinationPath)")
            print("items-copied: \(manifest.items.filter { $0.copied }.count)")
            print("warnings: \(manifest.warnings.count)")
            print("manifest: \(URL(fileURLWithPath: manifest.destinationPath).appendingPathComponent("manifest.json").path)")
        }
    }

    private func runStorageAdopt(_ args: [String]) throws {
        let options = Options(args)
        if options.flag("help") || options.flag("h") {
            print(Self.storageAdoptHelp)
            return
        }
        guard options.flag("yes") else {
            throw CLIError("storage adopt changes the app's active data folder; pass --yes to confirm", exitCode: 64)
        }

        let defaults = UserDefaults(suiteName: "io.retrace.app") ?? .standard
        if options.flag("default") {
            defaults.removeObject(forKey: "customRetraceDBLocation")
            defaults.synchronize()
            let response = StorageAdoptResponse(
                storageRoot: AppPaths.defaultStorageRoot,
                databasePath: "\(AppPaths.defaultStorageRoot)/retrace.db",
                databaseExists: FileManager.default.fileExists(atPath: "\(AppPaths.defaultStorageRoot)/retrace.db"),
                customLocationSet: false,
                restartRequired: true,
                warnings: []
            )
            try printStorageAdoptResponse(response, json: options.flag("json"))
            return
        }

        guard let rawSourcePath = options.string("from") ?? options.positionals.first else {
            throw CLIError("storage adopt requires --from PATH or --default. Example: retrace-cli storage adopt --from ~/Retrace-Recovery/Retrace --yes", exitCode: 64)
        }

        let expandedSourcePath = NSString(string: rawSourcePath).expandingTildeInPath
        let sourcePath = normalizedRetraceStorageRoot(from: expandedSourcePath)
        let databasePath = "\(sourcePath)/retrace.db"
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: databasePath) else {
            throw CLIError("no retrace.db found at \(databasePath)", exitCode: 66)
        }

        let manifest = try RecoveryDataAuditor().audit(
            request: RecoveryAuditRequest(
                sourcePaths: [sourcePath],
                includeDefaultSources: false
            )
        )
        let matchingDatabase = manifest.databaseCandidates.first {
            $0.path == databasePath && $0.kind == .retrace && $0.isReadable
        }
        guard matchingDatabase != nil else {
            let warnings = manifest.warnings.isEmpty ? "no readable Retrace database candidate found" : manifest.warnings.joined(separator: "; ")
            throw CLIError("could not adopt \(sourcePath): \(warnings)", exitCode: 66)
        }

        defaults.set(sourcePath, forKey: "customRetraceDBLocation")
        defaults.synchronize()

        var warnings = manifest.warnings
        if sourcePath.contains("/.Trash/") {
            warnings.append("adopted_path_is_in_trash: move or copy this folder to a stable location before relying on it")
        }

        let response = StorageAdoptResponse(
            storageRoot: sourcePath,
            databasePath: databasePath,
            databaseExists: true,
            customLocationSet: true,
            restartRequired: true,
            warnings: warnings
        )
        try printStorageAdoptResponse(response, json: options.flag("json"))
    }

    private func runStorageAudit(_ args: [String]) throws {
        let options = Options(args)
        if options.flag("help") || options.flag("h") {
            print(Self.storageAuditHelp)
            return
        }

        var sourcePaths = options.positionals + options.strings("path")
        if options.flag("include-defaults") {
            sourcePaths.append(AppPaths.expandedStorageRoot)
            sourcePaths.append(AppPaths.expandedRewindStorageRoot)
        }

        let cutoff = try options.string("rewind-cutoff").map(parseISO8601Date)
        let copyDestination = options.string("copy-to")
        let manifestPath = options.string("manifest")
        let auditor = RecoveryDataAuditor()
        let manifest = try auditor.audit(
            request: RecoveryAuditRequest(
                sourcePaths: sourcePaths,
                includeDefaultSources: !options.flag("no-defaults"),
                copyDestinationPath: copyDestination,
                confirmCopy: options.flag("yes"),
                rewindCutoffDate: cutoff
            )
        )

        if let manifestPath {
            try writeJSON(manifest, to: manifestPath)
        }

        if options.flag("json") {
            try printJSON(manifest)
        } else {
            printRecoveryAudit(manifest, manifestPath: manifestPath)
        }
    }

    private func runOllama(_ args: [String]) async throws {
        guard args.first == "status" || args.first == nil || args.first == "--help" else {
            throw CLIError("unknown ollama command. Try retrace-cli ollama status --json", exitCode: 64)
        }
        let options = Options(Array(args.dropFirst()))
        let baseURL = URL(string: options.string("base-url", defaultValue: DailyJournalConfiguration.defaultOllamaBaseURLString))!
        let model = options.string("model", defaultValue: DailyJournalConfiguration.defaultOllamaModel)
        let status = try await OllamaClient(baseURL: baseURL).status(model: model)
        if options.flag("json") || args.contains("--json") {
            try printJSON(status)
        } else {
            print("reachable: \(status.isReachable)")
            print("model-installed: \(status.isModelInstalled)")
            print("models: \(status.installedModels.joined(separator: ", "))")
        }
    }

    private func generateJournal(options: Options, folder: URL) async throws -> JournalGenerationResult {
        let range = try options.dateRange(defaultHours: 1)
        let connection = try SQLiteReadOnlyConnectionFactory.makeRetraceConnection(
            databasePath: options.string("db", defaultValue: AppPaths.databasePath)
        )
        let samples = try ActivityContextQueries.fetchSamples(
            connection: connection,
            from: range.start,
            to: range.end,
            limit: options.int("limit", defaultValue: 120),
            maxTextLength: options.int("max-chars-per-frame", defaultValue: 2_000),
            newestFirst: false
        )
        let digest = ActivityContextDigest(
            startDate: range.start,
            endDate: range.end,
            samples: samples,
            promptText: samples.map(Self.renderSample).joined(separator: "\n\n"),
            appNames: Array(Set(samples.map(\.displayAppName))).sorted()
        )
        guard digest.promptText.count >= 400 else {
            return JournalGenerationResult(
                status: .skipped,
                reason: "not_enough_completed_ocr",
                filePath: nil,
                startDate: range.start,
                endDate: range.end
            )
        }

        let prompt = JournalPromptRenderer.render(digest: digest)
        let writer = DailyJournalWriter(folder: folder)
        if writer.containsWindow(startDate: range.start, endDate: range.end) {
            return JournalGenerationResult(
                status: .skipped,
                reason: "already_summarized",
                filePath: writer.fileURL(for: range.start).path,
                startDate: range.start,
                endDate: range.end
            )
        }

        let summary: String
        if options.flag("dry-run") {
            summary = prompt
        } else {
            let baseURL = URL(string: options.string("base-url", defaultValue: DailyJournalConfiguration.defaultOllamaBaseURLString))!
            let model = options.string("model", defaultValue: DailyJournalConfiguration.defaultOllamaModel)
            summary = try await OllamaClient(baseURL: baseURL).summarize(prompt: prompt, model: model)
        }

        if options.flag("dry-run") {
            return JournalGenerationResult(
                status: .generated,
                reason: "dry_run",
                filePath: nil,
                startDate: range.start,
                endDate: range.end
            )
        }

        let fileURL = try writer.append(
            summary: summary,
            startDate: range.start,
            endDate: range.end,
            sampleCount: samples.count,
            appNames: digest.appNames,
            dryRun: options.flag("dry-run")
        )
        return JournalGenerationResult(status: .generated, reason: nil, filePath: fileURL.path, startDate: range.start, endDate: range.end)
    }

    private func readAppendText(_ options: Options) throws -> String {
        if let text = options.string("text") {
            return text
        }
        if let file = options.string("file") {
            return try String(contentsOfFile: file, encoding: .utf8)
        }
        if options.flag("stdin") {
            return String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
        }
        throw CLIError("journal append requires --text, --file, or --stdin", exitCode: 64)
    }

    private func printJournalFile(_ fileURL: URL, json: Bool) throws {
        let exists = FileManager.default.fileExists(atPath: fileURL.path)
        let content = exists ? (try String(contentsOf: fileURL, encoding: .utf8)) : ""
        if json {
            try printJSON(JournalReadResponse(path: fileURL.path, exists: exists, content: content))
        } else if exists {
            print(content)
        } else {
            throw CLIError("journal file not found at \(fileURL.path)", exitCode: 66)
        }
    }

    private static func renderSample(_ sample: ActivityContextQueries.Sample) -> String {
        let formatter = ISO8601DateFormatter()
        let parts = [sample.displayAppName, sample.windowName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return """
        [\(formatter.string(from: sample.timestamp))] \(parts.joined(separator: " - "))
        \(sample.mainText)
        """
    }

    private func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        print(String(data: data, encoding: .utf8) ?? "{}")
    }

    private func printJSONOrText(_ value: [String: String], json: Bool) throws {
        if json {
            try printJSON(value)
        } else {
            for (key, value) in value.sorted(by: { $0.key < $1.key }) {
                print("\(key): \(value)")
            }
        }
    }

    private func writeJSON<T: Encodable>(_ value: T, to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        let expandedPath = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func normalizedRetraceStorageRoot(from path: String) -> String {
        let nsPath = path as NSString
        if nsPath.lastPathComponent == "retrace.db" {
            return nsPath.deletingLastPathComponent
        }
        return path
    }

    private func printStorageAdoptResponse(_ response: StorageAdoptResponse, json: Bool) throws {
        if json {
            try printJSON(response)
            return
        }

        print("storage-root: \(response.storageRoot)")
        print("database: \(response.databasePath) exists=\(response.databaseExists)")
        print("custom-location-set: \(response.customLocationSet)")
        print("restart-required: \(response.restartRequired)")
        if !response.warnings.isEmpty {
            print("warnings:")
            for warning in response.warnings {
                print("  - \(warning)")
            }
        }
    }

    private func printRecoveryAudit(_ manifest: RecoveryAuditManifest, manifestPath: String?) {
        print("generated-at: \(ISO8601DateFormatter().string(from: manifest.generatedAt))")
        if let manifestPath {
            print("manifest: \(manifestPath)")
        }
        print("sources: \(manifest.sources.count)")
        print("databases: \(manifest.databaseCandidates.count)")
        print("use-rewind-data: \(manifest.settings.useRewindData)")
        if let cutoff = manifest.settings.rewindCutoffDate {
            print("rewind-cutoff: \(ISO8601DateFormatter().string(from: cutoff))")
        }

        for source in manifest.sources {
            print("")
            print("source: \(source.expandedPath)")
            print("  exists: \(source.exists)")
            print("  kinds: \(source.detectedKinds.map(\.rawValue).joined(separator: ","))")
            print("  files: \(source.fileCount)")
            print("  bytes: \(source.totalBytes)")
            if !source.databasePaths.isEmpty {
                print("  databases: \(source.databasePaths.joined(separator: ","))")
            }
            if !source.chunkDirectories.isEmpty {
                print("  chunks: \(source.chunkDirectories.joined(separator: ","))")
            }
        }

        for database in manifest.databaseCandidates {
            print("")
            print("database: \(database.path)")
            print("  kind: \(database.kind.rawValue)")
            print("  readable: \(database.isReadable)")
            let tableSummary = database.tables.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",")
            print("  tables: \(tableSummary)")
            if let earliest = database.earliestFrameDate {
                print("  earliest-frame: \(ISO8601DateFormatter().string(from: earliest))")
            }
            if let latest = database.latestFrameDate {
                print("  latest-frame: \(ISO8601DateFormatter().string(from: latest))")
            }
            if let before = database.framesBeforeCutoff, let after = database.framesAtOrAfterCutoff {
                print("  rewind-cutoff-visibility: before=\(before) at-or-after=\(after)")
            }
        }

        if !manifest.copyResults.isEmpty {
            print("")
            print("copies:")
            for result in manifest.copyResults {
                print("  \(result.copied ? "copied" : "skipped"): \(result.sourcePath) -> \(result.destinationPath)")
                if let warning = result.warning {
                    print("    warning: \(warning)")
                }
            }
        }

        if !manifest.warnings.isEmpty {
            print("")
            print("warnings:")
            for warning in manifest.warnings {
                print("  - \(warning)")
            }
        }
    }

    private func parseISO8601Date(_ value: String) throws -> Date {
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }
        throw CLIError("invalid ISO8601 date '\(value)'", exitCode: 64)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let displayDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()

    static let help = """
    retrace-cli - private local Retrace context access for agents

    Commands:
      context recent [--hours 1] [--json]
      context search QUERY [--hours 24] [--json]
      journal today [--json]
      journal day --date YYYY-MM-DD [--json]
      journal append --text TEXT --yes
      journal generate --from ISO8601 --to ISO8601 --dry-run --json
      recording status [--json]
      storage inspect [--json]
      storage audit [SOURCE ...] [--json] [--manifest PATH]
      ollama status [--model gemma4:e4b] [--json]

    Privacy:
      No localhost API or MCP server is started. Read commands use a read-only SQLite connection.
      Journal write commands require --yes unless --dry-run is used.
    """

    static let storageHelp = """
    Usage:
      retrace-cli storage inspect --json
      retrace-cli storage audit [SOURCE ...] --json
      retrace-cli storage audit [SOURCE ...] --manifest recovery-manifest.json
      retrace-cli storage export --to ~/Retrace-Export --yes
      retrace-cli storage adopt --from ~/Retrace-Recovery/Retrace --yes

    Commands:
      inspect      Show current Retrace storage paths
      audit        Read-only recovery inventory for Retrace/Rewind/Trash sources
      export       Copy a portable local export folder with manifest and README
      adopt        Make the app use an existing Retrace folder on next launch

    Run retrace-cli storage audit --help, retrace-cli storage export --help, or retrace-cli storage adopt --help for options.
    """

    static let storageAuditHelp = """
    Usage:
      retrace-cli storage audit [SOURCE ...] --json
      retrace-cli storage audit /path/from/Trash --manifest ~/Desktop/retrace-recovery.json
      retrace-cli storage audit /path/from/Trash --copy-to ~/Retrace-Recovery --yes

    Options:
      --json                    Print privacy-safe JSON manifest
      --manifest PATH           Write the JSON manifest to PATH
      --path PATH               Add a source path to inspect; can be repeated
      --include-defaults        Include default Retrace and Rewind App Support paths in addition to SOURCE
      --no-defaults             Do not inspect defaults when SOURCE is omitted
      --copy-to PATH            Copy each source into PATH; requires --yes
      --yes                     Confirm copy operation requested by --copy-to
      --rewind-cutoff ISO8601   Override Rewind cutoff diagnostics

    Privacy:
      The audit records filesystem metadata and database counts only. It does not export raw OCR text,
      screenshots, videos, keychain material, or SQLCipher secrets.
    """

    static let storageExportHelp = """
    Usage:
      retrace-cli storage export --to ~/Retrace-Export --yes
      retrace-cli storage export --to ~/Retrace-Export --exclude-rewind --yes --json

    Options:
      --to PATH           Destination folder for the portable export
      --yes               Confirm local data copy
      --exclude-rewind    Skip Rewind/MemoryVault database and chunks
      --json              Print export manifest JSON

    Privacy:
      Export copies local databases and chunk folders as files. It does not copy Keychain secrets
      or decrypt OCR text outside the databases.
    """

    static let storageAdoptHelp = """
    Usage:
      retrace-cli storage adopt --from ~/Retrace-Recovery/Retrace --yes
      retrace-cli storage adopt ~/Library/Application\\ Support/Retrace --yes --json
      retrace-cli storage adopt --default --yes

    Options:
      --from PATH    Existing Retrace storage folder, or a retrace.db file inside it
      --default      Clear the custom folder and return to ~/Library/Application Support/Retrace
      --yes          Confirm changing the app's active data folder
      --json         Print result JSON

    Notes:
      This does not copy or delete data. It updates the shared Retrace settings suite so
      the app opens the selected folder after restart.
    """

    static let contextHelp = """
    Usage:
      retrace-cli context recent --hours 1 --limit 50 --json
      retrace-cli context search "pull request" --hours 24 --json

    Options:
      --db PATH                 Retrace database path (default: app default)
      --from ISO8601 --to ISO8601
      --hours N
      --limit N
      --max-chars-per-frame N
      --json
    """

    static let journalHelp = """
    Usage:
      retrace-cli journal today --json
      retrace-cli journal day --date 2026-05-02
      retrace-cli journal append --stdin --yes
      retrace-cli journal generate --hours 1 --dry-run --json

    Options:
      --folder PATH
      --from ISO8601 --to ISO8601
      --hours N
      --model NAME
      --base-url URL
      --dry-run
      --yes
      --json
    """
}

private struct Options {
    let values: [String: String]
    let repeatedValues: [String: [String]]
    let flags: Set<String>
    let positionals: [String]

    init(_ args: [String]) {
        var values: [String: String] = [:]
        var repeatedValues: [String: [String]] = [:]
        var flags: Set<String> = []
        var positionals: [String] = []
        var index = 0

        while index < args.count {
            let arg = args[index]
            if arg.hasPrefix("--") {
                let name = String(arg.dropFirst(2))
                if index + 1 < args.count, !args[index + 1].hasPrefix("--") {
                    let value = args[index + 1]
                    values[name] = value
                    repeatedValues[name, default: []].append(value)
                    index += 2
                } else {
                    flags.insert(name)
                    index += 1
                }
            } else {
                positionals.append(arg)
                index += 1
            }
        }

        self.values = values
        self.repeatedValues = repeatedValues
        self.flags = flags
        self.positionals = positionals
    }

    func flag(_ name: String) -> Bool {
        flags.contains(name)
    }

    func string(_ name: String) -> String? {
        values[name]
    }

    func string(_ name: String, defaultValue: String) -> String {
        values[name] ?? defaultValue
    }

    func strings(_ name: String) -> [String] {
        repeatedValues[name] ?? []
    }

    func int(_ name: String, defaultValue: Int) -> Int {
        values[name].flatMap(Int.init) ?? defaultValue
    }

    func dateRange(defaultHours: Double) throws -> (start: Date, end: Date) {
        let end = try values["to"].map(parseDate) ?? Date()
        let start = try values["from"].map(parseDate)
            ?? end.addingTimeInterval(-3_600 * (Double(values["hours"] ?? "") ?? defaultHours))
        return (start, end)
    }

    private func parseDate(_ value: String) throws -> Date {
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }
        throw CLIError("invalid date '\(value)'; expected ISO8601", exitCode: 64)
    }
}

private struct ContextResponse: Encodable {
    let samples: [ActivityContextQueries.Sample]
}

private struct JournalReadResponse: Encodable {
    let path: String
    let exists: Bool
    let content: String
}

private struct RecordingStatusResponse: Encodable {
    let shouldAutoStart: Bool
    let wasRecordingBeforeLastExit: Bool
}

private struct StorageInspectResponse: Encodable {
    let storageRoot: String
    let databasePath: String
    let databaseExists: Bool
    let journalFolder: String
}

private struct StorageAdoptResponse: Encodable {
    let storageRoot: String
    let databasePath: String
    let databaseExists: Bool
    let customLocationSet: Bool
    let restartRequired: Bool
    let warnings: [String]
}

private struct CLIError: Error {
    let message: String
    let exitCode: Int32

    init(_ message: String, exitCode: Int32 = 1) {
        self.message = message
        self.exitCode = exitCode
    }
}
