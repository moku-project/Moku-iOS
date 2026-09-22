import Foundation
import SQLite3
import SwiftUI

struct SearchHistoryItem: Identifiable, Equatable, Sendable {
    let id: String
    let query: String
}

extension EnvironmentValues {
    @Entry var searchHistoryStore: SearchHistoryStore? = nil
}

/// Local search history, available without starting the source runtime.
actor SearchHistoryStore {
    let url: URL
    init(url: URL) { self.url = url }

    func recent() throws -> [SearchHistoryItem] {
        try database { db in try read(db) }
    }

    func record(_ query: String) throws -> [SearchHistoryItem] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return try recent() }
        let key = query.folding(
            options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return try database { db in
            try execute(db, "BEGIN IMMEDIATE")
            do {
                try execute(
                    db,
                    """
                    INSERT INTO search_history (query_key, query, searched_at) VALUES (?, ?, ?)
                    ON CONFLICT(query_key) DO UPDATE SET query = excluded.query, searched_at = excluded.searched_at
                    """, values: [key, query, String(Date().timeIntervalSince1970)])
                try execute(
                    db,
                    """
                    DELETE FROM search_history WHERE query_key NOT IN
                    (SELECT query_key FROM search_history ORDER BY searched_at DESC, rowid DESC LIMIT 30)
                    """)
                try execute(db, "COMMIT")
            } catch {
                try? execute(db, "ROLLBACK")
                throw error
            }
            return try read(db)
        }
    }

    func remove(id: String? = nil) throws -> [SearchHistoryItem] {
        try database { db in
            if let id {
                try execute(db, "DELETE FROM search_history WHERE query_key = ?", values: [id])
            } else {
                try execute(db, "DELETE FROM search_history")
            }
            return try read(db)
        }
    }

    private func database<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        let status = sqlite3_open_v2(
            url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil)
        defer { if let handle { sqlite3_close(handle) } }
        guard status == SQLITE_OK, let handle else { throw failure() }
        sqlite3_busy_timeout(handle, 3000)
        try execute(handle, "PRAGMA journal_mode=WAL")
        try execute(
            handle,
            """
            CREATE TABLE IF NOT EXISTS search_history (
                query_key TEXT PRIMARY KEY NOT NULL,
                query TEXT NOT NULL,
                searched_at REAL NOT NULL
            )
            """)
        return try body(handle)
    }

    private func read(_ db: OpaquePointer) throws -> [SearchHistoryItem] {
        var rows: [SearchHistoryItem] = []
        try statement(
            db,
            "SELECT query_key, query FROM search_history ORDER BY searched_at DESC, rowid DESC LIMIT 30"
        ) { stmt in
            var result = sqlite3_step(stmt)
            while result == SQLITE_ROW {
                guard let id = sqlite3_column_text(stmt, 0),
                    let query = sqlite3_column_text(stmt, 1)
                else {
                    throw failure()
                }
                rows.append(
                    SearchHistoryItem(id: String(cString: id), query: String(cString: query)))
                result = sqlite3_step(stmt)
            }
            guard result == SQLITE_DONE else { throw failure() }
        }
        return rows
    }

    private func execute(_ db: OpaquePointer, _ sql: String, values: [String] = []) throws {
        try statement(db, sql, values: values) { stmt in
            var result = sqlite3_step(stmt)
            while result == SQLITE_ROW { result = sqlite3_step(stmt) }
            guard result == SQLITE_DONE else { throw failure() }
        }
    }

    private func statement(
        _ db: OpaquePointer, _ sql: String, values: [String] = [],
        body: (OpaquePointer) throws -> Void
    ) throws {
        var handle: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &handle, nil) == SQLITE_OK, let handle else {
            throw failure()
        }
        defer { sqlite3_finalize(handle) }
        for (index, value) in values.enumerated() {
            let status = value.withCString {
                sqlite3_bind_text(
                    handle, Int32(index + 1), $0, -1,
                    unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            guard status == SQLITE_OK else { throw failure() }
        }
        try body(handle)
    }

    private func failure() -> NSError {
        NSError(
            domain: "Moku.SearchHistory", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Couldn’t access search history. Try again."])
    }
}
