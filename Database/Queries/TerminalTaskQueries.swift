import Foundation
import SQLite3
import Shared

enum TerminalTaskQueries {
    static func upsert(db: OpaquePointer, session: TerminalTaskSession) throws -> TerminalTaskSession {
        if session.id.value > 0, let existing = try getByID(db: db, id: session.id) {
            try update(db: db, session: session, existing: existing)
            return try getByID(db: db, id: session.id) ?? session
        }

        if let existing = try findExisting(db: db, sessionKey: session.sessionKey, bundleID: session.bundleID) {
            let merged = TerminalTaskSession(
                id: existing.id,
                bundleID: session.bundleID,
                windowName: session.windowName ?? existing.windowName,
                taskTitle: session.taskTitle ?? existing.taskTitle,
                workingDirectory: session.workingDirectory ?? existing.workingDirectory,
                shell: session.shell ?? existing.shell,
                sessionKey: session.sessionKey,
                startDate: min(existing.startDate, session.startDate),
                endDate: session.endDate ?? existing.endDate,
                lastActivityAt: max(existing.lastActivityAt, session.lastActivityAt),
                source: session.source,
                confidence: session.confidence,
                commandCount: max(existing.commandCount, session.commandCount),
                metadataJSON: session.metadataJSON ?? existing.metadataJSON
            )
            try update(db: db, session: merged, existing: existing)
            return try getByID(db: db, id: existing.id) ?? merged
        }

        let sql = """
            INSERT INTO terminal_task (
                bundleID, windowName, taskTitle, workingDirectory, shell, sessionKey,
                startDate, endDate, lastActivityAt, source, confidence, commandCount, metadataJSON
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(query: sql, underlying: String(cString: sqlite3_errmsg(db)))
        }

        bindTextOrNull(statement, 1, session.bundleID)
        bindTextOrNull(statement, 2, session.windowName)
        bindTextOrNull(statement, 3, session.taskTitle)
        bindTextOrNull(statement, 4, session.workingDirectory)
        bindTextOrNull(statement, 5, session.shell)
        bindTextOrNull(statement, 6, session.sessionKey)
        sqlite3_bind_int64(statement, 7, Schema.dateToTimestamp(session.startDate))
        bindDateOrNull(statement, 8, session.endDate)
        sqlite3_bind_int64(statement, 9, Schema.dateToTimestamp(session.lastActivityAt))
        bindTextOrNull(statement, 10, session.source.rawValue)
        sqlite3_bind_double(statement, 11, session.confidence)
        sqlite3_bind_int(statement, 12, Int32(session.commandCount))
        bindTextOrNull(statement, 13, session.metadataJSON)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed(query: sql, underlying: String(cString: sqlite3_errmsg(db)))
        }

        let rowID = sqlite3_last_insert_rowid(db)
        return try getByID(db: db, id: TerminalTaskID(value: rowID)) ?? session
    }

    static func appendEvent(db: OpaquePointer, event: TerminalTaskEvent) throws -> Int64 {
        let sql = """
            INSERT INTO terminal_event (
                taskId, timestamp, eventType, commandText, exitCode, durationMs, workingDirectory, metadataJSON
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(query: sql, underlying: String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_int64(statement, 1, event.taskID.value)
        sqlite3_bind_int64(statement, 2, Schema.dateToTimestamp(event.timestamp))
        bindTextOrNull(statement, 3, event.eventType.rawValue)
        bindTextOrNull(statement, 4, event.commandText)
        bindIntOrNull(statement, 5, event.exitCode)
        bindIntOrNull(statement, 6, event.durationMs)
        bindTextOrNull(statement, 7, event.workingDirectory)
        bindTextOrNull(statement, 8, event.metadataJSON)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed(query: sql, underlying: String(cString: sqlite3_errmsg(db)))
        }

        let rowID = sqlite3_last_insert_rowid(db)

        let updateSQL = """
            UPDATE terminal_task
            SET lastActivityAt = MAX(lastActivityAt, ?),
                workingDirectory = COALESCE(?, workingDirectory),
                commandCount = commandCount + CASE WHEN ? = 'command_end' THEN 1 ELSE 0 END
            WHERE id = ?
            """
        var updateStatement: OpaquePointer?
        defer { sqlite3_finalize(updateStatement) }
        guard sqlite3_prepare_v2(db, updateSQL, -1, &updateStatement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(query: updateSQL, underlying: String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_int64(updateStatement, 1, Schema.dateToTimestamp(event.timestamp))
        bindTextOrNull(updateStatement, 2, event.workingDirectory)
        bindTextOrNull(updateStatement, 3, event.eventType.rawValue)
        sqlite3_bind_int64(updateStatement, 4, event.taskID.value)
        guard sqlite3_step(updateStatement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed(query: updateSQL, underlying: String(cString: sqlite3_errmsg(db)))
        }

        return rowID
    }

    static func close(db: OpaquePointer, id: TerminalTaskID, endDate: Date, commandCount: Int?) throws {
        let sql = """
            UPDATE terminal_task
            SET endDate = ?, lastActivityAt = ?, commandCount = COALESCE(?, commandCount)
            WHERE id = ?
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(query: sql, underlying: String(cString: sqlite3_errmsg(db)))
        }
        let endTimestamp = Schema.dateToTimestamp(endDate)
        sqlite3_bind_int64(statement, 1, endTimestamp)
        sqlite3_bind_int64(statement, 2, endTimestamp)
        if let commandCount {
            sqlite3_bind_int(statement, 3, Int32(commandCount))
        } else {
            sqlite3_bind_null(statement, 3)
        }
        sqlite3_bind_int64(statement, 4, id.value)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed(query: sql, underlying: String(cString: sqlite3_errmsg(db)))
        }
    }

    static func linkFrame(db: OpaquePointer, frameID: FrameID, taskID: TerminalTaskID) throws {
        let sql = """
            INSERT OR IGNORE INTO terminal_task_frame (frameId, taskId)
            VALUES (?, ?)
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(query: sql, underlying: String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_int64(statement, 1, frameID.value)
        sqlite3_bind_int64(statement, 2, taskID.value)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed(query: sql, underlying: String(cString: sqlite3_errmsg(db)))
        }
    }

    static func getByID(db: OpaquePointer, id: TerminalTaskID) throws -> TerminalTaskSession? {
        let sql = """
            SELECT id, bundleID, windowName, taskTitle, workingDirectory, shell, sessionKey,
                   startDate, endDate, lastActivityAt, source, confidence, commandCount, metadataJSON
            FROM terminal_task
            WHERE id = ?
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(query: sql, underlying: String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_int64(statement, 1, id.value)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return try parseSession(statement: statement!)
    }

    static func getByTimeRange(
        db: OpaquePointer,
        bundleID: String?,
        from startDate: Date,
        to endDate: Date,
        limit: Int
    ) throws -> [TerminalTaskSession] {
        var whereClauses = [
            "startDate <= ?",
            "COALESCE(endDate, lastActivityAt) >= ?"
        ]
        if bundleID != nil {
            whereClauses.append("bundleID = ?")
        }
        let sql = """
            SELECT id, bundleID, windowName, taskTitle, workingDirectory, shell, sessionKey,
                   startDate, endDate, lastActivityAt, source, confidence, commandCount, metadataJSON
            FROM terminal_task
            WHERE \(whereClauses.joined(separator: " AND "))
            ORDER BY lastActivityAt DESC
            LIMIT ?
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(query: sql, underlying: String(cString: sqlite3_errmsg(db)))
        }
        var bindIndex: Int32 = 1
        sqlite3_bind_int64(statement, bindIndex, Schema.dateToTimestamp(endDate)); bindIndex += 1
        sqlite3_bind_int64(statement, bindIndex, Schema.dateToTimestamp(startDate)); bindIndex += 1
        if let bundleID {
            bindTextOrNull(statement, bindIndex, bundleID)
            bindIndex += 1
        }
        sqlite3_bind_int(statement, bindIndex, Int32(limit))

        var results: [TerminalTaskSession] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            results.append(try parseSession(statement: statement!))
        }
        return results
    }

    static func getEvents(db: OpaquePointer, taskID: TerminalTaskID, limit: Int) throws -> [TerminalTaskEvent] {
        let sql = """
            SELECT id, taskId, timestamp, eventType, commandText, exitCode, durationMs, workingDirectory, metadataJSON
            FROM terminal_event
            WHERE taskId = ?
            ORDER BY timestamp DESC
            LIMIT ?
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(query: sql, underlying: String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_int64(statement, 1, taskID.value)
        sqlite3_bind_int(statement, 2, Int32(limit))

        var results: [TerminalTaskEvent] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            results.append(parseEvent(statement: statement!))
        }
        return results
    }

    static func getUsageForApp(
        db: OpaquePointer,
        bundleID: String,
        from startDate: Date,
        to endDate: Date,
        limit: Int?
    ) throws -> [TerminalTaskUsage] {
        var sql = """
            WITH linked_frames AS (
                SELECT
                    ttf.taskId,
                    f.createdAt AS frameTimestamp,
                    LAG(f.createdAt) OVER (
                        PARTITION BY ttf.taskId
                        ORDER BY f.createdAt
                    ) AS previousFrameTimestamp
                FROM terminal_task_frame ttf
                INNER JOIN frame f ON f.id = ttf.frameId
            ),
            frame_usage AS (
                SELECT
                    taskId,
                    COUNT(*) AS linkedFrameCount,
                    SUM(
                        CASE
                            WHEN previousFrameTimestamp IS NULL THEN 2000
                            WHEN frameTimestamp - previousFrameTimestamp > 5000 THEN 2000
                            WHEN frameTimestamp - previousFrameTimestamp < 500 THEN 500
                            ELSE frameTimestamp - previousFrameTimestamp
                        END
                    ) AS linkedDurationMs
                FROM linked_frames
                GROUP BY taskId
            ),
            command_usage AS (
                SELECT
                    taskId,
                    SUM(COALESCE(durationMs, 0)) AS commandDurationMs
                FROM terminal_event
                WHERE eventType = 'command_end'
                GROUP BY taskId
            )
            SELECT t.id, t.bundleID, t.windowName, t.taskTitle, t.workingDirectory, t.shell, t.sessionKey,
                   t.startDate, t.endDate, t.lastActivityAt, t.source, t.confidence, t.commandCount, t.metadataJSON,
                   COALESCE(fu.linkedFrameCount, 0) AS linkedFrameCount,
                   COALESCE(fu.linkedDurationMs, 0) AS linkedDurationMs,
                   COALESCE(cu.commandDurationMs, 0) AS commandDurationMs
            FROM terminal_task t
            LEFT JOIN frame_usage fu ON fu.taskId = t.id
            LEFT JOIN command_usage cu ON cu.taskId = t.id
            WHERE t.bundleID = ?
              AND t.startDate <= ?
              AND COALESCE(t.endDate, t.lastActivityAt) >= ?
            ORDER BY linkedDurationMs DESC, commandDurationMs DESC, t.lastActivityAt DESC
            """
        if limit != nil {
            sql += "\nLIMIT ?"
        }

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(query: sql, underlying: String(cString: sqlite3_errmsg(db)))
        }
        bindTextOrNull(statement, 1, bundleID)
        sqlite3_bind_int64(statement, 2, Schema.dateToTimestamp(endDate))
        sqlite3_bind_int64(statement, 3, Schema.dateToTimestamp(startDate))
        if let limit {
            sqlite3_bind_int(statement, 4, Int32(limit))
        }

        var results: [TerminalTaskUsage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let session = try parseSession(statement: statement!)
            let linkedFrameCount = Int(sqlite3_column_int(statement, 14))
            let linkedDurationSeconds = TimeInterval(sqlite3_column_int64(statement, 15)) / 1000
            let commandDurationSeconds = TimeInterval(sqlite3_column_int64(statement, 16)) / 1000
            let totalDuration: TimeInterval
            if linkedDurationSeconds > 0 {
                totalDuration = linkedDurationSeconds
            } else if commandDurationSeconds > 0 {
                totalDuration = commandDurationSeconds
            } else {
                totalDuration = session.duration
            }
            results.append(
                TerminalTaskUsage(
                    task: session,
                    linkedFrameCount: linkedFrameCount,
                    totalDuration: totalDuration
                )
            )
        }
        return results
    }

    static func search(
        db: OpaquePointer,
        query: String,
        bundleID: String?,
        from startDate: Date?,
        to endDate: Date?,
        limit: Int
    ) throws -> [TerminalTaskSearchResult] {
        let pattern = "%\(query)%"
        var whereClauses = [
            "(t.taskTitle LIKE ? OR t.workingDirectory LIKE ? OR t.windowName LIKE ? OR EXISTS (" +
            "SELECT 1 FROM terminal_event te2 WHERE te2.taskId = t.id AND te2.commandText LIKE ?" +
            "))"
        ]
        if bundleID != nil {
            whereClauses.append("t.bundleID = ?")
        }
        if endDate != nil {
            whereClauses.append("t.startDate <= ?")
        }
        if startDate != nil {
            whereClauses.append("COALESCE(t.endDate, t.lastActivityAt) >= ?")
        }

        let sql = """
            SELECT t.id, t.bundleID, t.windowName, t.taskTitle, t.workingDirectory, t.shell, t.sessionKey,
                   t.startDate, t.endDate, t.lastActivityAt, t.source, t.confidence, t.commandCount, t.metadataJSON,
                   (
                       SELECT te.commandText
                       FROM terminal_event te
                       WHERE te.taskId = t.id AND te.commandText LIKE ?
                       ORDER BY te.timestamp DESC
                       LIMIT 1
                   ) AS matchedCommandPreview
            FROM terminal_task t
            WHERE \(whereClauses.joined(separator: " AND "))
            ORDER BY t.lastActivityAt DESC
            LIMIT ?
            """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(query: sql, underlying: String(cString: sqlite3_errmsg(db)))
        }

        var bindIndex: Int32 = 1
        bindTextOrNull(statement, bindIndex, pattern); bindIndex += 1
        bindTextOrNull(statement, bindIndex, pattern); bindIndex += 1
        bindTextOrNull(statement, bindIndex, pattern); bindIndex += 1
        bindTextOrNull(statement, bindIndex, pattern); bindIndex += 1
        bindTextOrNull(statement, bindIndex, pattern); bindIndex += 1
        if let bundleID {
            bindTextOrNull(statement, bindIndex, bundleID)
            bindIndex += 1
        }
        if let endDate {
            sqlite3_bind_int64(statement, bindIndex, Schema.dateToTimestamp(endDate))
            bindIndex += 1
        }
        if let startDate {
            sqlite3_bind_int64(statement, bindIndex, Schema.dateToTimestamp(startDate))
            bindIndex += 1
        }
        sqlite3_bind_int(statement, bindIndex, Int32(limit))

        var results: [TerminalTaskSearchResult] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let session = try parseSession(statement: statement!)
            let matchedPreview = sqlite3_column_text(statement, 14).map { String(cString: $0) }
            results.append(TerminalTaskSearchResult(task: session, matchedCommandPreview: matchedPreview))
        }
        return results
    }

    static func deleteOlderThan(db: OpaquePointer, date: Date) throws -> Int {
        let sql = """
            DELETE FROM terminal_task
            WHERE COALESCE(endDate, lastActivityAt) < ?
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(query: sql, underlying: String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_int64(statement, 1, Schema.dateToTimestamp(date))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed(query: sql, underlying: String(cString: sqlite3_errmsg(db)))
        }
        return Int(sqlite3_changes(db))
    }

    static func taskForFrame(db: OpaquePointer, frameID: FrameID) throws -> TerminalTaskSession? {
        let sql = """
            SELECT t.id, t.bundleID, t.windowName, t.taskTitle, t.workingDirectory, t.shell, t.sessionKey,
                   t.startDate, t.endDate, t.lastActivityAt, t.source, t.confidence, t.commandCount, t.metadataJSON
            FROM terminal_task_frame tf
            INNER JOIN terminal_task t ON t.id = tf.taskId
            WHERE tf.frameId = ?
            ORDER BY t.lastActivityAt DESC
            LIMIT 1
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(query: sql, underlying: String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_int64(statement, 1, frameID.value)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return try parseSession(statement: statement!)
    }

    private static func findExisting(db: OpaquePointer, sessionKey: String, bundleID: String) throws -> TerminalTaskSession? {
        let sql = """
            SELECT id, bundleID, windowName, taskTitle, workingDirectory, shell, sessionKey,
                   startDate, endDate, lastActivityAt, source, confidence, commandCount, metadataJSON
            FROM terminal_task
            WHERE sessionKey = ? AND bundleID = ?
            ORDER BY lastActivityAt DESC
            LIMIT 1
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(query: sql, underlying: String(cString: sqlite3_errmsg(db)))
        }
        bindTextOrNull(statement, 1, sessionKey)
        bindTextOrNull(statement, 2, bundleID)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return try parseSession(statement: statement!)
    }

