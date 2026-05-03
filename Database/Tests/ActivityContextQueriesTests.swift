import XCTest
import SQLCipher
@testable import Database

final class ActivityContextQueriesTests: XCTestCase {
    private var database: DatabaseManager!

    override func setUp() async throws {
        database = DatabaseManager(databasePath: "file:activity_context_\(UUID().uuidString)?mode=memory&cache=private")
        try await database.initialize()
    }

    override func tearDown() async throws {
        try await database.close()
        database = nil
    }

    func testFetchSamplesReadsRealIndexedOCRRowsWithinCaps() async throws {
        let connection = await database.getConnection()
        let db = try XCTUnwrap(connection)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        try seedContextRow(
            db: db,
            frameID: 1,
            timestamp: timestamp,
            text: "Implemented read-only context query over persisted OCR text.",
            title: "Cursor"
        )

        let samples = try ActivityContextQueries.fetchSamples(
            db: db,
            from: timestamp.addingTimeInterval(-60),
            to: timestamp.addingTimeInterval(60),
            limit: 10,
            maxTextLength: 24
        )

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].frameID, 1)
        XCTAssertEqual(samples[0].appBundleID, "com.todesktop.cursor")
        XCTAssertEqual(samples[0].displayAppName, "Cursor")
        XCTAssertTrue(samples[0].mainText.hasPrefix("Implemented read-only context"))
        XCTAssertLessThanOrEqual(samples[0].mainText.count, 128)
    }

    func testSearchSamplesUsesFTSRowsAndTimeBounds() async throws {
        let connection = await database.getConnection()
        let db = try XCTUnwrap(connection)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        try seedContextRow(
            db: db,
            frameID: 2,
            timestamp: timestamp,
            text: "Journal generation should summarize OCR context.",
            title: "Notes"
        )

        let matches = try ActivityContextQueries.searchSamples(
            db: db,
            query: "journal",
            from: timestamp.addingTimeInterval(-60),
            to: timestamp.addingTimeInterval(60),
            limit: 10,
            maxTextLength: 200
        )

        XCTAssertEqual(matches.map(\.frameID), [2])
    }

    private func seedContextRow(
        db: OpaquePointer,
        frameID: Int64,
        timestamp: Date,
        text: String,
        title: String
    ) throws {
        let timestampMs = Int64(timestamp.timeIntervalSince1970 * 1_000)
        try exec(db, "INSERT INTO segment (id, bundleID, startDate, endDate, windowName, browserUrl, type) VALUES (1, 'com.todesktop.cursor', \(timestampMs - 1000), \(timestampMs + 1000), 'Retrace', NULL, 0);")
        try exec(db, "INSERT INTO frame (id, createdAt, imageFileName, segmentId, processingStatus) VALUES (\(frameID), \(timestampMs), 'test', 1, 2);")

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let insertContent = "INSERT INTO searchRanking (rowid, text, otherText, title) VALUES (?, ?, '', ?);"
        XCTAssertEqual(sqlite3_prepare_v2(db, insertContent, -1, &statement, nil), SQLITE_OK)
        sqlite3_bind_int64(statement, 1, frameID)
        sqlite3_bind_text(statement, 2, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(statement, 3, title, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)

        try exec(db, "INSERT INTO doc_segment (docid, segmentId, frameId) VALUES (\(frameID), 1, \(frameID));")
    }

    private func exec(_ db: OpaquePointer, _ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorMessage) }
        if sqlite3_exec(db, sql, nil, nil, &errorMessage) != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            XCTFail("SQL failed: \(message)")
            throw NSError(domain: "ActivityContextQueriesTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
