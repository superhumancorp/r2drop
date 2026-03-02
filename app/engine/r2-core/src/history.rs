// r2-core/src/history.rs — Upload history backed by SQLite
// Stores completed upload records in ~/.r2drop/history.db.
// Uses WAL mode for concurrent access (same pattern as queue.db).

use rusqlite::{params, Connection, OptionalExtension};
use std::path::Path;
use thiserror::Error;

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

#[derive(Debug, Error)]
pub enum HistoryError {
    #[error("database error: {0}")]
    Db(#[from] rusqlite::Error),
}

// ---------------------------------------------------------------------------
// HistoryEntry — one row in the history table
// ---------------------------------------------------------------------------

/// A completed upload record.
#[derive(Debug, Clone)]
pub struct HistoryEntry {
    pub id: i64,
    pub file_name: String,
    pub file_size: u64,
    pub r2_key: String,
    pub bucket: String,
    pub account_name: String,
    /// Public URL (uses custom domain if configured, otherwise R2 URL).
    pub url: String,
    pub uploaded_at: String,
}

// ---------------------------------------------------------------------------
// HistoryDb — wrapper around a SQLite connection
// ---------------------------------------------------------------------------

/// Persistent upload history backed by SQLite.
/// Stored in a separate database (`history.db`) from the queue.
pub struct HistoryDb {
    conn: Connection,
}

impl HistoryDb {
    /// Open (or create) the history database at the given path.
    /// Enables WAL mode and creates the entries table if it doesn't exist.
    pub fn open(path: &Path) -> Result<Self, HistoryError> {
        let conn = Connection::open(path)?;
        conn.pragma_update(None, "journal_mode", "wal")?;
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS entries (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                file_name    TEXT    NOT NULL,
                file_size    INTEGER NOT NULL,
                r2_key       TEXT    NOT NULL,
                bucket       TEXT    NOT NULL,
                account_name TEXT    NOT NULL,
                url          TEXT    NOT NULL DEFAULT '',
                uploaded_at  TEXT    NOT NULL DEFAULT (datetime('now'))
            );",
        )?;
        Ok(Self { conn })
    }

    /// Open the default history database at `~/.r2drop/history.db`.
    pub fn open_default() -> Result<Self, HistoryError> {
        let dir = crate::config::config_dir()
            .map_err(|e| HistoryError::Db(rusqlite::Error::InvalidParameterName(e.to_string())))?;
        Self::open(&dir.join("history.db"))
    }

    /// Record a completed upload. Returns the auto-generated row ID.
    pub fn insert_entry(
        &self,
        file_name: &str,
        file_size: u64,
        r2_key: &str,
        bucket: &str,
        account_name: &str,
        url: &str,
    ) -> Result<i64, HistoryError> {
        self.conn.execute(
            "INSERT INTO entries (file_name, file_size, r2_key, bucket, account_name, url)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![file_name, file_size as i64, r2_key, bucket, account_name, url],
        )?;
        Ok(self.conn.last_insert_rowid())
    }

    /// Fetch a single entry by ID. Returns `None` if not found.
    pub fn get_entry(&self, id: i64) -> Result<Option<HistoryEntry>, HistoryError> {
        let mut stmt = self.conn.prepare(
            "SELECT id, file_name, file_size, r2_key, bucket, account_name, url, uploaded_at
             FROM entries WHERE id = ?1",
        )?;
        stmt.query_row(params![id], row_to_entry)
            .optional()
            .map_err(Into::into)
    }

    /// List all history entries, most recent first.
    pub fn list_entries(&self) -> Result<Vec<HistoryEntry>, HistoryError> {
        let mut stmt = self.conn.prepare(
            "SELECT id, file_name, file_size, r2_key, bucket, account_name, url, uploaded_at
             FROM entries ORDER BY id DESC",
        )?;
        let rows = stmt.query_map([], row_to_entry)?;
        rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
    }

    /// Search history by file name (case-insensitive substring match).
    pub fn search(&self, query: &str) -> Result<Vec<HistoryEntry>, HistoryError> {
        let pattern = format!("%{query}%");
        let mut stmt = self.conn.prepare(
            "SELECT id, file_name, file_size, r2_key, bucket, account_name, url, uploaded_at
             FROM entries WHERE file_name LIKE ?1 ORDER BY id DESC",
        )?;
        let rows = stmt.query_map(params![pattern], row_to_entry)?;
        rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
    }

