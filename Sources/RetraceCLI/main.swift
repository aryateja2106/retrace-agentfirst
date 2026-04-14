import App
import AppKit
import Database
import Darwin
import Foundation
import Search
import Shared

private let retraceCLIVersion = "0.0.1"

private enum CLIError: LocalizedError {
    case usage(String)
    case accessDisabled
    case invalidArgument(String)
    case socketUnavailable
    case taskNotFound(String)
    case databaseUnavailable(String)
    case frameSearchDisabled

    var errorDescription: String? {
        switch self {
        case .usage(let message):
            return message
        case .accessDisabled:
            return "CLI access is disabled. Enable it in arya-retrace Settings > Advanced > Terminal Memory."
        case .invalidArgument(let message):
            return message
        case .socketUnavailable:
            return "arya-retrace socket is unavailable (is the app running?)."
        case .taskNotFound(let taskID):
            return "Terminal task \(taskID) was not found."
        case .databaseUnavailable(let message):
            return message
        case .frameSearchDisabled:
            return "Frame search is disabled. Enable 'Allow agent frame search' in arya-retrace settings."
        }
    }
}

private struct ParsedArguments {
    let values: [String: String]
    let flags: Set<String>
    let positionals: [String]
}

private struct CLIContext {
    let jsonOutput: Bool
    let defaults = UserDefaults(suiteName: AryaRetraceIdentity.userDefaultsSuiteName) ?? .standard
    let encoder: JSONEncoder
    let decoder: JSONDecoder
    let iso8601: ISO8601DateFormatter

    init(jsonOutput: Bool) {
        self.jsonOutput = jsonOutput

        let encoder = JSONEncoder()
        encoder.outputFormatting = jsonOutput ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.iso8601 = formatter
    }

    var isCLIAccessEnabled: Bool {
        defaults.object(forKey: TerminalMemoryService.cliAccessEnabledDefaultsKey) as? Bool ?? false
    }

    var allowAgentFrameSearch: Bool {
        defaults.object(forKey: TerminalMemoryService.allowAgentFrameSearchDefaultsKey) as? Bool ?? false
    }

    func requireAccess() throws {
        guard isCLIAccessEnabled else {
            throw CLIError.accessDisabled
        }
    }

    func emit(_ response: TerminalMemoryCLIResponse) throws {
        if jsonOutput {
            let data = try encoder.encode(response)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }

        if let tasks = response.tasks {
            if tasks.isEmpty {
                print("No terminal tasks found.")
                return
            }

            for task in tasks {
                let duration = formatDuration(task.duration)
                let cwd = task.workingDirectory ?? "-"
                print("\(task.id.stringValue)\t\(task.effectiveTitle)\t\(cwd)\t\(duration)\t\(task.commandCount) commands")
            }
            return
        }

        if let task = response.task {
            print("Task: \(task.effectiveTitle)")
            print("ID: \(task.id.stringValue)")
            print("Bundle: \(task.bundleID)")
            print("Window: \(task.windowName ?? "-")")
            print("Working Directory: \(task.workingDirectory ?? "-")")
            print("Shell: \(task.shell ?? "-")")
            print("Started: \(formatDate(task.startDate))")
            print("Last Active: \(formatDate(task.lastActivityAt))")
            print("Ended: \(task.endDate.map(formatDate) ?? "-")")
            print("Commands: \(task.commandCount)")
            if let deeplinkURL = response.deeplinkURL {
                print("Deeplink: \(deeplinkURL)")
            }
            if let events = response.events, !events.isEmpty {
                print("")
                print("Events:")
                for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
                    var line = "- \(formatDate(event.timestamp)) [\(event.eventType.rawValue)]"
                    if let commandText = event.commandText, !commandText.isEmpty {
                        line += " \(commandText)"
                    }
                    if let exitCode = event.exitCode {
                        line += " (exit \(exitCode))"
                    }
                    print(line)
                }
            }
            return
        }

