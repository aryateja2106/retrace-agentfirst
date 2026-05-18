import XCTest
@testable import Retrace

@MainActor
final class VoiceOverlayViewModelTests: XCTestCase {
    func testStartUpdateAndCancelDraftSession() {
        let defaults = makeDefaults()
        var events: [VoiceOverlayMetricEvent] = []
        let viewModel = VoiceOverlayViewModel(defaults: defaults, metricRecorder: { events.append($0) })

        viewModel.startDraftSession(source: "test")
        viewModel.updateTranscript("Hello from voice")

        XCTAssertTrue(viewModel.isDraftActive)
        XCTAssertEqual(viewModel.transcript, "Hello from voice")
        XCTAssertEqual(defaults.string(forKey: VoiceOverlayDefaults.lastDraftTranscript), "Hello from voice")

        viewModel.cancel()

        XCTAssertFalse(viewModel.isDraftActive)
        XCTAssertEqual(viewModel.transcript, "")
        XCTAssertNil(defaults.string(forKey: VoiceOverlayDefaults.lastDraftTranscript))
        XCTAssertEqual(events.last, .cancelled(hadTranscript: true))
    }

    func testApplyCustomWordsUsesDefaultsBackedReplacementRules() {
        let defaults = makeDefaults()
        let viewModel = VoiceOverlayViewModel(defaults: defaults)
        viewModel.customWordsText = """
        retrace agent first => Retrace Agentfirst
        local first = local-first
        """

        viewModel.startDraftSession()
        viewModel.updateTranscript("retrace agent first is local first")
        viewModel.applyCustomWords()

        XCTAssertEqual(viewModel.transcript, "Retrace Agentfirst is local-first")
        XCTAssertEqual(viewModel.statusMessage, "Custom words applied.")
    }

    func testCopyTranscriptWritesClipboardAndStoresBoundedDedupedHistory() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: VoiceOverlayDefaults.keepTranscriptHistory)
        defaults.set(2, forKey: VoiceOverlayDefaults.transcriptHistoryLimit)

        var copiedStrings: [String] = []
        var dates = [
            Date(timeIntervalSince1970: 3),
            Date(timeIntervalSince1970: 2),
            Date(timeIntervalSince1970: 1)
        ]
        var ids = [
            UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        ]

        let viewModel = VoiceOverlayViewModel(
            defaults: defaults,
            clipboardWriter: { copiedStrings.append($0) },
            dateProvider: { dates.removeFirst() },
            idProvider: { ids.removeFirst() }
        )

        viewModel.updateTranscript(" First copied transcript ")
        viewModel.copyTranscriptToClipboard()
        viewModel.updateTranscript("Second copied transcript")
        viewModel.copyTranscriptToClipboard()
        viewModel.updateTranscript("First copied transcript")
        viewModel.copyTranscriptToClipboard()

        XCTAssertEqual(copiedStrings, [
            "First copied transcript",
            "Second copied transcript",
            "First copied transcript"
        ])
        XCTAssertEqual(viewModel.history.map(\.transcript), [
            "First copied transcript",
            "Second copied transcript"
        ])
        XCTAssertNotNil(defaults.data(forKey: VoiceOverlayDefaults.transcriptHistory))
    }

    func testCopyDoesNotStoreHistoryWhenHistoryPreferenceIsDisabled() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: VoiceOverlayDefaults.keepTranscriptHistory)
        var copiedStrings: [String] = []
        let viewModel = VoiceOverlayViewModel(
            defaults: defaults,
            clipboardWriter: { copiedStrings.append($0) }
        )

        viewModel.updateTranscript("No history please")
        viewModel.copyTranscriptToClipboard()

        XCTAssertEqual(copiedStrings, ["No history please"])
        XCTAssertTrue(viewModel.history.isEmpty)
        XCTAssertNil(defaults.data(forKey: VoiceOverlayDefaults.transcriptHistory))
    }

    func testFinishDraftSessionAppliesCustomWordsCopiesAndEndsDraft() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: VoiceOverlayDefaults.keepTranscriptHistory)
        defaults.set(5, forKey: VoiceOverlayDefaults.transcriptHistoryLimit)
        var copiedStrings: [String] = []
        var events: [VoiceOverlayMetricEvent] = []
        let viewModel = VoiceOverlayViewModel(
            defaults: defaults,
            clipboardWriter: { copiedStrings.append($0) },
            metricRecorder: { events.append($0) }
        )

        viewModel.customWordsText = "cloud AI => Claude AI"
        viewModel.startDraftSession()
        viewModel.updateTranscript("Ask cloud AI about Retrace")

        XCTAssertTrue(viewModel.finishDraftSessionAndCopy())

        XCTAssertFalse(viewModel.isDraftActive)
        XCTAssertEqual(viewModel.transcript, "Ask Claude AI about Retrace")
        XCTAssertEqual(copiedStrings, ["Ask Claude AI about Retrace"])
        XCTAssertEqual(viewModel.history.map(\.transcript), ["Ask Claude AI about Retrace"])
        XCTAssertNil(defaults.string(forKey: VoiceOverlayDefaults.lastDraftTranscript))
        XCTAssertTrue(events.contains(.customWordsApplied(replacementCount: 1)))
        XCTAssertTrue(events.contains(.transcriptCopied(characterCount: 27, historyCount: 1)))
    }

    func testFinishDraftSessionWithoutTranscriptCancelsDraft() {
        let defaults = makeDefaults()
        var copiedStrings: [String] = []
        let viewModel = VoiceOverlayViewModel(
            defaults: defaults,
            clipboardWriter: { copiedStrings.append($0) }
        )

        viewModel.startDraftSession()

        XCTAssertFalse(viewModel.finishDraftSessionAndCopy())
        XCTAssertFalse(viewModel.isDraftActive)
        XCTAssertEqual(viewModel.transcript, "")
        XCTAssertTrue(copiedStrings.isEmpty)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "VoiceOverlayViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
