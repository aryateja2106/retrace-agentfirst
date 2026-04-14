import Foundation

/// Controls how `DatabaseManager` opens the on-disk SQLite file.
public enum DatabaseOpenMode: Sendable {
    /// Default: create parent directories, run migrations, and allow writes.
    case readWrite
    /// Opens an existing database read-only and skips migrations (CLI / tooling).
    case readOnlyExisting
}