        if let search = response.search {
            if !search.terminal.isEmpty {
                print("Terminal tasks:")
                for item in search.terminal {
                    print("- \(item.task.id.stringValue)  \(item.task.effectiveTitle)  \(item.task.workingDirectory ?? "-")")
                    if let preview = item.matchedCommandPreview, !preview.isEmpty {
                        print("  \(preview)")
                    }
                }
            }

            if !search.frames.isEmpty {
                if !search.terminal.isEmpty {
                    print("")
                }
                print("Frames:")
                for frame in search.frames {
                    let title = frame.terminalTask?.effectiveTitle ?? frame.windowName ?? frame.appBundleID ?? "Frame"
                    print("- \(frame.frameID.value)  \(formatDate(frame.timestamp))  \(title)")
                    if let score = frame.relevanceScore {
                        print("  relevance: \(String(format: "%.3f", score))")
                    }
                    if let snippet = frame.snippet, !snippet.isEmpty {
                        print("  \(snippet)")
                    } else if let matched = frame.matchedText, !matched.isEmpty {
                        print("  \(matched)")
                    }
                    print("  \(frame.deeplinkURL)")
                }
            }

            if search.terminal.isEmpty && search.frames.isEmpty {
                print("No memory matches found.")
            }
            return
        }

        if let message = response.message, !message.isEmpty {
            print(message)
        }
    }

    func emitError(_ error: Error) {
        if jsonOutput {
            let response = TerminalMemoryCLIResponse(
                ok: false,
                message: error.localizedDescription,
                errorCode: String(describing: error)
            )
            if let data = try? encoder.encode(response) {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
                return
            }
        }

        FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
    }

    func parseDate(_ value: String?) throws -> Date? {
        guard let value, !value.isEmpty else { return nil }
        if let seconds = TimeInterval(value) {
            if seconds > 10_000_000_000 {
                return Date(timeIntervalSince1970: seconds / 1_000)
            }
            return Date(timeIntervalSince1970: seconds)
        }
        if let date = iso8601.date(from: value) {
            return date
        }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        if let date = fallback.date(from: value) {
            return date
        }
        throw CLIError.invalidArgument("Invalid date: \(value)")
    }
}

@main
enum RetraceCLI {
    static func main() async {
        let rawArguments = Array(CommandLine.arguments.dropFirst())
        let jsonOutput = rawArguments.contains("--json")
        let arguments = rawArguments.filter { $0 != "--json" }
        let context = CLIContext(jsonOutput: jsonOutput)

        do {
            let response = try await run(arguments: arguments, context: context)
            try context.emit(response)
        } catch {
            context.emitError(error)
            Foundation.exit(1)
        }
    }

    private static func run(arguments: [String], context: CLIContext) async throws -> TerminalMemoryCLIResponse {
        guard let command = arguments.first else {
            throw CLIError.usage(usageText)
        }

        switch command {
        case "hook":
            try context.requireAccess()
            return try await runHook(arguments: Array(arguments.dropFirst()), context: context)
        case "tasks":
            try context.requireAccess()
            return try await runTasks(arguments: Array(arguments.dropFirst()), context: context)
        case "memory":
            try context.requireAccess()
            return try await runMemory(arguments: Array(arguments.dropFirst()), context: context)
        case "search":
            try context.requireAccess()
            return try await runMemory(arguments: ["search"] + Array(arguments.dropFirst()), context: context)
        case "open":
            try context.requireAccess()
            return try await runOpen(arguments: Array(arguments.dropFirst()), context: context)
        case "pm":
            return try await runPM(arguments: Array(arguments.dropFirst()), context: context)
        case "version", "--version":
            return TerminalMemoryCLIResponse(ok: true, message: "arya-retrace CLI \(retraceCLIVersion)")
        case "help", "--help", "-h":
            return TerminalMemoryCLIResponse(ok: true, message: usageText)
        default:
            throw CLIError.usage(usageText)
        }
    }

