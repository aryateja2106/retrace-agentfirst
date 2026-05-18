import XCTest
@testable import Retrace

final class FeedbackSubmissionProgressTests: XCTestCase {
    func testBugSubmissionStagesIncludeCrashDiagnosticsSteps() {
        let steps = FeedbackSubmissionProgress.steps(
            for: .bug,
            currentStage: .crashReports
        )

        XCTAssertEqual(
            steps.map(\.title),
            [
                "Compiling crash reports",
                "Getting recent logs",
                "Collecting device snapshot",
                "Bundling diagnostics",
                "Sending feedback",
                "Verifying delivery"
            ]
        )
    }

    func testFeatureSubmissionStagesSkipCrashSpecificSteps() {
        let steps = FeedbackSubmissionProgress.steps(
            for: .feature,
            currentStage: .preparing
        )

        XCTAssertEqual(
            steps.map(\.title),
            [
                "Preparing your request",
                "Collecting app snapshot",
                "Bundling attachments",
                "Sending feedback",
                "Verifying delivery"
            ]
        )
    }

    func testStatusesAdvanceAsSubmissionMovesForward() {
        let steps = FeedbackSubmissionProgress.steps(
            for: .bug,
            currentStage: .upload
        )

        XCTAssertEqual(
            steps.map(\.status),
            [.complete, .complete, .complete, .complete, .active, .pending]
        )
    }

    func testAutomaticStagesStopBeforeUploadAndConfirmation() {
        XCTAssertEqual(
            FeedbackSubmissionProgress.automaticStages(for: .bug),
            [.recentLogs, .deviceSnapshot, .packaging]
        )
        XCTAssertEqual(
            FeedbackSubmissionProgress.automaticStages(for: .feature),
            [.deviceSnapshot, .packaging]
        )
    }

    func testSubmittedCompletionUsesLiveChatSuccessPresentation() {
        let presentation = FeedbackCompletionState.submitted.presentation

        XCTAssertEqual(presentation.title, "Feedback Sent!")
        XCTAssertEqual(presentation.detail, "Thanks for helping improve Retrace Agentfirst.")
        XCTAssertEqual(presentation.callToActionTitle, "Need to add more context?")
        XCTAssertEqual(presentation.linkTitle, "Open an issue on GitHub")
        XCTAssertEqual(presentation.linkURL, URL(string: "https://github.com/aryateja2106/retrace-agentfirst/issues/new/choose"))
        XCTAssertEqual(presentation.linkSymbolName, "exclamationmark.bubble.fill")
    }

    func testExportedCompletionUsesDirectChatSuccessPresentation() {
        let presentation = FeedbackCompletionState.exported.presentation

        XCTAssertEqual(presentation.title, "Download Complete")
        XCTAssertTrue(presentation.detail.contains("Attach it to a GitHub issue"))
        XCTAssertEqual(presentation.callToActionTitle, "Next Steps:")
        XCTAssertEqual(presentation.linkTitle, "Create a GitHub Issue")
        XCTAssertEqual(presentation.linkURL, URL(string: "https://github.com/aryateja2106/retrace-agentfirst/issues/new/choose"))
        XCTAssertEqual(presentation.linkSymbolName, "exclamationmark.bubble.fill")
    }

    @MainActor
    func testNetworkSubmissionFailureUsesSpecificCopy() {
        let failure = FeedbackViewModel.makeSubmissionFailure(
            from: FeedbackError.networkError("The Internet connection appears to be offline.")
        )

        XCTAssertEqual(failure.title, "No network connection")
        XCTAssertEqual(failure.symbolName, "wifi.slash")
        XCTAssertTrue(failure.isNetworkRelated)
        XCTAssertTrue(failure.detail.contains("Download .json.gz"))
    }

    @MainActor
    func testGenericSubmissionFailureFallsBackToLocalizedDescription() {
        let failure = FeedbackViewModel.makeSubmissionFailure(from: FeedbackError.submissionFailed)

        XCTAssertEqual(failure.title, "Feedback wasn't sent")
        XCTAssertEqual(failure.symbolName, "exclamationmark.triangle.fill")
        XCTAssertFalse(failure.isNetworkRelated)
        XCTAssertEqual(failure.detail, FeedbackError.submissionFailed.localizedDescription)
    }
}
