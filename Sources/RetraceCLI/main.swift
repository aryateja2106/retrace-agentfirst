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
        guard args.first == "inspect" || args.first == nil || args.first == "--help" else {
            throw CLIError("unknown storage command. Try retrace-cli storage inspect --json", exitCode: 64)
        }
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
    }

    private func runOllama(_ args: [String]) async throws {
        guard args.first == "status" || args.first == nil || args.first == "--help" else {
            throw CLIError("unknown ollama command. Try retrace-cli ollama status --json", exitCode: 64)
        }
        let options = Options(Array(args.dropFirst()))
        let baseURL = URL(string: options.string("base-url", defaultValue: "http://localhost:11434"))!
        let model = options.string("model", defaultValue: "gemma4:e2b")
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
            let baseURL = URL(string: options.string("base-url", defaultValue: "http://localhost:11434"))!
            let model = options.string("model", defaultValue: "gemma4:e2b")
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
      ollama status [--model gemma4:e2b] [--json]

    Privacy:
      No localhost API or MCP server is started. Read commands use a read-only SQLite connection.
      Journal write commands require --yes unless --dry-run is used.
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
    let flags: Set<String>
    let positionals: [String]

    init(_ args: [String]) {
        var values: [String: String] = [:]
        var flags: Set<String> = []
        var positionals: [String] = []
        var index = 0

        while index < args.count {
            let arg = args[index]
            if arg.hasPrefix("--") {
                let name = String(arg.dropFirst(2))
                if index + 1 < args.count, !args[index + 1].hasPrefix("--") {
                    values[name] = args[index + 1]
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

private struct CLIError: Error {
    let message: String
    let exitCode: Int32

    init(_ message: String, exitCode: Int32 = 1) {
        self.message = message
        self.exitCode = exitCode
    }
}