    private static func runHook(arguments: [String], context: CLIContext) async throws -> TerminalMemoryCLIResponse {
        guard let subcommand = arguments.first else {
            throw CLIError.usage(usageText)
        }

        let parsed = parseArguments(Array(arguments.dropFirst()))
        let requestKind: TerminalMemoryCLIRequestKind
        switch subcommand {
        case "prompt":
            requestKind = .hookPrompt
        case "command-start":
            requestKind = .hookCommandStart
        case "command-end":
            requestKind = .hookCommandEnd
        default:
            throw CLIError.invalidArgument("Unknown hook command: \(subcommand)")
        }

        guard let sessionKey = parsed.values["--session-key"], !sessionKey.isEmpty else {
            throw CLIError.invalidArgument("Missing required --session-key for hook command.")
        }

        let payload = TerminalMemoryHookPayload(
            sessionKey: sessionKey,
            bundleID: parsed.values["--bundle-id"],
            windowName: parsed.values["--window-name"],
            taskTitle: parsed.values["--task-title"],
            workingDirectory: parsed.values["--working-directory"],
            shell: parsed.values["--shell"],
            commandText: parsed.values["--command"],
            timestamp: try context.parseDate(parsed.values["--timestamp"]),
            exitCode: parsed.values["--exit-code"].flatMap(Int.init),
            durationMs: parsed.values["--duration-ms"].flatMap(Int.init),
            metadataJSON: parsed.values["--metadata-json"],
            source: parsed.values["--source"].flatMap(TerminalTaskSource.init(rawValue:)),
            closeSession: parsed.flags.contains("--close-session")
        )
        let request = TerminalMemoryCLIRequest(kind: requestKind, hook: payload)

        if let response = try sendSocketRequestIfPossible(request, context: context) {
            return response
        }

        try appendHookRequestToInbox(request, context: context)
        return TerminalMemoryCLIResponse(ok: true, message: "Queued terminal hook event.")
    }

    private static func runTasks(arguments: [String], context: CLIContext) async throws -> TerminalMemoryCLIResponse {
        guard let subcommand = arguments.first else {
            throw CLIError.usage(usageText)
        }

        switch subcommand {
        case "list":
            let parsed = parseArguments(Array(arguments.dropFirst()))
            let request = TerminalMemoryCLIRequest(
                kind: .tasksList,
                limit: parsed.values["--limit"].flatMap(Int.init),
                bundleID: parsed.values["--bundle-id"],
                startDate: try context.parseDate(parsed.values["--start-date"] ?? parsed.values["--from"]),
                endDate: try context.parseDate(parsed.values["--end-date"] ?? parsed.values["--to"])
            )
            if let response = try sendSocketRequestIfPossible(request, context: context) {
                return response
            }
            return try await readOnlyTaskList(request: request)

        case "show":
            let parsed = parseArguments(Array(arguments.dropFirst()))
            let taskID = parsed.positionals.first ?? parsed.values["--task-id"]
            guard let taskID else {
                throw CLIError.invalidArgument("Missing task id for `retrace tasks show`.")
            }
            let request = TerminalMemoryCLIRequest(
                kind: .tasksShow,
                taskID: taskID,
                limit: parsed.values["--limit"].flatMap(Int.init)
            )
            if let response = try sendSocketRequestIfPossible(request, context: context) {
                return response
            }
            return try await readOnlyTaskShow(taskID: taskID, limit: parsed.values["--limit"].flatMap(Int.init) ?? 200)

        default:
            throw CLIError.invalidArgument("Unknown tasks command: \(subcommand)")
        }
    }

