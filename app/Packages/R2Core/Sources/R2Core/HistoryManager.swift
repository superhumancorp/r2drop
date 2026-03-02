// Packages/R2Core/Sources/R2Core/HistoryManager.swift
// Swift interface to the upload history database (history.db).
// Uses direct SQLite3 access for shared data between app targets.
// Schema matches r2-core/src/history.rs exactly.

import Foundation

// MARK: - HistoryManager

/// Manages the persistent upload history backed by SQLite.
/// Stores completed upload records with file info and R2 URLs.
public final class HistoryManager {
    private let db: SQLiteConnection

    /// Open (or create) the history database at the given path.
    public init(path: String) throws {
        db = try SQLiteConnection(path: path)
        try createTable()
    }

    /// Open the history database in the default config directory.
    public convenience init() throws {
        let dir = ConfigManager.configDir()
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        try self.init(path: dir.appendingPathComponent("history.db").path)
    }

    // MARK: - CRUD Operations

    /// Record a completed upload. Returns the auto-generated row ID.
    @discardableResult
    public func insertEntry(
        fileName: String,
        fileSize: UInt64,
        r2Key: String,
        bucket: String,
        accountName: String,
        url: String
    ) throws -> Int64 {
        try db.run(
            """
            INSERT INTO entries (file_name, file_size, r2_key, bucket, account_name, url)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6)
            """,
            params: [fileName, fileSize, r2Key, bucket, accountName, url]
        )
        return db.lastInsertRowId()
    }

    /// Fetch a single entry by ID. Returns nil if not found.
    public func getEntry(id: Int64) throws -> HistoryEntry? {
        let rows = try db.query(
            """
            SELECT id, file_name, file_size, r2_key, bucket, account_name, url, uploaded_at
            FROM entries WHERE id = ?1
            """,
            params: [id]
        )
        return rows.first.map { rowToEntry($0) }
    }

    /// List all history entries, most recent first.
    public func listEntries() throws -> [HistoryEntry] {
        let rows = try db.query(
            """
            SELECT id, file_name, file_size, r2_key, bucket, account_name, url, uploaded_at
            FROM entries ORDER BY id DESC
            """
        )
        return rows.map { rowToEntry($0) }
    }

    /// Search history by file name (case-insensitive substring match).
    public func search(query: String) throws -> [HistoryEntry] {
        let pattern = "%\(query)%"
        let rows = try db.query(
            """
            SELECT id, file_name, file_size, r2_key, bucket, account_name, url, uploaded_at
            FROM entries WHERE file_name LIKE ?1 ORDER BY id DESC
            """,
            params: [pattern]
        )
        return rows.map { rowToEntry($0) }
    }

    /// Delete a single entry by ID. Returns true if a row was deleted.
    @discardableResult
    public func deleteEntry(id: Int64) throws -> Bool {
        let changed = try db.run(
            "DELETE FROM entries WHERE id = ?1",
            params: [id]
        )
        return changed > 0
    }

    /// Clear all history entries. Returns the number of entries removed.
    @discardableResult
    public func clear() throws -> Int {
        return try db.run("DELETE FROM entries")
    }

    // MARK: - Private

    private func createTable() throws {
        try db.execute(
            """
            CREATE TABLE IF NOT EXISTS entries (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                file_name    TEXT    NOT NULL,
                file_size    INTEGER NOT NULL,
                r2_key       TEXT    NOT NULL,
                bucket       TEXT    NOT NULL,
                account_name TEXT    NOT NULL,
                url          TEXT    NOT NULL DEFAULT '',
                uploaded_at  TEXT    NOT NULL DEFAULT (datetime('now'))
            )
            """
        )
    }

    /// Map a raw SQLite row to a HistoryEntry model.
    private func rowToEntry(_ row: SQLiteConnection.Row) -> HistoryEntry {
        HistoryEntry(
            id: row[0] as? Int64 ?? 0,
            fileName: row[1] as? String ?? "",
            fileSize: UInt64(row[2] as? Int64 ?? 0),
            r2Key: row[3] as? String ?? "",
            bucket: row[4] as? String ?? "",
            accountName: row[5] as? String ?? "",
            url: row[6] as? String ?? "",
            uploadedAt: row[7] as? String ?? ""
        )
    }
}
