import Foundation

public struct TerminalTaskID: Hashable, Codable, Sendable, Identifiable, Equatable {
    public let value: Int64

    public var id: Int64 { value }

    public init(value: Int64) {
        self.value = value
    }

    public init?(string: String) {
        guard let int64 = Int64(string) else { return nil }
        self.value = int64
    }

    public var stringValue: String { String(value) }
}

public enum TerminalTaskSource: String, Codable, Sendable, CaseIterable {
    case shellHook = "shell_hook"
    case warpHook = "warp_hook"
    case imported = "imported"
    case manual = "manual"
}

public enum TerminalTaskEventType: String, Codable, Sendable, CaseIterable {
    case prompt = "prompt"
    case commandStart = "command_start"
    case commandEnd = "command_end"
    case frameLinked = "frame_linked"
}

public struct TerminalTaskSession: Codable, Sendable, Equatable, Identifiable {
    public let id: TerminalTaskID
    public let bundleID: String
    public let windowName: String?
    public let taskTitle: String?
    public let workingDirectory: String?
    public let shell: String?
    public let sessionKey: String
    public let startDate: Date
    public let endDate: Date?
    public let lastActivityAt: Date
    public let source: TerminalTaskSource
    public let confidence: Double
    public let commandCount: Int
    public let metadataJSON: String?

    public init(
        id: TerminalTaskID,
        bundleID: String,
        windowName: String?,
        taskTitle: String?,
        workingDirectory: String?,
        shell: String?,
        sessionKey: String,
        startDate: Date,
        endDate: Date?,
        lastActivityAt: Date,
        source: TerminalTaskSource,
        confidence: Double,
        commandCount: Int,
        metadataJSON: String?
    ) {
        self.id = id
        self.bundleID = bundleID
        self.windowName = windowName
        self.taskTitle = taskTitle
        self.workingDirectory = workingDirectory
        self.shell = shell
        self.sessionKey = sessionKey
        self.startDate = startDate
        self.endDate = endDate
        self.lastActivityAt = lastActivityAt
        self.source = source
        self.confidence = confidence
        self.commandCount = commandCount
        self.metadataJSON = metadataJSON
    }

    public var duration: TimeInterval {
        (endDate ?? lastActivityAt).timeIntervalSince(startDate)
    }

    public var effectiveTitle: String {
        if let windowName, !windowName.isEmpty {
            return windowName
        }
        if let taskTitle, !taskTitle.isEmpty {
            return taskTitle
        }
        if let workingDirectory, !workingDirectory.isEmpty {
            return workingDirectory
        }
        return "Terminal task"
    }
}

public struct TerminalTaskEvent: Codable, Sendable, Equatable, Identifiable {
    public let id: Int64
    public let taskID: TerminalTaskID
    public let timestamp: Date
    public let eventType: TerminalTaskEventType
    public let commandText: String?
    public let exitCode: Int?
    public let durationMs: Int?
    public let workingDirectory: String?
    public let metadataJSON: String?

    public init(
        id: Int64,
        taskID: TerminalTaskID,
        timestamp: Date,
        eventType: TerminalTaskEventType,
        commandText: String?,
        exitCode: Int?,
        durationMs: Int?,
        workingDirectory: String?,
        metadataJSON: String?
    ) {
        self.id = id
        self.taskID = taskID
        self.timestamp = timestamp
        self.eventType = eventType
        self.commandText = commandText
        self.exitCode = exitCode
        self.durationMs = durationMs
        self.workingDirectory = workingDirectory
        self.metadataJSON = metadataJSON
    }
}

public struct TerminalTaskUsage: Codable, Sendable, Equatable {
    public let task: TerminalTaskSession
    public let linkedFrameCount: Int
    public let totalDuration: TimeInterval

    public init(task: TerminalTaskSession, linkedFrameCount: Int, totalDuration: TimeInterval) {
        self.task = task
        self.linkedFrameCount = linkedFrameCount
        self.totalDuration = totalDuration
    }
}

public struct TerminalTaskFrameLink: Codable, Sendable, Equatable {
    public let frameID: FrameID
    public let taskID: TerminalTaskID

    public init(frameID: FrameID, taskID: TerminalTaskID) {
        self.frameID = frameID
        self.taskID = taskID
    }
}

public struct TerminalTaskSearchResult: Codable, Sendable, Equatable, Identifiable {
    public let task: TerminalTaskSession
    public let matchedCommandPreview: String?

    public var id: TerminalTaskID { task.id }

    public init(task: TerminalTaskSession, matchedCommandPreview: String?) {
        self.task = task
        self.matchedCommandPreview = matchedCommandPreview
    }
}
