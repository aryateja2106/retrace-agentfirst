import XCTest
import AppKit
import Combine
import Shared
import App
@testable import Retrace

final class DashboardWindowTitleFormatterTests: XCTestCase {
    func testSupportedBrowserBreakdownTreatsCometAsBrowser() {
        let app = AppUsageData(
            appBundleID: "ai.perplexity.comet",
            appName: "Comet",
            duration: 120,
            uniqueItemCount: 2,
            percentage: 0.25
        )

        XCTAssertTrue(app.isBrowser)
        XCTAssertEqual(app.uniqueItemLabel, "2 websites")
    }

    func testSupportedBrowserBreakdownTreatsChromeCanaryAsBrowser() {
        let app = AppUsageData(
            appBundleID: "com.google.Chrome.canary",
            appName: "Chrome Canary",
            duration: 120,
            uniqueItemCount: 1,
            percentage: 0.25
        )

        XCTAssertTrue(app.isBrowser)
        XCTAssertEqual(app.uniqueItemLabel, "1 website")
    }

    func testSupportedTerminalBreakdownTreatsWarpAsTerminal() {
        let app = AppUsageData(
            appBundleID: "dev.warp.Warp-Stable",
            appName: "Warp",
            duration: 120,
            uniqueItemCount: 3,
            percentage: 0.25
        )

        XCTAssertTrue(app.isTerminal)
        XCTAssertEqual(app.uniqueItemLabel, "3 tasks")
    }

    func testStripsWebPrefixForChromePWAAppShimBundle() {
        let result = DashboardWindowTitleFormatter.displayTitle(
            for: "ChatGPT Web - New Chat",
            appBundleID: "com.google.Chrome.app.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        )

        XCTAssertEqual(result, "New Chat")
    }

    func testStripsUnreadBadgeAfterWebPrefix() {
        let result = DashboardWindowTitleFormatter.displayTitle(
            for: "Notion Web - (4) Project Roadmap",
            appBundleID: "com.google.Chrome.app.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        )

        XCTAssertEqual(result, "Project Roadmap")
    }

    func testStripsDomainPrefixForChromePWAAppShimBundle() {
        let result = DashboardWindowTitleFormatter.displayTitle(
            for: "timetracking.live - Weekly Report",
            appBundleID: "com.google.Chrome.app.cccccccccccccccccccccccccccccccc"
        )

        XCTAssertEqual(result, "Weekly Report")
    }

    func testKeepsRegularChromeTabTitlesUntouched() {
        let result = DashboardWindowTitleFormatter.displayTitle(
            for: "Feature request - GitHub",
            appBundleID: "com.google.Chrome"
        )

        XCTAssertEqual(result, "Feature request - GitHub")
    }

    func testKeepsNonChromeTitlesUntouched() {
        let result = DashboardWindowTitleFormatter.displayTitle(
            for: "Terminal - zsh",
            appBundleID: "com.apple.Terminal"
        )

        XCTAssertEqual(result, "Terminal - zsh")
    }

    func testWindowUsageDataMarksTerminalTaskRows() {
        let window = WindowUsageData(
            windowName: "Claude Code",
            isWebsite: false,
            duration: 300,
            percentage: 0.6,
            taskID: TerminalTaskID(value: 42),
            subtitle: "~/Projects/retrace",
            commandCount: 12,
            lastActiveAt: Date(timeIntervalSince1970: 1_700_000_000),
            workingDirectory: "~/Projects/retrace"
        )

        XCTAssertTrue(window.isTerminalTask)
        XCTAssertEqual(window.displayName, "Claude Code")
        XCTAssertEqual(window.workingDirectory, "~/Projects/retrace")
    }
}
