import AppKit
import Foundation

enum VoiceOverlayDefaults {
    static let suiteName = "io.retrace.app"

    static let transcriptHistory = "voiceOverlayTranscriptHistory"
    static let customWords = "voiceCustomWordsRaw"
    static let keepTranscriptHistory = "voiceOverlayKeepTranscriptHistory"
    static let transcriptHistoryLimit = "voiceHistoryLimit"
    static let lastDraftTranscript = "voiceOverlayLastDraftTranscript"

    static let defaultHistoryLimit = 25
}

struct VoiceTranscriptHistoryItem: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let transcript: String
    let createdAt: Date

    init(id: UUID = UUID(), transcript: String, createdAt: Date = Date()) {
        self.id = id
        self.transcript = transcript
        self.createdAt = createdAt
    }
}

enum VoiceOverlayMetricEvent: Equatable, Sendable {
    case draftStarted(source: String)
    case transcriptUpdated(characterCount: Int)
    case customWordsApplied(replacementCount: Int)
    case transcriptCopied(characterCount: Int, historyCount: Int)
    case cancelled(hadTranscript: Bool)
}

@MainActor
final class VoiceOverlayViewModel: ObservableObject {
    typealias ClipboardWriter = @MainActor (String) -> Void
    typealias DateProvider = @MainActor () -> Date
    typealias IDProvider = @MainActor () -> UUID
    typealias MetricRecorder = @MainActor (VoiceOverlayMetricEvent) -> Void

    @Published private(set) var isDraftActive = false
    @Published var transcript: String = ""
    @Published private(set) var history: [VoiceTranscriptHistoryItem]
    @Published private(set) var statusMessage: String?

    private let defaults: UserDefaults
    private let clipboardWriter: ClipboardWriter
    private let dateProvider: DateProvider
    private let idProvider: IDProvider
    private let metricRecorder: MetricRecorder
    private let historyLimitFallback: Int

    init(
        defaults: UserDefaults = UserDefaults(suiteName: VoiceOverlayDefaults.suiteName) ?? .standard,
        clipboardWriter: @escaping ClipboardWriter = VoiceOverlayViewModel.writeToGeneralPasteboard,
        dateProvider: @escaping DateProvider = Date.init,
        idProvider: @escaping IDProvider = UUID.init,
        metricRecorder: @escaping MetricRecorder = { _ in },
        historyLimitFallback: Int = VoiceOverlayDefaults.defaultHistoryLimit
    ) {
        self.defaults = defaults
        self.clipboardWriter = clipboardWriter
        self.dateProvider = dateProvider
        self.idProvider = idProvider
        self.metricRecorder = metricRecorder
        self.historyLimitFallback = historyLimitFallback
        self.history = Self.loadHistory(from: defaults)
    }

