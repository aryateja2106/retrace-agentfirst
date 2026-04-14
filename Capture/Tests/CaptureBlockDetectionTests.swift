import XCTest
@testable import Capture

final class CaptureBlockDetectionTests: XCTestCase {
    func testCaptureBlockReasonDetectsLoginWindowOwner() {
        let reason = CGWindowListCapture.captureBlockReason(ownerName: "loginwindow", bundleID: nil)
        XCTAssertEqual(reason, "loginwindow-visible")
    }

    func testCaptureBlockReasonDetectsLoginWindowBundle() {
        let reason = CGWindowListCapture.captureBlockReason(ownerName: "Window Server", bundleID: "com.apple.loginwindow")
        XCTAssertEqual(reason, "loginwindow-visible")
    }

    func testCaptureBlockReasonDetectsScreenSaverOwner() {
        let reason = CGWindowListCapture.captureBlockReason(ownerName: "ScreenSaverEngine", bundleID: nil)
        XCTAssertEqual(reason, "screensaver-visible")
    }

    func testCaptureBlockReasonDetectsScreenSaverBundle() {
        let reason = CGWindowListCapture.captureBlockReason(
            ownerName: "Window Server",
            bundleID: "com.apple.ScreenSaver.Engine"
        )
        XCTAssertEqual(reason, "screensaver-visible")
    }

    func testCaptureBlockReasonIgnoresNormalApplications() {
        let reason = CGWindowListCapture.captureBlockReason(ownerName: "Brave Browser", bundleID: "com.brave.Browser")
        XCTAssertNil(reason)
    }

    func testTerminalBundleRegistryRecognizesSupportedTerminalApps() {
        XCTAssertTrue(TerminalBundleRegistry.isSupportedApp(TerminalBundleRegistry.warpBundleID))
        XCTAssertTrue(TerminalBundleRegistry.isSupportedApp(TerminalBundleRegistry.terminalBundleID))
        XCTAssertTrue(TerminalBundleRegistry.isSupportedApp(TerminalBundleRegistry.iTermBundleID))
        XCTAssertFalse(TerminalBundleRegistry.isSupportedApp("com.apple.Safari"))
    }

    func testTerminalBundleRegistryNormalizesWarpWindowTitlesForCorrelation() {
        XCTAssertEqual(
            TerminalBundleRegistry.normalizedWindowName("• ~/Projects/retrace — Warp", bundleID: TerminalBundleRegistry.warpBundleID),
            "~/Projects/retrace"
        )
        XCTAssertEqual(
            TerminalBundleRegistry.normalizedWindowName("* Claude Code - Warp", bundleID: TerminalBundleRegistry.warpBundleID),
            "Claude Code"
        )
    }
}
