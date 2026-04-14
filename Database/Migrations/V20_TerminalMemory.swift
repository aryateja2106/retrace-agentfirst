import Foundation
import SQLCipher
import Shared

/// V20 Migration: terminal task memory for shell/warp task tracking and frame correlation.
struct V20_TerminalMemory: Migration {
    let version = 20

    func migrate(db: OpaquePointer) async throws {
        Log.info("🧠 Verifying V20 terminal memory tables...", category: .database)

        let statements = [
            """
            CREATE TABLE IF NOT EXISTS terminal_task (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                bundleID TEXT NOT NULL,
                windowName TEXT,
                taskTitle TEXT,
                workingDirectory TEXT,
                shell TEXT,
                sessionKey TEXT NOT NULL,
                startDate INTEGER NOT NULL,
                endDate INTEGER,
                lastActivityAt INTEGER NOT NULL,
                source TEXT NOT NULL,
                confidence REAL NOT NULL DEFAULT 0.5,
                commandCount INTEGER NOT NULL DEFAULT 0,
                metadataJSON TEXT
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS terminal_event (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                taskId INTEGER NOT NULL,
                timestamp INTEGER NOT NULL,
                eventType TEXT NOT NULL,
                commandText TEXT,
                exitCode INTEGER,
                durationMs INTEGER,
                workingDirectory TEXT,
                metadataJSON TEXT,
                FOREIGN KEY(taskId) REFERENCES terminal_task(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS terminal_task_frame (
                frameId INTEGER NOT NULL,
                taskId INTEGER NOT NULL,
                PRIMARY KEY(frameId, taskId),
                FOREIGN KEY(frameId) REFERENCES frame(id) ON DELETE CASCADE,
                FOREIGN KEY(taskId) REFERENCES terminal_task(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_terminal_task_lookup
            ON terminal_task(bundleID, startDate, endDate, windowName, workingDirectory);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_terminal_task_session_key
            ON terminal_task(sessionKey, lastActivityAt DESC);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_terminal_event_task_timestamp
            ON terminal_event(taskId, timestamp);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_terminal_event_timestamp
            ON terminal_event(timestamp DESC, id DESC);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_terminal_task_frame_task
            ON terminal_task_frame(taskId, frameId);
            """
        ]

        try MigrationRunner.executeStatements(db: db, statements: statements)

        Log.info("✅ V20 migration completed: terminal memory schema verified", category: .database)
    }
}