    private static func runMemory(arguments: [String], context: CLIContext) async throws -> TerminalMemoryCLIResponse {
        guard arguments.first == "search" else {
            throw CLIError.usage(usageText)
        }

        let parsed = parseArguments(Array(arguments.dropFirst()))
        let query = parsed.values["--query"] ?? parsed.positionals.joined(separator: " ")
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw CLIError.invalidArgument("Missing query text for `retrace memory search`.")
        }
        let scope = parsed.values["--scope"].flatMap(TerminalMemorySearchScope.init(rawValue:)) ?? .terminal

        if scope != .terminal && !context.allowAgentFrameSearch {
            throw CLIError.frameSearchDisabled
        }

        let request = TerminalMemoryCLIRequest(
            kind: .memorySearch,
            query: trimmedQuery,
            scope: scope,
            limit: parsed.values["--limit"].flatMap(Int.init)
        )
        if let response = try sendSocketRequestIfPossible(request, context: context) {
            return response
        }
        return try await readOnlyMemorySearch(
            query: trimmedQuery,
            scope: scope,
            limit: parsed.values["--limit"].flatMap(Int.init) ?? 10,
            context: context
        )
    }

    private static func runOpen(arguments: [String], context: CLIContext) async throws -> TerminalMemoryCLIResponse {
        guard arguments.first == "task" else {
            throw CLIError.usage(usageText)
        }

        let parsed = parseArguments(Array(arguments.dropFirst()))
        let taskID = parsed.positionals.first ?? parsed.values["--task-id"]
        guard let taskID else {
            throw CLIError.invalidArgument("Missing task id for `retrace open task`.")
        }

        let request = TerminalMemoryCLIRequest(kind: .openTask, taskID: taskID)
        let response = if let socketResponse = try sendSocketRequestIfPossible(request, context: context) {
            socketResponse
        } else {
            try await readOnlyOpenTask(taskID: taskID)
        }

        if response.ok, let deeplinkURL = response.deeplinkURL, let url = URL(string: deeplinkURL) {
            NSWorkspace.shared.open(url)
        }
        return response
    }

    private static func sendSocketRequestIfPossible(
        _ request: TerminalMemoryCLIRequest,
        context: CLIContext
    ) throws -> TerminalMemoryCLIResponse? {
        guard FileManager.default.fileExists(atPath: AppPaths.terminalMemorySocketPath) else {
            return nil
        }

        let requestData = try context.encoder.encode(request)
        let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            return nil
        }
        defer {
            shutdown(socketFD, SHUT_RDWR)
            close(socketFD)
        }

        do {
            try withUnixSocketAddress(path: AppPaths.terminalMemorySocketPath) { address, addressLength in
                guard connect(socketFD, address, addressLength) == 0 else {
                    throw CLIError.socketUnavailable
                }
            }
        } catch {
            return nil
        }

        _ = requestData.withUnsafeBytes { bytes in
            write(socketFD, bytes.baseAddress, bytes.count)
        }
        shutdown(socketFD, SHUT_WR)

        guard let responseData = readAll(from: socketFD) else {
            return nil
        }

        return try context.decoder.decode(TerminalMemoryCLIResponse.self, from: responseData)
    }

    private static func appendHookRequestToInbox(
        _ request: TerminalMemoryCLIRequest,
        context: CLIContext
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: URL(fileURLWithPath: AppPaths.defaultAppSupportRoot, isDirectory: true),
            withIntermediateDirectories: true,
            attributes: nil
        )

        let data = try context.encoder.encode(request) + Data("\n".utf8)
        let inboxURL = URL(fileURLWithPath: AppPaths.terminalHookInboxPath)

        if fileManager.fileExists(atPath: inboxURL.path) {
            let handle = try FileHandle(forWritingTo: inboxURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: inboxURL, options: .atomic)
        }
    }

    private static func readOnlyTaskList(request: TerminalMemoryCLIRequest) async throws -> TerminalMemoryCLIResponse {
        let endDate = request.endDate ?? Date()
        let startDate = request.startDate ?? Calendar.current.date(byAdding: .day, value: -30, to: endDate)
            ?? endDate.addingTimeInterval(-30 * 86400)
        do {
            return try await withReadOnlyDatabaseManager { database in
                let tasks = try await database.getTerminalTasks(
                    bundleID: request.bundleID,
                    from: startDate,
                    to: endDate,
                    limit: request.limit ?? 25
                )
                return TerminalMemoryCLIResponse(ok: true, tasks: tasks)
            }
        } catch {
            throw mapDatabaseError(error)
        }
    }

    private static func readOnlyTaskShow(taskID: String, limit: Int) async throws -> TerminalMemoryCLIResponse {
        guard let parsedID = TerminalTaskID(string: taskID) else {
            throw CLIError.invalidArgument("Invalid terminal task id: \(taskID)")
        }
        do {
            return try await withReadOnlyDatabaseManager { database in
                guard let task = try await database.getTerminalTask(id: parsedID) else {
                    throw CLIError.taskNotFound(taskID)
                }
                let events = try await database.getTerminalEvents(taskID: parsedID, limit: limit)
                return TerminalMemoryCLIResponse(ok: true, task: task, events: events)
            }
        } catch let error as CLIError {
            throw error
        } catch {
            throw mapDatabaseError(error)
        }
    }

    private static func readOnlyMemorySearch(
        query: String,
        scope: TerminalMemorySearchScope,
        limit: Int,
        context: CLIContext
    ) async throws -> TerminalMemoryCLIResponse {
        if scope != .terminal && !context.allowAgentFrameSearch {
            throw CLIError.frameSearchDisabled
        }
        do {
            return try await withReadOnlySearchStack { database, search in
                let payload = try await TerminalMemorySearch.makePayload(
                    query: query,
                    scope: scope,
                    limit: limit,
                    database: database,
                    search: search,
                    allowAgentFrameSearch: context.allowAgentFrameSearch
                )
                return TerminalMemoryCLIResponse(ok: true, search: payload)
            }
        } catch let error as TerminalMemoryError {
            if case .frameSearchDisabled = error {
                throw CLIError.frameSearchDisabled
            }
            throw CLIError.databaseUnavailable(error.localizedDescription)
        } catch {
            throw mapDatabaseError(error)
        }
    }

    private static func readOnlyOpenTask(taskID: String) async throws -> TerminalMemoryCLIResponse {
        guard let parsedID = TerminalTaskID(string: taskID) else {
            throw CLIError.invalidArgument("Invalid terminal task id: \(taskID)")
        }
        do {
            return try await withReadOnlyDatabaseManager { database in
                guard let task = try await database.getTerminalTask(id: parsedID) else {
                    throw CLIError.taskNotFound(taskID)
                }
                let deeplinkURL = RetraceTimelineDeeplink.string(for: task.startDate)
                return TerminalMemoryCLIResponse(ok: true, task: task, deeplinkURL: deeplinkURL)
            }
        } catch let error as CLIError {
            throw error
        } catch {
            throw mapDatabaseError(error)
        }
    }

    private static func mapDatabaseError(_ error: Error) -> Error {
        if error is CLIError {
            return error
        }
        return CLIError.databaseUnavailable(error.localizedDescription)
    }

    private static func withReadOnlyDatabaseManager<T>(
        _ body: (DatabaseManager) async throws -> T
    ) async throws -> T {
        let database = DatabaseManager(databasePath: AppPaths.databasePath, openMode: .readOnlyExisting)
        try await database.initialize()
        do {
            let result = try await body(database)
            try await database.close()
            return result
        } catch {
            try? await database.close()
            throw error
        }
    }

    private static func withReadOnlySearchStack<T>(
        _ body: (DatabaseManager, SearchManager) async throws -> T
    ) async throws -> T {
        let database = DatabaseManager(databasePath: AppPaths.databasePath, openMode: .readOnlyExisting)
        let fts = FTSManager(databasePath: AppPaths.databasePath, readOnly: true)
        let search = SearchManager(database: database, ftsEngine: fts)
        try await database.initialize()
        try await fts.initialize()
        try await search.initialize(config: SearchConfig())
        do {
            let result = try await body(database, search)
            try await fts.close()
            try await database.close()
            return result
        } catch {
            try? await fts.close()
            try? await database.close()
            throw error
        }
    }

    private static func runPM(arguments: [String], context: CLIContext) async throws -> TerminalMemoryCLIResponse {
        let service = ProjectTaskService(database: nil)
        guard let sub = arguments.first else {
            throw CLIError.usage(usageText)
        }
        let rest = Array(arguments.dropFirst())

        switch sub {
        case "project":
            guard rest.first == "register" else {
                throw CLIError.invalidArgument("Expected `pm project register --path <dir> [--name <title>]`")
            }
            let parsed = parseArguments(Array(rest.dropFirst()))
            guard let path = parsed.values["--path"] ?? parsed.positionals.first else {
                throw CLIError.invalidArgument("Missing --path for pm project register.")
            }
            let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
            let manifest = try service.registerProject(at: url, displayName: parsed.values["--name"])
            return TerminalMemoryCLIResponse(
                ok: true,
                message: "Registered project \(manifest.displayName) — data under \(path)/\(DotProjectLayout.dotDirectoryName)"
            )

        case "tasks":
            guard rest.first == "list" else {
                throw CLIError.invalidArgument("Expected `pm tasks list --project <dir>`")
            }
            let parsed = parseArguments(Array(rest.dropFirst()))
            guard let path = parsed.values["--project"] else {
                throw CLIError.invalidArgument("Missing --project for pm tasks list.")
            }
            let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
            let tasks = try service.listTasks(for: url)
            if context.jsonOutput {
                let data = try context.encoder.encode(tasks)
                let s = String(data: data, encoding: .utf8) ?? "[]"
                return TerminalMemoryCLIResponse(ok: true, message: s)
            }
            if tasks.isEmpty {
                return TerminalMemoryCLIResponse(ok: true, message: "No PM tasks in \(path)/\(DotProjectLayout.dotDirectoryName)")
            }
            var lines: [String] = []
            for t in tasks {
                lines.append("\(t.id.uuidString)\t\(t.status.rawValue)\t\(Int(t.totalTrackedSeconds))s\t\(t.title)")
            }
            return TerminalMemoryCLIResponse(ok: true, message: lines.joined(separator: "\n"))

        case "task":
            guard let taskSub = rest.first else {
                throw CLIError.invalidArgument("Expected `pm task start|stop|status --project <dir> ...`")
            }
            let parsed = parseArguments(Array(rest.dropFirst()))
            guard let path = parsed.values["--project"] else {
                throw CLIError.invalidArgument("Missing --project for pm task.")
            }
            let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)

            switch taskSub {
            case "start":
                let title = parsed.values["--title"] ?? parsed.positionals.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else {
                    throw CLIError.invalidArgument("Missing task title (`--title` or positional).")
                }
                let task = try service.startTask(for: url, title: title)
                return TerminalMemoryCLIResponse(ok: true, message: "Started task \(task.id.uuidString) — \(task.title)")

            case "stop":
                if let stopped = try service.stopTask(for: url) {
                    return TerminalMemoryCLIResponse(ok: true, message: "Stopped task \(stopped.id.uuidString) — \(stopped.title)")
                }
                return TerminalMemoryCLIResponse(ok: true, message: "No active PM task to stop.")

            case "status":
                if let active = try service.activeTask(for: url) {
                    return TerminalMemoryCLIResponse(
                        ok: true,
                        message: "Active: \(active.id.uuidString) — \(active.title) (\(active.status.rawValue))"
                    )
                }
                return TerminalMemoryCLIResponse(ok: true, message: "No active PM task.")

            default:
                throw CLIError.invalidArgument("Unknown pm task subcommand: \(taskSub)")
            }

        default:
            throw CLIError.invalidArgument("Unknown pm command: \(sub)")
        }
    }
}