    private static func update(db: OpaquePointer, session: TerminalTaskSession, existing: TerminalTaskSession) throws {
        let sql = """
            UPDATE terminal_task
            SET bundleID = ?, windowName = ?, taskTitle = ?, workingDirectory = ?, shell = ?, sessionKey = ?,
                startDate = ?, endDate = ?, lastActivityAt = ?, source = ?, confidence = ?, commandCount = ?, metadataJSON = ?
            WHERE id = ?
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(query: sql, underlying: String(cString: sqlite3_errmsg(db)))
        }

        bindTextOrNull(statement, 1, session.bundleID)
        bindTextOrNull(statement, 2, session.windowName ?? existing.windowName)
        bindTextOrNull(statement, 3, session.taskTitle ?? existing.taskTitle)
        bindTextOrNull(statement, 4, session.workingDirectory ?? existing.workingDirectory)
        bindTextOrNull(statement, 5, session.shell ?? existing.shell)
        bindTextOrNull(statement, 6, session.sessionKey)
        sqlite3_bind_int64(statement, 7, Schema.dateToTimestamp(session.startDate))
        bindDateOrNull(statement, 8, session.endDate ?? existing.endDate)
        sqlite3_bind_int64(statement, 9, Schema.dateToTimestamp(session.lastActivityAt))
        bindTextOrNull(statement, 10, session.source.rawValue)
        sqlite3_bind_double(statement, 11, session.confidence)
        sqlite3_bind_int(statement, 12, Int32(session.commandCount))
        bindTextOrNull(statement, 13, session.metadataJSON ?? existing.metadataJSON)
        sqlite3_bind_int64(statement, 14, existing.id.value)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed(query: sql, underlying: String(cString: sqlite3_errmsg(db)))
        }
    }

    private static func parseSession(statement: OpaquePointer) throws -> TerminalTaskSession {
        let id = TerminalTaskID(value: sqlite3_column_int64(statement, 0))
        guard let bundleIDText = sqlite3_column_text(statement, 1) else {
            throw DatabaseError.queryFailed(query: "terminal_task", underlying: "Missing bundleID")
        }
        let bundleID = String(cString: bundleIDText)
        let windowName = sqlite3_column_text(statement, 2).map { String(cString: $0) }
        let taskTitle = sqlite3_column_text(statement, 3).map { String(cString: $0) }
        let workingDirectory = sqlite3_column_text(statement, 4).map { String(cString: $0) }
        let shell = sqlite3_column_text(statement, 5).map { String(cString: $0) }
        let sessionKey = sqlite3_column_text(statement, 6).map { String(cString: $0) } ?? ""
        let startDate = Schema.timestampToDate(sqlite3_column_int64(statement, 7))
        let endDate = sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : Schema.timestampToDate(sqlite3_column_int64(statement, 8))
        let lastActivityAt = Schema.timestampToDate(sqlite3_column_int64(statement, 9))
        let sourceRawValue = sqlite3_column_text(statement, 10).map { String(cString: $0) } ?? TerminalTaskSource.shellHook.rawValue
        let source = TerminalTaskSource(rawValue: sourceRawValue) ?? .shellHook
        let confidence = sqlite3_column_double(statement, 11)
        let commandCount = Int(sqlite3_column_int(statement, 12))
        let metadataJSON = sqlite3_column_text(statement, 13).map { String(cString: $0) }

        return TerminalTaskSession(
            id: id,
            bundleID: bundleID,
            windowName: windowName,
            taskTitle: taskTitle,
            workingDirectory: workingDirectory,
            shell: shell,
            sessionKey: sessionKey,
            startDate: startDate,
            endDate: endDate,
            lastActivityAt: lastActivityAt,
            source: source,
            confidence: confidence,
            commandCount: commandCount,
            metadataJSON: metadataJSON
        )
    }

    private static func parseEvent(statement: OpaquePointer) -> TerminalTaskEvent {
        let id = sqlite3_column_int64(statement, 0)
        let taskID = TerminalTaskID(value: sqlite3_column_int64(statement, 1))
        let timestamp = Schema.timestampToDate(sqlite3_column_int64(statement, 2))
        let eventTypeRawValue = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? TerminalTaskEventType.prompt.rawValue
        let eventType = TerminalTaskEventType(rawValue: eventTypeRawValue) ?? .prompt
        let commandText = sqlite3_column_text(statement, 4).map { String(cString: $0) }
        let exitCode = sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 5))
        let durationMs = sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 6))
        let workingDirectory = sqlite3_column_text(statement, 7).map { String(cString: $0) }
        let metadataJSON = sqlite3_column_text(statement, 8).map { String(cString: $0) }

        return TerminalTaskEvent(
            id: id,
            taskID: taskID,
            timestamp: timestamp,
            eventType: eventType,
            commandText: commandText,
            exitCode: exitCode,
            durationMs: durationMs,
            workingDirectory: workingDirectory,
            metadataJSON: metadataJSON
        )
    }

    private static func bindTextOrNull(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        guard let statement else { return }
        if let value {
            sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private static func bindDateOrNull(_ statement: OpaquePointer?, _ index: Int32, _ value: Date?) {
        if let value {
            sqlite3_bind_int64(statement, index, Schema.dateToTimestamp(value))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private static func bindIntOrNull(_ statement: OpaquePointer?, _ index: Int32, _ value: Int?) {
        if let value {
            sqlite3_bind_int(statement, index, Int32(value))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }
}
