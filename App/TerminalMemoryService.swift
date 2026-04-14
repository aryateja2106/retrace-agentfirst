import Foundation
import Darwin
import Shared
import Database
import Search
import Capture

public enum TerminalMemorySearchScope: String, Codable, Sendable, CaseIterable {
    case terminal
    case frames
    case both
}

public enum TerminalMemoryCLIRequestKind: String, Codable, Sendable {
    case hookPrompt = "hook_prompt"
    case hookCommandStart = "hook_command_start"
    case hookCommandEnd = "hook_command_end"
    case tasksList = "tasks_list"
    case tasksShow = "tasks_show"
    case memorySearch = "memory_search"
    case openTask = "open_task"
}

public struct TerminalMemoryHookPayload: Codable, Sendable {
    public let sessionKey: String
    public let bundleID: String?
    public let windowName: String?
    public let taskTitle: String?
    public let workingDirectory: String?
    public let shell: String?
    public let commandText: String?
    public let timestamp: Date?
    public let exitCode: Int?
    public let durationMs: Int?
    public let metadataJSON: String?
    public let source: TerminalTaskSource?
    public let closeSession: Bool

    public init(
        sessionKey: String,
        bundleID: String? = nil,
        windowName: String? = nil,
        taskTitle: String? = nil,
        workingDirectory: String? = nil,
        shell: String? = nil,
        commandText: String? = nil,
        timestamp: Date? = nil,
        exitCode: Int? = nil,
        durationMs: Int? = nil,
        metadataJSON: String? = nil,
        source: TerminalTaskSource? = nil,
        closeSession: Bool = false
    ) {
        self.sessionKey = sessionKey
        self.bundleID = bundleID
        self.windowName = windowName
        self.taskTitle = taskTitle
        self.workingDirectory = workingDirectory
        self.shell = shell
        self.commandText = commandText
        self.timestamp = timestamp
        self.exitCode = exitCode
        self.durationMs = durationMs
        self.metadataJSON = metadataJSON
        self.source = source
        self.closeSession = closeSession
    }
}

public struct TerminalMemoryFrameHit: Codable, Sendable, Equatable, Identifiable {
    public let frameID: FrameID
    public let timestamp: Date
    public let appBundleID: String?
    public let windowName: String?
    public let deeplinkURL: String
    public let terminalTask: TerminalTaskSession?
    /// OCR / FTS snippet for this frame (same family as in-app search).
    public let snippet: String?
    /// Normalized relevance score from search ranking (0…1).
    public let relevanceScore: Double?
    /// Short matched-text preview derived from the snippet.
    public let matchedText: String?

    public var id: FrameID { frameID }

    public init(
        frameID: FrameID,
        timestamp: Date,
        appBundleID: String?,
        windowName: String?,
        deeplinkURL: String,
        terminalTask: TerminalTaskSession?,
        snippet: String? = nil,
        relevanceScore: Double? = nil,
        matchedText: String? = nil
    ) {
        self.frameID = frameID
        self.timestamp = timestamp
        self.appBundleID = appBundleID
        self.windowName = windowName
        self.deeplinkURL = deeplinkURL
        self.terminalTask = terminalTask
        self.snippet = snippet
        self.relevanceScore = relevanceScore
        self.matchedText = matchedText
    }
}

public struct TerminalMemorySearchPayload: Codable, Sendable, Equatable {
    public let terminal: [TerminalTaskSearchResult]
    public let frames: [TerminalMemoryFrameHit]

    public init(
        terminal: [TerminalTaskSearchResult],
        frames: [TerminalMemoryFrameHit]
    ) {
        self.terminal = terminal
        self.frames = frames
    }
}

public struct TerminalMemoryCLIRequest: Codable, Sendable {
    public let kind: TerminalMemoryCLIRequestKind
    public let hook: TerminalMemoryHookPayload?
    public let taskID: String?
    public let query: String?
    public let scope: TerminalMemorySearchScope?
    public let limit: Int?
    public let bundleID: String?
    public let startDate: Date?
    public let endDate: Date?

