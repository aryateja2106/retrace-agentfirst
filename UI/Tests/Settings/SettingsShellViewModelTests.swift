import XCTest
import App
@testable import Retrace

@MainActor
final class SettingsShellViewModelTests: XCTestCase {
    func testInitializerHonorsInitialTabAndScrollTarget() {
        let viewModel = SettingsShellViewModel(
            initialTab: .power,
            initialScrollTargetID: "settings.powerOCRCard"
        )

        XCTAssertEqual(viewModel.selectedTab, .power)
        XCTAssertEqual(viewModel.pendingScrollTargetID, "settings.powerOCRCard")
    }

    func testSearchResultsMatchKeywordsAndTitles() {
        let ocrResults = SettingsShellViewModel.searchResults(for: "ocr")
        let shortcutResults = SettingsShellViewModel.searchResults(for: "shortcut")
        let captureAnimationResults = SettingsShellViewModel.searchResults(for: "capture animation")

        XCTAssertTrue(ocrResults.contains(where: { $0.id == "power.ocrProcessing" }))
        XCTAssertTrue(shortcutResults.contains(where: { $0.id == "general.shortcuts" }))
        XCTAssertTrue(captureAnimationResults.contains(where: { $0.id == "capture.menuBarIcon" }))
    }

    func testSearchResultsIncludeContextLocalModelSurfaces() {
        let ollamaResults = SettingsShellViewModel.searchResults(for: "ollama")
        let agentCLIResults = SettingsShellViewModel.searchResults(for: "agent cli")
        let obsidianResults = SettingsShellViewModel.searchResults(for: "obsidian")

        XCTAssertTrue(ollamaResults.contains(where: { $0.id == "context.journal" }))
        XCTAssertTrue(agentCLIResults.contains(where: { $0.id == "context.cli" }))
        XCTAssertTrue(obsidianResults.contains(where: { $0.id == "context.integrations" }))
    }

    func testVoiceTabIsAvailableForSettingsNavigation() {
        XCTAssertTrue(SettingsTab.allCases.contains(.voice))
        XCTAssertEqual(SettingsTab.voice.rawValue, "Voice")
        XCTAssertEqual(SettingsTab.voice.icon, "waveform")
    }

    func testSearchResultsIncludeVoiceSettingsSurfaces() {
        let dictationResults = SettingsShellViewModel.searchResults(for: "dictation")
        let clipboardResults = SettingsShellViewModel.searchResults(for: "clipboard")
        let vocabularyResults = SettingsShellViewModel.searchResults(for: "custom words")
        let idleModelResults = SettingsShellViewModel.searchResults(for: "unload model")

        XCTAssertTrue(dictationResults.contains(where: { $0.id == "voice.activation" }))
        XCTAssertTrue(clipboardResults.contains(where: { $0.id == "voice.output" }))
        XCTAssertTrue(vocabularyResults.contains(where: { $0.id == "voice.customWords" }))
        XCTAssertTrue(idleModelResults.contains(where: { $0.id == "voice.modelLifecycle" }))
    }

    func testContextOllamaStatusPresentationShowsRecommendedInstalledModel() {
        let status = OllamaModelStatus(
            baseURL: "http://localhost:11434",
            requestedModel: "gemma4:e2b",
            isReachable: true,
            isModelInstalled: false,
            installedModels: ["gemma4:e4b"],
            recommendedModel: "gemma4:e4b",
            pullCommand: "ollama pull gemma4:e2b"
        )

        let presentation = ContextOllamaStatusPresentation.make(status: status)

        XCTAssertTrue(presentation.isError)
        XCTAssertTrue(presentation.message.contains("gemma4:e4b is available"))
    }

    func testContextOllamaStatusPresentationShowsReachabilityFailure() {
        let presentation = ContextOllamaStatusPresentation.makeFailure(baseURL: "http://localhost:11434")

        XCTAssertTrue(presentation.isError)
        XCTAssertTrue(presentation.message.contains("Start Ollama"))
    }

    func testScheduleSettingsSearchResetClearsQueryAfterDelay() async {
        let viewModel = SettingsShellViewModel()
        viewModel.settingsSearchQuery = "privacy"

        viewModel.scheduleSettingsSearchReset()
        try? await Task.sleep(for: .nanoseconds(Int64(250_000_000)), clock: .continuous)

        XCTAssertEqual(viewModel.settingsSearchQuery, "")
    }

    func testCancelSettingsSearchResetKeepsQuery() async {
        let viewModel = SettingsShellViewModel()
        viewModel.settingsSearchQuery = "power"

        viewModel.scheduleSettingsSearchReset()
        viewModel.cancelSettingsSearchReset()
        try? await Task.sleep(for: .nanoseconds(Int64(250_000_000)), clock: .continuous)

        XCTAssertEqual(viewModel.settingsSearchQuery, "power")
    }
}
