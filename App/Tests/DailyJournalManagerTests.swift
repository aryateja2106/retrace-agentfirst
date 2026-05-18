import XCTest
import Database
@testable import App

final class DailyJournalManagerTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

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

    func testDailyJournalConfigurationDefaultsToEfficientInstalledModelCandidate() {
        let suiteName = "DailyJournalConfigurationTests_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = DailyJournalConfiguration.read(from: defaults)

        XCTAssertEqual(configuration.ollamaBaseURL.absoluteString, DailyJournalConfiguration.defaultOllamaBaseURLString)
        XCTAssertEqual(configuration.ollamaModel, "gemma4:e4b")
        XCTAssertEqual(configuration.cadenceSeconds, 3_600)
    }

    func testDailyJournalConfigurationFallsBackForInvalidBaseURLAndClampsCadence() {
        let suiteName = "DailyJournalConfigurationTests_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("not a url", forKey: DailyJournalConfiguration.ollamaBaseURLKey)
        defaults.set("custom-model", forKey: DailyJournalConfiguration.ollamaModelKey)
        defaults.set(60, forKey: DailyJournalConfiguration.cadenceSecondsKey)

        let configuration = DailyJournalConfiguration.read(from: defaults)

        XCTAssertEqual(configuration.ollamaBaseURL.absoluteString, DailyJournalConfiguration.defaultOllamaBaseURLString)
        XCTAssertEqual(configuration.ollamaModel, "custom-model")
        XCTAssertEqual(configuration.cadenceSeconds, 900)
    }

    func testOllamaStatusSortsInstalledModelsAndRecommendsAvailableModel() async throws {
        let client = OllamaClient(
            baseURL: URL(string: "http://localhost:11434")!,
            session: makeStubbedSession(statusCode: 200, body: """
            {
              "models": [
                {"name": "nomic-embed-text:latest"},
                {"name": "gemma4:e4b"}
              ]
            }
            """)
        )

        let status = try await client.status(model: "gemma4:e2b")

        XCTAssertEqual(status.installedModels, ["gemma4:e4b", "nomic-embed-text:latest"])
        XCTAssertFalse(status.isModelInstalled)
        XCTAssertEqual(status.recommendedModel, "gemma4:e4b")
        XCTAssertEqual(status.pullCommand, "ollama pull gemma4:e2b")
    }

    func testOllamaStatusMarksExactInstalledModel() async throws {
        let client = OllamaClient(
            baseURL: URL(string: "http://localhost:11434")!,
            session: makeStubbedSession(statusCode: 200, body: """
            {"models": [{"name": "gemma4:e4b"}]}
            """)
        )

        let status = try await client.status(model: "gemma4:e4b")

        XCTAssertTrue(status.isModelInstalled)
        XCTAssertEqual(status.recommendedModel, "gemma4:e4b")
    }

    func testOllamaStatusThrowsForNonSuccessResponse() async throws {
        let client = OllamaClient(
            baseURL: URL(string: "http://localhost:11434")!,
            session: makeStubbedSession(statusCode: 500, body: #"{"error":"nope"}"#)
        )

        do {
            _ = try await client.status(model: "gemma4:e4b")
            XCTFail("Expected status to throw")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    private func makeStubbedSession(statusCode: Int, body: String) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(body.utf8))
        }
        return URLSession(configuration: configuration)
    }

}

private final class URLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
