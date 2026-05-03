import Foundation
import SQLCipher
import Shared

/// Read-only context windows for agent and journal features.
///
/// These queries intentionally read already-indexed OCR text instead of touching
/// screenshots or video files, so they stay off the capture and OCR hot paths.
public enum ActivityContextQueries {
    public struct Sample: Codable, Sendable, Equatable {
        public let frameID: Int64
        public let timestamp: Date
        public let appBundleID: String?
        public let windowName: String?
        public let browserURL: String?
        public let mainText: String
        public let chromeText: String?
        public let titleText: String?

        public var displayAppName: String {
            if let titleText = titleText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !titleText.isEmpty {
                return titleText
            }
            if let appBundleID = appBundleID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !appBundleID.isEmpty {
                return appBundleID
            }
            return "Unknown"
        }

        public init(
            frameID: Int64,
            timestamp: Date,
            appBundleID: String?,
            windowName: String?,
            browserURL: String?,
            mainText: String,
            chromeText: String?,
            titleText: String?
        ) {
            self.frameID = frameID
            self.timestamp = timestamp
            self.appBundleID = appBundleID
            self.windowName = windowName
            self.browserURL = browserURL
            self.mainText = mainText
            self.chromeText = chromeText
            self.titleText = titleText
        }
    }

    public static func fetchSamples(
        db: OpaquePointer,
        from startDate: Date,
        to endDate: Date,
        limit: Int,
        maxTextLength: Int,
        newestFirst: Bool = false
    ) throws -> [Sample] {
        let boundedLimit = max(0, min(limit, 2_000))
        guard boundedLimit > 0 else { return [] }

        let boundedTextLength = max(128, min(maxTextLength, 12_000))
        let order = newestFirst ? "DESC" : "ASC"
        let sql = """
            WITH latest_doc AS (
                SELECT frameId, MAX(docid) AS docid
                FROM doc_segment
                WHERE frameId IS NOT NULL
                GROUP BY frameId
            )
            SELECT
                f.id,
                f.createdAt,
                s.bundleID,
                s.windowName,
                s.browserUrl,
                substr(COALESCE(sc.c0, ''), 1, ?),
                substr(COALESCE(sc.c1, ''), 1, ?),
                sc.c2
            FROM frame f
            JOIN latest_doc ld ON ld.frameId = f.id
            JOIN searchRanking_content sc ON sc.id = ld.docid
            LEFT JOIN segment s ON s.id = f.segmentId
            WHERE f.createdAt >= ?
              AND f.createdAt <= ?
              AND (f.processingStatus IS NULL OR f.processingStatus NOT IN (0, 1, 4))
              AND length(trim(COALESCE(sc.c0, '') || COALESCE(sc.c1, '') || COALESCE(sc.c2, ''))) > 0
            ORDER BY f.createdAt \(order), f.id \(order)
            LIMIT ?;
            """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(
                query: sql,
                underlying: String(cString: sqlite3_errmsg(db))
            )
        }

        sqlite3_bind_int(statement, 1, Int32(boundedTextLength))
        sqlite3_bind_int(statement, 2, Int32(min(boundedTextLength, 2_000)))
        sqlite3_bind_int64(statement, 3, Schema.dateToTimestamp(startDate))
        sqlite3_bind_int64(statement, 4, Schema.dateToTimestamp(endDate))
        sqlite3_bind_int(statement, 5, Int32(boundedLimit))