    public init(
        kind: TerminalMemoryCLIRequestKind,
        hook: TerminalMemoryHookPayload? = nil,
        taskID: String? = nil,
        query: String? = nil,
        scope: TerminalMemorySearchScope? = nil,
        limit: Int? = nil,
        bundleID: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) {
        self.kind = kind
        self.hook = hook
        self.taskID = taskID
        self.query = query
        self.scope = scope
        self.limit = limit
        self.bundleID = bundleID
        self.startDate = startDate
        self.endDate = endDate
    }
}

public struct TerminalMemoryCLIResponse: Codable, Sendable {
    public let ok: Bool
    public let message: String?
    public let errorCode: String?
    public let task: TerminalTaskSession?
    public let tasks: [TerminalTaskSession]?
    public let events: [TerminalTaskEvent]?
    public let search: TerminalMemorySearchPayload?
    public let deeplinkURL: String?

    public init(
        ok: Bool,
        message: String? = nil,
        errorCode: String? = nil,
        task: TerminalTaskSession? = nil,
        tasks: [TerminalTaskSession]? = nil,
        events: [TerminalTaskEvent]? = nil,
        search: TerminalMemorySearchPayload? = nil,
        deeplinkURL: String? = nil
    ) {
        self.ok = ok
        self.message = message
        self.errorCode = errorCode
        self.task = task
        self.tasks = tasks
        self.events = events
        self.search = search
        self.deeplinkURL = deeplinkURL
    }
}

public enum TerminalMemoryError: Error, LocalizedError {
    case cliAccessDisabled
    case frameSearchDisabled
    case invalidTaskID
    case taskNotFound
    case invalidRequest(String)
    case socketSetupFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cliAccessDisabled:
            return "CLI access is disabled in Retrace settings."
        case .frameSearchDisabled:
            return "Agent frame search is disabled."
        case .invalidTaskID:
            return "Invalid terminal task identifier."
        case .taskNotFound:
            return "Terminal task not found."
        case .invalidRequest(let message):
            return message
        case .socketSetupFailed(let message):
            return message
        }
    }
}

public enum TerminalShellHookBuilder {
    public static func snippet(for shell: String) -> String {
        switch shell.lowercased() {
        case "bash":
            return bashSnippet
        case "fish":
            return fishSnippet
        default:
            return zshSnippet
        }
    }

    private static let commonHelpers = #"""
_retrace_bin() {
  command -v retrace >/dev/null 2>&1 || return 1
  command retrace "$@"
}

_retrace_bundle_id() {
  case "${TERM_PROGRAM:-}" in
    WarpTerminal|Warp) printf '%s' 'dev.warp.Warp-Stable' ;;
    Apple_Terminal) printf '%s' 'com.apple.Terminal' ;;
    iTerm.app|iTerm2) printf '%s' 'com.googlecode.iterm2' ;;
    *) printf '%s' 'dev.warp.Warp-Stable' ;;
  esac
}
"""#

    public static let zshSnippet = commonHelpers + #"""

typeset -g RETRACE_SESSION_KEY="${RETRACE_SESSION_KEY:-${HOST:-local}:$$}"
typeset -g RETRACE_LAST_COMMAND=""

_retrace_precmd() {
  local exit_code="$?"
  local pwd_hint="${PWD/#$HOME/~}"

  if [[ -n "${RETRACE_LAST_COMMAND}" ]]; then
    _retrace_bin hook command-end \
      --session-key "$RETRACE_SESSION_KEY" \
      --bundle-id "$(_retrace_bundle_id)" \
      --window-name "$pwd_hint" \
      --task-title "$pwd_hint" \
      --working-directory "$PWD" \
      --shell "${SHELL##*/}" \
      --command "$RETRACE_LAST_COMMAND" \
      --exit-code "$exit_code" >/dev/null 2>&1 || true
    RETRACE_LAST_COMMAND=""
  fi

  _retrace_bin hook prompt \
    --session-key "$RETRACE_SESSION_KEY" \
    --bundle-id "$(_retrace_bundle_id)" \
    --window-name "$pwd_hint" \
    --task-title "$pwd_hint" \
    --working-directory "$PWD" \
    --shell "${SHELL##*/}" >/dev/null 2>&1 || true
}