private func parseArguments(_ arguments: [String]) -> ParsedArguments {
    var values: [String: String] = [:]
    var flags = Set<String>()
    var positionals: [String] = []

    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        if argument.hasPrefix("--") {
            if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") {
                values[argument] = arguments[index + 1]
                index += 2
            } else {
                flags.insert(argument)
                index += 1
            }
        } else {
            positionals.append(argument)
            index += 1
        }
    }

    return ParsedArguments(values: values, flags: flags, positionals: positionals)
}

private func readAll(from fileDescriptor: Int32) -> Data? {
    var buffer = [UInt8](repeating: 0, count: 4096)
    var data = Data()

    while true {
        let bytesRead = Darwin.read(fileDescriptor, &buffer, buffer.count)
        if bytesRead > 0 {
            data.append(buffer, count: bytesRead)
            continue
        }
        break
    }

    return data.isEmpty ? nil : data
}

private func withUnixSocketAddress<T>(
    path: String,
    _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T
) throws -> T {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)

    #if os(macOS)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    #endif

    let utf8Path = path.utf8CString
    let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
    guard utf8Path.count <= pathCapacity else {
        throw CLIError.invalidArgument("Socket path is too long.")
    }

    withUnsafeMutablePointer(to: &address.sun_path) { rawPathPointer in
        let pathPointer = UnsafeMutableRawPointer(rawPathPointer).assumingMemoryBound(to: CChar.self)
        pathPointer.initialize(repeating: 0, count: pathCapacity)
        utf8Path.withUnsafeBufferPointer { buffer in
            pathPointer.initialize(from: buffer.baseAddress!, count: buffer.count)
        }
    }

    let addressLength = socklen_t(MemoryLayout<sockaddr_un>.size)
    return try withUnsafePointer(to: &address) { pointer in
        try body(
            UnsafeRawPointer(pointer).assumingMemoryBound(to: sockaddr.self),
            addressLength
        )
    }
}

