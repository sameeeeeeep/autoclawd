import Foundation
import SQLite3

// MARK: - ExtractionStore

final class ExtractionStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.autoclawd.extractionstore", qos: .utility)

    init(url: URL) {
        let status = sqlite3_open(url.path, &db)
        if status != SQLITE_OK {
            Log.error(.system, "ExtractionStore SQLite open failed: \(status)")
            return
        }
        createTable()
        enableWAL()
        Log.info(.system, "ExtractionStore opened at \(url.lastPathComponent)")
    }

    deinit { sqlite3_close(db) }

    // MARK: - Write

    func insert(_ item: ExtractionItem) {
        queue.async { [weak self] in
            self?.insertItem(item)
        }
    }

    func setUserOverride(id: String, override: String?) {
        queue.async { [weak self] in
            self?.updateUserOverride(id: id, override: override)
        }
    }

    func setBucket(id: String, bucket: ExtractionBucket) {
        queue.async { [weak self] in
            self?.updateBucket(id: id, bucket: bucket)
        }
    }

    func markApplied(ids: [String]) {
        queue.async { [weak self] in
            self?.updateApplied(ids: ids)
        }
    }

    // MARK: - Read

    func all(chunkIndex: Int? = nil) -> [ExtractionItem] {
        queue.sync { fetchAll(chunkIndex: chunkIndex) }
    }

    func pendingAccepted() -> [ExtractionItem] {
        queue.sync { fetchPendingAccepted() }
    }

    // MARK: - Schema

    private func createTable() {
        let sql = """
            CREATE TABLE IF NOT EXISTS extraction_items (
                id            TEXT PRIMARY KEY,
                chunk_index   INTEGER NOT NULL,
                timestamp     REAL NOT NULL,
                source_phrase TEXT NOT NULL,
                content       TEXT NOT NULL,
                type          TEXT NOT NULL,
                bucket        TEXT NOT NULL DEFAULT 'other',
                priority      TEXT,
                model_decision TEXT NOT NULL,
                user_override TEXT,
                applied       INTEGER NOT NULL DEFAULT 0,
                created_at    REAL NOT NULL
            );
        """
        execSQL(sql)
    }

    private func enableWAL() {
        execSQL("PRAGMA journal_mode=WAL;")
    }

    // MARK: - SQL Helpers

    private func insertItem(_ item: ExtractionItem) {
        let sql = """
            INSERT OR IGNORE INTO extraction_items
                (id, chunk_index, timestamp, source_phrase, content, type, bucket,
                 priority, model_decision, user_override, applied, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, item.id, -1, SQLITE_TRANSIENT_ES)
        sqlite3_bind_int(stmt, 2, Int32(item.chunkIndex))
        sqlite3_bind_double(stmt, 3, item.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 4, item.sourcePhrase, -1, SQLITE_TRANSIENT_ES)
        sqlite3_bind_text(stmt, 5, item.content, -1, SQLITE_TRANSIENT_ES)
        sqlite3_bind_text(stmt, 6, item.type.rawValue, -1, SQLITE_TRANSIENT_ES)
        sqlite3_bind_text(stmt, 7, item.bucket.rawValue, -1, SQLITE_TRANSIENT_ES)

        if let priority = item.priority {
            sqlite3_bind_text(stmt, 8, priority, -1, SQLITE_TRANSIENT_ES)
        } else {
            sqlite3_bind_null(stmt, 8)
        }

        sqlite3_bind_text(stmt, 9, item.modelDecision, -1, SQLITE_TRANSIENT_ES)

        if let userOverride = item.userOverride {
            sqlite3_bind_text(stmt, 10, userOverride, -1, SQLITE_TRANSIENT_ES)
        } else {
            sqlite3_bind_null(stmt, 10)
        }

        sqlite3_bind_int(stmt, 11, item.applied ? 1 : 0)
        // Use current time as created_at since ExtractionItem has no createdAt field
        sqlite3_bind_double(stmt, 12, Date().timeIntervalSince1970)

        let result = sqlite3_step(stmt)
        if result != SQLITE_DONE {
            Log.error(.system, "ExtractionStore insert failed: \(result)")
        }
    }

    private func updateUserOverride(id: String, override: String?) {
        let sql = "UPDATE extraction_items SET user_override = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        if let override = override {
            sqlite3_bind_text(stmt, 1, override, -1, SQLITE_TRANSIENT_ES)
        } else {
            sqlite3_bind_null(stmt, 1)
        }
        sqlite3_bind_text(stmt, 2, id, -1, SQLITE_TRANSIENT_ES)

        let result = sqlite3_step(stmt)
        if result != SQLITE_DONE {
            Log.error(.system, "ExtractionStore setUserOverride failed: \(result)")
        }
    }

    private func updateBucket(id: String, bucket: ExtractionBucket) {
        let sql = "UPDATE extraction_items SET bucket = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, bucket.rawValue, -1, SQLITE_TRANSIENT_ES)
        sqlite3_bind_text(stmt, 2, id, -1, SQLITE_TRANSIENT_ES)

        let result = sqlite3_step(stmt)
        if result != SQLITE_DONE {
            Log.error(.system, "ExtractionStore setBucket failed: \(result)")
        }
    }

    private func updateApplied(ids: [String]) {
        let sql = "UPDATE extraction_items SET applied = 1 WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        for id in ids {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT_ES)
            let result = sqlite3_step(stmt)
            if result != SQLITE_DONE {
                Log.error(.system, "ExtractionStore markApplied failed for id \(id): \(result)")
            }
            sqlite3_reset(stmt)
        }
    }

    private func fetchAll(chunkIndex: Int?) -> [ExtractionItem] {
        let sql: String
        if chunkIndex != nil {
            sql = """
                SELECT id, chunk_index, timestamp, source_phrase, content, type, bucket,
                       priority, model_decision, user_override, applied, created_at
                FROM extraction_items
                WHERE chunk_index = ?
                ORDER BY created_at DESC;
            """
        } else {
            sql = """
                SELECT id, chunk_index, timestamp, source_phrase, content, type, bucket,
                       priority, model_decision, user_override, applied, created_at
                FROM extraction_items
                ORDER BY created_at DESC;
            """
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        if let chunkIndex = chunkIndex {
            sqlite3_bind_int(stmt, 1, Int32(chunkIndex))
        }

        return collectRows(stmt: stmt)
    }

    private func fetchPendingAccepted() -> [ExtractionItem] {
        let sql = """
            SELECT id, chunk_index, timestamp, source_phrase, content, type, bucket,
                   priority, model_decision, user_override, applied, created_at
            FROM extraction_items
            WHERE applied = 0
              AND (user_override = 'accepted'
                   OR (user_override IS NULL AND model_decision = 'relevant'))
            ORDER BY created_at DESC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        return collectRows(stmt: stmt)
    }

    private func collectRows(stmt: OpaquePointer?) -> [ExtractionItem] {
        var results: [ExtractionItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id            = String(cString: sqlite3_column_text(stmt, 0))
            let chunkIndex    = Int(sqlite3_column_int(stmt, 1))
            let timestampEpoch = sqlite3_column_double(stmt, 2)
            let sourcePhrase  = String(cString: sqlite3_column_text(stmt, 3))
            let content       = String(cString: sqlite3_column_text(stmt, 4))
            let typeRaw       = String(cString: sqlite3_column_text(stmt, 5))
            let bucketRaw     = String(cString: sqlite3_column_text(stmt, 6))

            let priority: String?
            if sqlite3_column_type(stmt, 7) == SQLITE_NULL {
                priority = nil
            } else {
                priority = String(cString: sqlite3_column_text(stmt, 7))
            }

            let modelDecision = String(cString: sqlite3_column_text(stmt, 8))

            let userOverride: String?
            if sqlite3_column_type(stmt, 9) == SQLITE_NULL {
                userOverride = nil
            } else {
                userOverride = String(cString: sqlite3_column_text(stmt, 9))
            }

            let applied = sqlite3_column_int(stmt, 10) != 0
            // column 11 is created_at — not part of ExtractionItem, used for ordering only

            let timestamp = Date(timeIntervalSince1970: timestampEpoch)
            let type      = ExtractionType(rawValue: typeRaw) ?? .fact
            let bucket    = ExtractionBucket.parse(bucketRaw)

            let item = ExtractionItem(
                id: id,
                chunkIndex: chunkIndex,
                timestamp: timestamp,
                sourcePhrase: sourcePhrase,
                content: content,
                type: type,
                bucket: bucket,
                priority: priority,
                modelDecision: modelDecision,
                userOverride: userOverride,
                applied: applied
            )
            results.append(item)
        }
        return results
    }

    private func execSQL(_ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &err)
        if result != SQLITE_OK, let e = err {
            Log.error(.system, "ExtractionStore exec error: \(String(cString: e))")
            sqlite3_free(err)
        }
    }
}

// Needed for sqlite3_bind_text with SQLITE_TRANSIENT
private let SQLITE_TRANSIENT_ES = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