        return try parseRows(statement: statement, db: db, query: sql)
    }

    public static func searchSamples(
        db: OpaquePointer,
        query: String,
        from startDate: Date,
        to endDate: Date,
        limit: Int,
        maxTextLength: Int
    ) throws -> [Sample] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return try fetchSamples(
                db: db,
                from: startDate,
                to: endDate,
                limit: limit,
                maxTextLength: maxTextLength,
                newestFirst: true
            )
        }

        let boundedLimit = max(0, min(limit, 500))
        guard boundedLimit > 0 else { return [] }
        let boundedTextLength = max(128, min(maxTextLength, 12_000))

        let sql = """
            WITH matches AS (
                SELECT rowid AS docid, bm25(searchRanking) AS rank
                FROM searchRanking
                WHERE searchRanking MATCH ?
                LIMIT ?
            )
            SELECT
                f.id,
                f.createdAt,
                s.bundleID,
                s.windowName,
                s.browserUrl,
                substr(COALESCE(sc.c0, ''), 1, ?),
                substr(COALESCE(sc.c1, ''), 1, ?),
                sc.c2
            FROM matches m
            JOIN doc_segment ds ON ds.docid = m.docid
            JOIN frame f ON f.id = ds.frameId
            JOIN searchRanking_content sc ON sc.id = m.docid
            LEFT JOIN segment s ON s.id = f.segmentId
            WHERE f.createdAt >= ?
              AND f.createdAt <= ?
              AND (f.processingStatus IS NULL OR f.processingStatus NOT IN (0, 1, 4))
            ORDER BY m.rank ASC, f.createdAt DESC, f.id DESC
            LIMIT ?;
            """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(
                query: sql,
                underlying: String(cString: sqlite3_errmsg(db))
            )
        }

        sqlite3_bind_text(statement, 1, ftsQuery(from: normalizedQuery), -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 2, Int32(max(boundedLimit * 4, boundedLimit)))
        sqlite3_bind_int(statement, 3, Int32(boundedTextLength))
        sqlite3_bind_int(statement, 4, Int32(min(boundedTextLength, 2_000)))
        sqlite3_bind_int64(statement, 5, Schema.dateToTimestamp(startDate))
        sqlite3_bind_int64(statement, 6, Schema.dateToTimestamp(endDate))
        sqlite3_bind_int(statement, 7, Int32(boundedLimit))

        return try parseRows(statement: statement, db: db, query: sql)
    }

    public static func fetchSamples(
        connection: DatabaseConnection,
        from startDate: Date,
        to endDate: Date,
        limit: Int,
        maxTextLength: Int,
        newestFirst: Bool = false
    ) throws -> [Sample] {
        guard let db = connection.getConnection() else {
            throw DatabaseError.connectionFailed(underlying: "Read connection unavailable")
        }
        return try fetchSamples(
            db: db,
            from: startDate,
            to: endDate,
            limit: limit,
            maxTextLength: maxTextLength,
            newestFirst: newestFirst
        )
    }

    public static func searchSamples(
        connection: DatabaseConnection,
        query: String,
        from startDate: Date,
        to endDate: Date,
        limit: Int,
        maxTextLength: Int
    ) throws -> [Sample] {
        guard let db = connection.getConnection() else {
            throw DatabaseError.connectionFailed(underlying: "Read connection unavailable")
        }
        return try searchSamples(
            db: db,
            query: query,
            from: startDate,
            to: endDate,
            limit: limit,
            maxTextLength: maxTextLength
        )
    }

    private static func parseRows(
        statement: OpaquePointer?,
        db: OpaquePointer,
        query: String
    ) throws -> [Sample] {
        var samples: [Sample] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_DONE {
                return samples
            }
            guard stepResult == SQLITE_ROW else {
                throw DatabaseError.queryFailed(
                    query: query,
                    underlying: String(cString: sqlite3_errmsg(db))
                )
            }

            samples.append(
                Sample(
                    frameID: sqlite3_column_int64(statement, 0),
                    timestamp: Schema.timestampToDate(sqlite3_column_int64(statement, 1)),
                    appBundleID: text(statement, 2),
                    windowName: text(statement, 3),
                    browserURL: text(statement, 4),
                    mainText: text(statement, 5) ?? "",
                    chromeText: text(statement, 6),
                    titleText: text(statement, 7)
                )
            )
        }
    }

    private static func text(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else {
            return nil
        }
        let string = String(cString: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return string.isEmpty ? nil : string
    }

    private static func ftsQuery(from rawQuery: String) -> String {
        let tokens = rawQuery
            .split { !$0.isLetter && !$0.isNumber && $0 != "_" && $0 != "-" }
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else {
            return "\"\(rawQuery.replacingOccurrences(of: "\"", with: "\"\""))\""
        }

        return tokens
            .map { token in
                "\"\(token.replacingOccurrences(of: "\"", with: "\"\""))\""
            }
            .joined(separator: " AND ")
    }
}
