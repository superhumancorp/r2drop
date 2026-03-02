// Packages/R2Core/Sources/R2Core/SQLiteConnection.swift
// Minimal SQLite3 C API wrapper for queue.db and history.db access.
// Both the main app and Finder extension use this for shared SQLite I/O
// via App Groups. Uses WAL mode for concurrent read/write access.

import Foundation
import SQLite3

// MARK: - Errors

/// Errors from SQLite operations.
public enum SQLiteError: LocalizedError {
    case open(String)
    case prepare(String)
    case execute(String)
    case step(String)

    public var errorDescription: String? {
        switch self {
        case .open(let msg): return "SQLite open: \(msg)"
        case .prepare(let msg): return "SQLite prepare: \(msg)"
        case .execute(let msg): return "SQLite execute: \(msg)"
        case .step(let msg): return "SQLite step: \(msg)"
        }
    }
}

// MARK: - SQLiteConnection

/// Thin wrapper around the SQLite3 C API.
/// Handles open/close, WAL mode, parameterized queries, and type-safe binding.
final class SQLiteConnection {
    private var db: OpaquePointer?

    // SQLITE_TRANSIENT tells SQLite to copy bound strings immediately.
    // Defined as a C macro: ((sqlite3_destructor_type)-1)
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Open a SQLite database at the given path. Creates if it doesn't exist.
    /// Enables WAL journal mode for concurrent access.
    init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK else {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            #if DEBUG
            print("[R2Core:SQLiteConnection] init error: \(msg)")
            #endif
            sqlite3_close(handle)
            throw SQLiteError.open(msg)
        }
        self.db = handle
        try execute("PRAGMA journal_mode = WAL")
    }

    deinit { sqlite3_close(db) }

    // MARK: - Execute (DDL, simple writes)

    /// Execute a SQL statement with no parameters or results.
    @discardableResult
    func execute(_ sql: String) throws -> Int32 {
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            #if DEBUG
            print("[R2Core:SQLiteConnection] execute error: \(msg)")
            #endif
            sqlite3_free(errMsg)
            throw SQLiteError.execute(msg)
        }
        return rc
    }

    // MARK: - Run (parameterized INSERT/UPDATE/DELETE)

    /// Execute a parameterized statement. Returns the number of changed rows.
    /// Params can be: String, Int64, Int, UInt64, or nil for NULL.
    @discardableResult
    func run(_ sql: String, params: [Any?] = []) throws -> Int {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, params: params)
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE else {
            let msg = errMsg()
            #if DEBUG
            print("[R2Core:SQLiteConnection] run error: \(msg)")
            #endif
            throw SQLiteError.step(msg)
        }
        return Int(sqlite3_changes(db))
    }

    /// The rowid of the most recent INSERT.
    func lastInsertRowId() -> Int64 {
        sqlite3_last_insert_rowid(db)
    }

    // MARK: - Query (parameterized SELECT)

    /// A single row from a query: array of column values.
    typealias Row = [Any?]

    /// Execute a parameterized query. Returns rows as arrays of column values.
    /// Column types: TEXT → String, INTEGER → Int64, NULL → nil.
    func query(_ sql: String, params: [Any?] = []) throws -> [Row] {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, params: params)

        var rows: [Row] = []
        let colCount = sqlite3_column_count(stmt)

        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: Row = []
            for i in 0..<colCount {
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER:
                    row.append(sqlite3_column_int64(stmt, i))
                case SQLITE_TEXT:
                    if let ptr = sqlite3_column_text(stmt, i) {
                        row.append(String(cString: ptr))
                    } else { row.append(nil) }
                default:
                    row.append(nil)
                }
            }
            rows.append(row)
        }
        return rows
    }

    // MARK: - Private Helpers

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.prepare(errMsg())
        }
        return stmt!
    }

    private func bind(_ stmt: OpaquePointer, params: [Any?]) throws {
        for (i, param) in params.enumerated() {
            let idx = Int32(i + 1)
            switch param {
            case let v as String:
                sqlite3_bind_text(stmt, idx, v, -1, Self.transient)
            case let v as Int64:
                sqlite3_bind_int64(stmt, idx, v)
            case let v as Int:
                sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as UInt64:
                sqlite3_bind_int64(stmt, idx, Int64(bitPattern: v))
            case nil:
                sqlite3_bind_null(stmt, idx)
            default:
                sqlite3_bind_null(stmt, idx)
            }
        }
    }

    private func errMsg() -> String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
    }
}