_retrace_preexec() {
  local command="$1"
  RETRACE_LAST_COMMAND="$command"
  local pwd_hint="${PWD/#$HOME/~}"
  _retrace_bin hook command-start \
    --session-key "$RETRACE_SESSION_KEY" \
    --bundle-id "$(_retrace_bundle_id)" \
    --window-name "$pwd_hint" \
    --task-title "$pwd_hint" \
    --working-directory "$PWD" \
    --shell "${SHELL##*/}" \
    --command "$command" >/dev/null 2>&1 || true
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec _retrace_preexec
add-zsh-hook precmd _retrace_precmd
"""#

    public static let bashSnippet = commonHelpers + #"""

export RETRACE_SESSION_KEY="${RETRACE_SESSION_KEY:-${HOSTNAME:-local}:$$}"
export RETRACE_LAST_COMMAND=""

_retrace_prompt_command() {
  local exit_code="$?"
  local pwd_hint="${PWD/#$HOME/~}"

  if [[ -n "${RETRACE_LAST_COMMAND}" ]]; then
    _retrace_bin hook command-end \
      --session-key "$RETRACE_SESSION_KEY" \
      --bundle-id "$(_retrace_bundle_id)" \
      --window-name "$pwd_hint" \
      --task-title "$pwd_hint" \
      --working-directory "$PWD" \
      --shell "${SHELL##*/}" \
      --command "$RETRACE_LAST_COMMAND" \
      --exit-code "$exit_code" >/dev/null 2>&1 || true
    RETRACE_LAST_COMMAND=""
  fi

  _retrace_bin hook prompt \
    --session-key "$RETRACE_SESSION_KEY" \
    --bundle-id "$(_retrace_bundle_id)" \
    --window-name "$pwd_hint" \
    --task-title "$pwd_hint" \
    --working-directory "$PWD" \
    --shell "${SHELL##*/}" >/dev/null 2>&1 || true
}

trap '_retrace_last="$BASH_COMMAND"; if [[ "$_retrace_last" != _retrace_* ]]; then RETRACE_LAST_COMMAND="$_retrace_last"; _retrace_pwd="${PWD/#$HOME/~}"; _retrace_bin hook command-start --session-key "$RETRACE_SESSION_KEY" --bundle-id "$(_retrace_bundle_id)" --window-name "$_retrace_pwd" --task-title "$_retrace_pwd" --working-directory "$PWD" --shell "${SHELL##*/}" --command "$_retrace_last" >/dev/null 2>&1 || true; fi' DEBUG
PROMPT_COMMAND="_retrace_prompt_command${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
"""#

    public static let fishSnippet = #"""
function __retrace_bundle_id
    switch "$TERM_PROGRAM"
        case WarpTerminal Warp
            echo "dev.warp.Warp-Stable"
        case Apple_Terminal
            echo "com.apple.Terminal"
        case iTerm.app iTerm2
            echo "com.googlecode.iterm2"
        case '*'
            echo "dev.warp.Warp-Stable"
    end
end

set -gx RETRACE_SESSION_KEY (set -q RETRACE_SESSION_KEY; and echo $RETRACE_SESSION_KEY; or echo (hostname)":"(fish_pid))
set -g RETRACE_LAST_COMMAND ""

function __retrace_preexec --on-event fish_preexec
    set -g RETRACE_LAST_COMMAND "$argv[1]"
    set pwd_hint (string replace -r "^$HOME" "~" -- "$PWD")
    command retrace hook command-start --session-key "$RETRACE_SESSION_KEY" --bundle-id (__retrace_bundle_id) --window-name "$pwd_hint" --task-title "$pwd_hint" --working-directory "$PWD" --shell (basename "$SHELL") --command "$argv[1]" >/dev/null 2>&1; or true
end

function __retrace_prompt --on-event fish_prompt
    set pwd_hint (string replace -r "^$HOME" "~" -- "$PWD")
    if test -n "$RETRACE_LAST_COMMAND"
        command retrace hook command-end --session-key "$RETRACE_SESSION_KEY" --bundle-id (__retrace_bundle_id) --window-name "$pwd_hint" --task-title "$pwd_hint" --working-directory "$PWD" --shell (basename "$SHELL") --command "$RETRACE_LAST_COMMAND" --exit-code "$status" >/dev/null 2>&1; or true
        set -g RETRACE_LAST_COMMAND ""
    end
    command retrace hook prompt --session-key "$RETRACE_SESSION_KEY" --bundle-id (__retrace_bundle_id) --window-name "$pwd_hint" --task-title "$pwd_hint" --working-directory "$PWD" --shell (basename "$SHELL") >/dev/null 2>&1; or true
end
"""#
}

public actor TerminalMemoryService {
    public static let cliAccessEnabledDefaultsKey = "terminalCLIAccessEnabled"
    public static let allowAgentFrameSearchDefaultsKey = "terminalAllowAgentFrameSearch"

    private static let defaultSearchWindowDays = 30
    private static let frameTaskLookbackSeconds: TimeInterval = 30 * 60
    private static let frameTaskMatchRecencySeconds: TimeInterval = 3 * 60

    private let database: DatabaseManager
    private let search: SearchManager
    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var startedSessionKeys: Set<String> = []
    private var listenSocket: Int32 = -1
    private var serverTask: Task<Void, Never>?

    public init(
        database: DatabaseManager,
        search: SearchManager,
        defaults: UserDefaults = UserDefaults(suiteName: AryaRetraceIdentity.userDefaultsSuiteName) ?? .standard
    ) {
        self.database = database
        self.search = search
        self.defaults = defaults

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func refreshAccess() async {
        if isCLIAccessEnabled {
            do {
                try ensureRuntimeDirectories()
                await importHookInboxIfNeeded()
                try startServerIfNeeded()
            } catch {
                Log.error("[TerminalMemoryService] Failed to refresh CLI access", category: .app, error: error)
            }
        } else {
            stopServer()
        }
    }

    public func stop() {
        stopServer()
    }

    public func processRequest(_ request: TerminalMemoryCLIRequest) async throws -> TerminalMemoryCLIResponse {
        guard isCLIAccessEnabled else {
            throw TerminalMemoryError.cliAccessDisabled
        }
        return try await handleRequest(request)
    }

    public func linkCapturedFrameIfNeeded(
        frameID: FrameID,
        timestamp: Date,
        metadata: FrameMetadata
    ) async throws -> TerminalTaskSession? {
        guard let bundleID = metadata.appBundleID,
              TerminalBundleRegistry.isSupportedApp(bundleID) else {
            return nil
        }

        let normalizedWindowName = TerminalBundleRegistry.normalizedWindowName(
            metadata.windowName,
            bundleID: bundleID
        )

        let searchStart = timestamp.addingTimeInterval(-Self.frameTaskLookbackSeconds)
        let candidates = try await database.getTerminalTasks(
            bundleID: bundleID,
            from: searchStart,
            to: timestamp,
            limit: 25
        )

        let bestMatch = candidates
            .compactMap { candidate -> (score: Int, task: TerminalTaskSession)? in
                let candidateWindow = TerminalBundleRegistry.normalizedWindowName(
                    candidate.windowName,
                    bundleID: candidate.bundleID
                )
                let candidateTitle = TerminalBundleRegistry.normalizedWindowName(
                    candidate.taskTitle,
                    bundleID: candidate.bundleID
                )

                var score = 0
                if let normalizedWindowName {
                    if normalizedWindowName == candidateWindow {
                        score += 100
                    }
                    if normalizedWindowName == candidateTitle {
                        score += 80
                    }
                }

                let recency = abs(candidate.lastActivityAt.timeIntervalSince(timestamp))
                if recency <= Self.frameTaskMatchRecencySeconds {
                    score += 40
                }

                if candidate.endDate == nil {
                    score += 10
                }

                return score > 0 ? (score, candidate) : nil
            }
            .sorted {
                if $0.score == $1.score {
                    return $0.task.lastActivityAt > $1.task.lastActivityAt
                }
                return $0.score > $1.score
            }
            .first?
            .task

        guard let bestMatch else {
            return nil
        }

        try await database.linkFrameToTerminalTask(frameID: frameID, taskID: bestMatch.id)

        guard let normalizedWindowName, !normalizedWindowName.isEmpty else {
            return bestMatch
        }

        guard normalizedWindowName != bestMatch.windowName || normalizedWindowName != bestMatch.taskTitle else {
            return bestMatch
        }

        let enrichedTask = TerminalTaskSession(
            id: bestMatch.id,
            bundleID: bestMatch.bundleID,
            windowName: normalizedWindowName,
            taskTitle: normalizedWindowName,
            workingDirectory: bestMatch.workingDirectory,
            shell: bestMatch.shell,
            sessionKey: bestMatch.sessionKey,
            startDate: bestMatch.startDate,
            endDate: bestMatch.endDate,
            lastActivityAt: max(bestMatch.lastActivityAt, timestamp),
            source: bestMatch.source,
            confidence: bestMatch.confidence,
            commandCount: bestMatch.commandCount,
            metadataJSON: bestMatch.metadataJSON
        )
        return try await database.upsertTerminalTaskSession(enrichedTask)
    }

    private func handleRequest(_ request: TerminalMemoryCLIRequest) async throws -> TerminalMemoryCLIResponse {
        switch request.kind {
        case .hookPrompt, .hookCommandStart, .hookCommandEnd:
            guard let hook = request.hook else {
                throw TerminalMemoryError.invalidRequest("Missing hook payload.")
            }
            let task = try await ingestHook(
                kind: request.kind,
                payload: hook
            )
            return TerminalMemoryCLIResponse(ok: true, task: task)

        case .tasksList:
            let endDate = request.endDate ?? Date()
            let startDate = request.startDate ?? Calendar.current.date(
                byAdding: .day,
                value: -Self.defaultSearchWindowDays,
                to: endDate
            ) ?? endDate.addingTimeInterval(-(Double(Self.defaultSearchWindowDays) * 86400))
            let tasks = try await database.getTerminalTasks(
                bundleID: request.bundleID,
                from: startDate,
                to: endDate,
                limit: max(1, request.limit ?? 25)
            )
            await recordMetric(
                .terminalCLIQuery,
                metadata: jsonMetadata([
                    "kind": request.kind.rawValue,
                    "count": tasks.count,
                    "bundleID": request.bundleID ?? ""
                ])
            )
            return TerminalMemoryCLIResponse(ok: true, tasks: tasks)

        case .tasksShow:
            guard let taskID = request.taskID.flatMap(TerminalTaskID.init(string:)) else {
                throw TerminalMemoryError.invalidTaskID
            }
            guard let task = try await database.getTerminalTask(id: taskID) else {
                throw TerminalMemoryError.taskNotFound
            }
            let events = try await database.getTerminalEvents(taskID: taskID, limit: max(1, request.limit ?? 200))
            await recordMetric(
                .terminalCLIQuery,
                metadata: jsonMetadata([
                    "kind": request.kind.rawValue,
                    "taskID": taskID.value
                ])
            )
            return TerminalMemoryCLIResponse(ok: true, task: task, events: events)

        case .memorySearch:
            let query = request.query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !query.isEmpty else {
                throw TerminalMemoryError.invalidRequest("Search query cannot be empty.")
            }
            let scope = request.scope ?? .terminal
            let payload = try await searchMemory(
                query: query,
                scope: scope,
                limit: max(1, request.limit ?? 10)
            )
            return TerminalMemoryCLIResponse(ok: true, search: payload)

        case .openTask:
            guard let taskID = request.taskID.flatMap(TerminalTaskID.init(string:)) else {
                throw TerminalMemoryError.invalidTaskID
            }
            guard let task = try await database.getTerminalTask(id: taskID) else {
                throw TerminalMemoryError.taskNotFound
            }
            let deeplinkURL = RetraceTimelineDeeplink.string(for: task.startDate)
            await recordMetric(
                .terminalCLIQuery,
                metadata: jsonMetadata([
                    "kind": request.kind.rawValue,
                    "taskID": taskID.value
                ])
            )
            return TerminalMemoryCLIResponse(ok: true, task: task, deeplinkURL: deeplinkURL)
        }
    }

    private func searchMemory(
        query: String,
        scope: TerminalMemorySearchScope,
        limit: Int
    ) async throws -> TerminalMemorySearchPayload {
        if scope != .terminal, !allowAgentFrameSearch {
            await recordMetric(
                .terminalCLIScopeDenied,
                metadata: jsonMetadata([
                    "scope": scope.rawValue,
                    "reason": "frame_search_disabled"
                ])
            )
            throw TerminalMemoryError.frameSearchDisabled
        }

        let payload = try await TerminalMemorySearch.makePayload(
            query: query,
            scope: scope,
            limit: limit,
            database: database,
            search: search,
            allowAgentFrameSearch: allowAgentFrameSearch
        )

        await recordMetric(
            .terminalCLIQuery,
            metadata: jsonMetadata([
                "kind": "memory_search",
                "scope": scope.rawValue,
                "queryLength": query.count
            ])
        )
        return payload
    }

    private func ingestHook(
        kind: TerminalMemoryCLIRequestKind,
        payload: TerminalMemoryHookPayload
    ) async throws -> TerminalTaskSession {
        let timestamp = payload.timestamp ?? Date()
        let bundleID = payload.bundleID ?? TerminalBundleRegistry.warpBundleID
        let normalizedWindowName = TerminalBundleRegistry.normalizedWindowName(
            payload.windowName ?? payload.taskTitle ?? payload.workingDirectory,
            bundleID: bundleID
        )
        let normalizedTaskTitle = TerminalBundleRegistry.normalizedWindowName(
            payload.taskTitle ?? payload.commandText ?? payload.workingDirectory,
            bundleID: bundleID
        ) ?? basename(from: payload.workingDirectory) ?? "Terminal task"

        let session = TerminalTaskSession(
            id: TerminalTaskID(value: 0),
            bundleID: bundleID,
            windowName: normalizedWindowName,
            taskTitle: normalizedTaskTitle,
            workingDirectory: payload.workingDirectory,
            shell: payload.shell,
            sessionKey: payload.sessionKey,
            startDate: timestamp,
            endDate: nil,
            lastActivityAt: timestamp,
            source: payload.source ?? .shellHook,
            confidence: 0.9,
            commandCount: 0,
            metadataJSON: payload.metadataJSON
        )
        let persisted = try await database.upsertTerminalTaskSession(session)

        let eventType: TerminalTaskEventType = switch kind {
        case .hookPrompt:
            .prompt
        case .hookCommandStart:
            .commandStart
        case .hookCommandEnd:
            .commandEnd
        default:
            .prompt
        }

        _ = try await database.appendTerminalTaskEvent(
            TerminalTaskEvent(
                id: 0,
                taskID: persisted.id,
                timestamp: timestamp,
                eventType: eventType,
                commandText: payload.commandText,
                exitCode: payload.exitCode,
                durationMs: payload.durationMs,
                workingDirectory: payload.workingDirectory,
                metadataJSON: payload.metadataJSON
            )
        )

        if startedSessionKeys.insert(payload.sessionKey).inserted {
            await recordMetric(
                .terminalTaskStarted,
                metadata: jsonMetadata([
                    "bundleID": bundleID,
                    "source": (payload.source ?? .shellHook).rawValue
                ])
            )
        }

        if eventType == .commandEnd {
            await recordMetric(
                .terminalCommandRecorded,
                metadata: jsonMetadata([
                    "taskID": persisted.id.value,
                    "exitCode": payload.exitCode ?? -999
                ])
            )
        }

        if payload.closeSession {
            try await database.closeTerminalTaskSession(id: persisted.id, endDate: timestamp, commandCount: nil)
            await recordMetric(
                .terminalTaskCompleted,
                metadata: jsonMetadata([
                    "taskID": persisted.id.value
                ])
            )
        }

        return try await database.getTerminalTask(id: persisted.id) ?? persisted
    }

    private var isCLIAccessEnabled: Bool {
        defaults.object(forKey: Self.cliAccessEnabledDefaultsKey) as? Bool ?? false
    }

    private var allowAgentFrameSearch: Bool {
        defaults.object(forKey: Self.allowAgentFrameSearchDefaultsKey) as? Bool ?? false
    }

    private func recordMetric(
        _ metric: DailyMetricsQueries.MetricType,
        metadata: String? = nil
    ) async {
        try? await database.recordMetricEvent(metricType: metric, metadata: metadata)
    }

    private func jsonMetadata(_ payload: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func basename(from workingDirectory: String?) -> String? {
        guard let workingDirectory, !workingDirectory.isEmpty else { return nil }
        let lastComponent = URL(fileURLWithPath: workingDirectory).lastPathComponent
        return lastComponent.isEmpty ? nil : lastComponent
    }

    private func ensureRuntimeDirectories() throws {
        try FileManager.default.createDirectory(
            atPath: AppPaths.runPath,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            atPath: AppPaths.defaultAppSupportRoot,
            withIntermediateDirectories: true
        )
    }

    private func importHookInboxIfNeeded() async {
        let inboxURL = URL(fileURLWithPath: AppPaths.terminalHookInboxPath)
        guard FileManager.default.fileExists(atPath: inboxURL.path),
              let data = try? Data(contentsOf: inboxURL),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else {
            return
        }

        try? FileManager.default.removeItem(at: inboxURL)

        for line in text.split(whereSeparator: \.isNewline) {
            guard let data = line.data(using: .utf8),
                  let request = try? decoder.decode(TerminalMemoryCLIRequest.self, from: data) else {
                continue
            }
            _ = try? await handleRequest(request)
        }
    }

    private func startServerIfNeeded() throws {
        guard serverTask == nil else { return }

        try ensureRuntimeDirectories()
        unlink(AppPaths.terminalMemorySocketPath)

        let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            throw TerminalMemoryError.socketSetupFailed("Failed to create unix socket.")
        }

        do {
            try Self.withUnixSocketAddress(path: AppPaths.terminalMemorySocketPath) { address, addressLength in
                guard bind(socketFD, address, addressLength) == 0 else {
                    throw TerminalMemoryError.socketSetupFailed(
                        "Failed to bind terminal-memory socket: \(String(cString: strerror(errno)))"
                    )
                }
            }

            guard listen(socketFD, 8) == 0 else {
                throw TerminalMemoryError.socketSetupFailed(
                    "Failed to listen on terminal-memory socket: \(String(cString: strerror(errno)))"
                )
            }

            chmod(AppPaths.terminalMemorySocketPath, mode_t(S_IRUSR | S_IWUSR))
        } catch {
            close(socketFD)
            throw error
        }

        listenSocket = socketFD
        serverTask = Task.detached(priority: .background) { [service = self] in
            await service.socketAcceptLoop(socketFD: socketFD)
        }
    }

    private func stopServer() {
        serverTask?.cancel()
        serverTask = nil

        if listenSocket >= 0 {
            shutdown(listenSocket, SHUT_RDWR)
            close(listenSocket)
            listenSocket = -1
        }

        unlink(AppPaths.terminalMemorySocketPath)
    }

    private func socketAcceptLoop(socketFD: Int32) async {
        while !Task.isCancelled {
            let clientFD = accept(socketFD, nil, nil)
            if clientFD < 0 {
                if errno == EINTR { continue }
                break
            }

            let requestData = Self.readAll(from: clientFD)
            let responseData: Data
            if let requestData,
               let request = try? decoder.decode(TerminalMemoryCLIRequest.self, from: requestData) {
                let response: TerminalMemoryCLIResponse
                do {
                    response = try await processRequest(request)
                } catch {
                    response = TerminalMemoryCLIResponse(
                        ok: false,
                        message: error.localizedDescription,
                        errorCode: String(describing: error)
                    )
                }
                responseData = (try? encoder.encode(response)) ?? Data(#"{"ok":false,"message":"Encoding failed."}"#.utf8)
            } else {
                responseData = Data(#"{"ok":false,"message":"Invalid request."}"#.utf8)
            }

            _ = responseData.withUnsafeBytes { bytes in
                write(clientFD, bytes.baseAddress, bytes.count)
            }
            _ = "\n".utf8CString.withUnsafeBytes { bytes in
                write(clientFD, bytes.baseAddress, bytes.count - 1)
            }
            shutdown(clientFD, SHUT_RDWR)
            close(clientFD)
        }
    }

    private static func readAll(from fileDescriptor: Int32) -> Data? {
        var buffer = [UInt8](repeating: 0, count: 4096)
        var data = Data()

        while true {
            let bytesRead = read(fileDescriptor, &buffer, buffer.count)
            if bytesRead > 0 {
                data.append(buffer, count: bytesRead)
                continue
            }
            break
        }

        return data.isEmpty ? nil : data
    }

    private static func withUnixSocketAddress<T>(
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
            throw TerminalMemoryError.socketSetupFailed("Socket path is too long.")
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
}
