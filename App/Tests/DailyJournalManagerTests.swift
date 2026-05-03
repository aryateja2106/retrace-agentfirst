import XCTest
import Database
@testable import App

final class DailyJournalManagerTests: XCTestCase {
    func testDailyJournalWriterPreventsDuplicateWindowMarkers() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("DailyJournalWriterTests_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let writer = DailyJournalWriter(folder: folder)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(3_600)

        let fileURL = try writer.append(
            summary: "- Worked on the agent CLI.",
            startDate: start,
            endDate: end,
            sampleCount: 4,
            appNames: ["Cursor"],
            dryRun: false
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(writer.containsWindow(startDate: start, endDate: end))
    }

    func testDryRunResultDoesNotNeedJournalFile() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let result = JournalGenerationResult(
            status: .generated,
            reason: "dry_run",
            filePath: nil,
            startDate: start,
            endDate: start.addingTimeInterval(3_600)
        )

        XCTAssertEqual(result.reason, "dry_run")
        XCTAssertNil(result.filePath)
    }

    func testJournalPromptRendererIncludesAgentContextShape() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = ActivityContextQueries.Sample(
            frameID: 42,
            timestamp: start,
            appBundleID: "com.todesktop.cursor",
            windowName: "Retrace",
            browserURL: nil,
            mainText: "Implemented bounded OCR sampling for the journal.",
            chromeText: nil,
            titleText: "Cursor"
        )
        let digest = ActivityContextDigest(
            startDate: start,
            endDate: start.addingTimeInterval(3_600),
            samples: [sample],
            promptText: "Cursor - Retrace\nImplemented bounded OCR sampling for the journal.",
            appNames: ["Cursor"]
        )

        let prompt = JournalPromptRenderer.render(digest: digest)

        XCTAssertTrue(prompt.contains("Agent context"))
        XCTAssertTrue(prompt.contains("Possible next steps"))
        XCTAssertTrue(prompt.contains("Implemented bounded OCR sampling"))
    }
}