    /// Delete a single entry by ID. Returns true if a row was deleted.
    pub fn delete_entry(&self, id: i64) -> Result<bool, HistoryError> {
        let changed = self
            .conn
            .execute("DELETE FROM entries WHERE id = ?1", params![id])?;
        Ok(changed > 0)
    }

    /// Clear all history entries.
    pub fn clear(&self) -> Result<usize, HistoryError> {
        let changed = self.conn.execute("DELETE FROM entries", [])?;
        Ok(changed)
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Map a SQLite row to a HistoryEntry struct.
fn row_to_entry(row: &rusqlite::Row) -> rusqlite::Result<HistoryEntry> {
    let file_size: i64 = row.get(2)?;
    Ok(HistoryEntry {
        id: row.get(0)?,
        file_name: row.get(1)?,
        file_size: file_size as u64,
        r2_key: row.get(3)?,
        bucket: row.get(4)?,
        account_name: row.get(5)?,
        url: row.get(6)?,
        uploaded_at: row.get(7)?,
    })
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn test_db() -> HistoryDb {
        HistoryDb::open(Path::new(":memory:")).unwrap()
    }

    #[test]
    fn insert_and_get_entry() {
        let db = test_db();
        let id = db
            .insert_entry("photo.jpg", 2048, "imgs/photo.jpg", "my-bucket", "acct1", "https://cdn.example.com/imgs/photo.jpg")
            .unwrap();
        let entry = db.get_entry(id).unwrap().unwrap();
        assert_eq!(entry.file_name, "photo.jpg");
        assert_eq!(entry.file_size, 2048);
        assert_eq!(entry.r2_key, "imgs/photo.jpg");
        assert_eq!(entry.bucket, "my-bucket");
        assert_eq!(entry.account_name, "acct1");
        assert_eq!(entry.url, "https://cdn.example.com/imgs/photo.jpg");
    }

    #[test]
    fn get_nonexistent_returns_none() {
        let db = test_db();
        assert!(db.get_entry(999).unwrap().is_none());
    }

    #[test]
    fn list_entries_most_recent_first() {
        let db = test_db();
        db.insert_entry("a.txt", 100, "a.txt", "b", "acct", "").unwrap();
        db.insert_entry("b.txt", 200, "b.txt", "b", "acct", "").unwrap();
        db.insert_entry("c.txt", 300, "c.txt", "b", "acct", "").unwrap();
        let entries = db.list_entries().unwrap();
        assert_eq!(entries.len(), 3);
        // Most recent (highest ID) first
        assert_eq!(entries[0].file_name, "c.txt");
        assert_eq!(entries[2].file_name, "a.txt");
    }

    #[test]
    fn search_by_file_name() {
        let db = test_db();
        db.insert_entry("photo.jpg", 100, "k", "b", "a", "").unwrap();
        db.insert_entry("document.pdf", 200, "k", "b", "a", "").unwrap();
        db.insert_entry("photo_backup.jpg", 300, "k", "b", "a", "").unwrap();

        let results = db.search("photo").unwrap();
        assert_eq!(results.len(), 2);

        let results = db.search("pdf").unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].file_name, "document.pdf");

        let results = db.search("nonexistent").unwrap();
        assert!(results.is_empty());
    }

    #[test]
    fn delete_entry() {
        let db = test_db();
        let id = db.insert_entry("f.txt", 100, "k", "b", "a", "").unwrap();
        assert!(db.delete_entry(id).unwrap());
        assert!(db.get_entry(id).unwrap().is_none());
        assert!(!db.delete_entry(id).unwrap());
    }

    #[test]
    fn clear_removes_all() {
        let db = test_db();
        db.insert_entry("a.txt", 100, "k", "b", "a", "").unwrap();
        db.insert_entry("b.txt", 200, "k", "b", "a", "").unwrap();
        let removed = db.clear().unwrap();
        assert_eq!(removed, 2);
        assert!(db.list_entries().unwrap().is_empty());
    }

    #[test]
    fn wal_mode_enabled() {
        // WAL doesn't work with :memory: databases, so use a temp file.
        let tmp = tempfile::tempdir().unwrap();
        let db = HistoryDb::open(&tmp.path().join("test.db")).unwrap();
        let mode: String = db
            .conn
            .pragma_query_value(None, "journal_mode", |row| row.get(0))
            .unwrap();
        assert_eq!(mode, "wal");
    }
}