private func formatDuration(_ duration: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = duration >= 3600 ? [.hour, .minute] : [.minute, .second]
    formatter.unitsStyle = .abbreviated
    formatter.zeroFormattingBehavior = [.dropLeading, .pad]
    return formatter.string(from: max(0, duration)) ?? "0s"
}

private func formatDate(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
}

private let usageText = """
Usage:
  retrace version
  retrace hook prompt --session-key <key> [--bundle-id <id>] [--window-name <title>] [--task-title <title>] [--working-directory <cwd>] [--shell <shell>]
  retrace hook command-start --session-key <key> [--command <text>] [--working-directory <cwd>] [--bundle-id <id>] [--window-name <title>] [--task-title <title>] [--shell <shell>]
  retrace hook command-end --session-key <key> [--command <text>] [--exit-code <code>] [--duration-ms <ms>] [--working-directory <cwd>] [--bundle-id <id>] [--window-name <title>] [--task-title <title>] [--shell <shell>]
  retrace tasks list [--limit <n>] [--bundle-id <id>] [--start-date <iso8601>] [--end-date <iso8601>] [--json]
  retrace tasks show <task-id> [--limit <n>] [--json]
  retrace memory search [--scope terminal|frames|both] [--limit <n>] --query <text> [--json]
  retrace search ...   (alias for retrace memory search)
  retrace open task <task-id> [--json]

  retrace pm project register --path <dir> [--name <title>] [--json]
  retrace pm tasks list --project <dir> [--json]
  retrace pm task start --project <dir> --title <text> [--json]
  retrace pm task stop --project <dir> [--json]
  retrace pm task status --project <dir> [--json]

Build the binary with: swift build -c release --product RetraceCLI
Install (example): ln -sf "$(pwd)/.build/arm64-apple-macosx/release/RetraceCLI" /usr/local/bin/retrace
"""