    var trimmedTranscript: String {
        transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canCopyTranscript: Bool {
        !trimmedTranscript.isEmpty
    }

    var customWordsText: String {
        get { defaults.string(forKey: VoiceOverlayDefaults.customWords) ?? SettingsDefaults.voiceCustomWordsRaw }
        set { defaults.set(newValue, forKey: VoiceOverlayDefaults.customWords) }
    }

    var keepsTranscriptHistory: Bool {
        get {
            guard defaults.object(forKey: VoiceOverlayDefaults.keepTranscriptHistory) != nil else {
                return true
            }
            return defaults.bool(forKey: VoiceOverlayDefaults.keepTranscriptHistory)
        }
        set { defaults.set(newValue, forKey: VoiceOverlayDefaults.keepTranscriptHistory) }
    }

    var transcriptHistoryLimit: Int {
        let storedLimit = defaults.integer(forKey: VoiceOverlayDefaults.transcriptHistoryLimit)
        return storedLimit > 0 ? storedLimit : historyLimitFallback
    }

    func startDraftSession(source: String = "voice_overlay") {
        isDraftActive = true
        transcript = ""
        statusMessage = nil
        defaults.removeObject(forKey: VoiceOverlayDefaults.lastDraftTranscript)
        metricRecorder(.draftStarted(source: source))
    }

    func updateTranscript(_ newTranscript: String) {
        transcript = newTranscript
        defaults.set(newTranscript, forKey: VoiceOverlayDefaults.lastDraftTranscript)
        statusMessage = nil
        metricRecorder(.transcriptUpdated(characterCount: newTranscript.count))
    }

    func applyCustomWords() {
        let replacements = Self.parseCustomWordReplacements(customWordsText)
        guard !replacements.isEmpty else {
            statusMessage = "No custom words configured."
            metricRecorder(.customWordsApplied(replacementCount: 0))
            return
        }

        var replacementCount = 0
        var updatedTranscript = transcript
        for replacement in replacements {
            let nextTranscript = updatedTranscript.replacingOccurrences(
                of: replacement.source,
                with: replacement.target,
                options: [.caseInsensitive, .diacriticInsensitive]
            )
            if nextTranscript != updatedTranscript {
                replacementCount += 1
                updatedTranscript = nextTranscript
            }
        }

        transcript = updatedTranscript
        defaults.set(updatedTranscript, forKey: VoiceOverlayDefaults.lastDraftTranscript)
        statusMessage = replacementCount == 0 ? "No custom word matches found." : "Custom words applied."
        metricRecorder(.customWordsApplied(replacementCount: replacementCount))
    }

    func copyTranscriptToClipboard() {
        let textToCopy = trimmedTranscript
        guard !textToCopy.isEmpty else {
            statusMessage = "Nothing to copy."
            return
        }

        clipboardWriter(textToCopy)
        if keepsTranscriptHistory {
            addHistoryItem(textToCopy)
        }
        statusMessage = "Transcript copied."
        metricRecorder(.transcriptCopied(characterCount: textToCopy.count, historyCount: history.count))
    }

    func cancel() {
        let hadTranscript = !trimmedTranscript.isEmpty
        isDraftActive = false
        transcript = ""
        statusMessage = nil
        defaults.removeObject(forKey: VoiceOverlayDefaults.lastDraftTranscript)
        metricRecorder(.cancelled(hadTranscript: hadTranscript))
    }

    private func addHistoryItem(_ transcript: String) {
        let newItem = VoiceTranscriptHistoryItem(
            id: idProvider(),
            transcript: transcript,
            createdAt: dateProvider()
        )
        let dedupedHistory = history.filter { $0.transcript != transcript }
        history = Array(([newItem] + dedupedHistory).prefix(transcriptHistoryLimit))
        persistHistory()
    }

    private func persistHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        defaults.set(data, forKey: VoiceOverlayDefaults.transcriptHistory)
    }

    private static func loadHistory(from defaults: UserDefaults) -> [VoiceTranscriptHistoryItem] {
        guard let data = defaults.data(forKey: VoiceOverlayDefaults.transcriptHistory),
              let decoded = try? JSONDecoder().decode([VoiceTranscriptHistoryItem].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func parseCustomWordReplacements(_ rawValue: String) -> [CustomWordReplacement] {
        rawValue
            .components(separatedBy: .newlines)
            .compactMap { line in
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedLine.isEmpty else { return nil }

                let separators = ["=>", "=", ":"]
                guard let separator = separators.first(where: { trimmedLine.contains($0) }) else {
                    return nil
                }

                let parts = trimmedLine.components(separatedBy: separator)
                guard parts.count >= 2 else { return nil }
                let source = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let target = parts.dropFirst().joined(separator: separator).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !source.isEmpty, !target.isEmpty else { return nil }
                return CustomWordReplacement(source: source, target: target)
            }
    }

    private static func writeToGeneralPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

private struct CustomWordReplacement: Equatable {
    let source: String
    let target: String
}
