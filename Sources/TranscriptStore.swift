import Foundation
import SQLite3

// MARK: - TranscriptRecord

struct TranscriptRecord: Identifiable {
    let id: Int64
    let timestamp: Date
    let durationSeconds: Int
    let text: String
    let audioFilePath: String
}

// MARK: - TranscriptStore

final class TranscriptStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.autoclawd.transcriptstore", qos: .utility)

    init(url: URL) {
        let status = sqlite3_open(url.path, &db)
        if status != SQLITE_OK {
            Log.error(.system, "SQLite open failed: \(status)")
            return
        }
        createTables()
        Log.info(.system, "TranscriptStore opened at \(url.lastPathComponent)")
    }

    deinit { sqlite3_close(db) }

    // MARK: - Write

    func save(text: String, durationSeconds: Int, audioFilePath: String) {
        queue.async { [weak self] in
            self?.insertTranscript(text: text, duration: durationSeconds, path: audioFilePath)
        }
    }

    // MARK: - Read

    /// Full-text search using FTS5.
    func search(query: String, limit: Int = 50) -> [TranscriptRecord] {
        queue.sync { ftsSearch(query: query, limit: limit) }
    }

    /// Most recent N transcripts.
    func recent(limit: Int = 50) -> [TranscriptRecord] {
        queue.sync { fetchRecent(limit: limit) }
    }

    // MARK: - Schema

    private func createTables() {
        let transcripts = """
            CREATE TABLE IF NOT EXISTS transcripts (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp       TEXT NOT NULL,
                duration_seconds INTEGER NOT NULL DEFAULT 0,
                text            TEXT NOT NULL,
                audio_file_path TEXT NOT NULL DEFAULT ''
            );
        """
        let fts = """
            CREATE VIRTUAL TABLE IF NOT EXISTS transcripts_fts
            USING fts5(text, content='transcripts', content_rowid='id');
        """
        let trigger = """
            CREATE TRIGGER IF NOT EXISTS transcripts_ai
            AFTER INSERT ON transcripts BEGIN
                INSERT INTO transcripts_fts(rowid, text) VALUES (new.id, new.text);
            END;
        """
        execSQL(transcripts)
        execSQL(fts)
        execSQL(trigger)
    }

    // MARK: - SQL Helpers

    private func insertTranscript(text: String, duration: Int, path: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let sql = """
            INSERT INTO transcripts (timestamp, duration_seconds, text, audio_file_path)
            VALUES (?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, ts, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(duration))
        sqlite3_bind_text(stmt, 3, text, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, path, -1, SQLITE_TRANSIENT)
        let result = sqlite3_step(stmt)
        if result == SQLITE_DONE {
            Log.info(.system, "Transcript saved (\(text.split(separator: " ").count) words)")
        } else {
            Log.error(.system, "Transcript save failed: \(result)")
        }
    }

    private func ftsSearch(query: String, limit: Int) -> [TranscriptRecord] {
        let sql = """
            SELECT t.id, t.timestamp, t.duration_seconds, t.text, t.audio_file_path
            FROM transcripts t
            JOIN transcripts_fts f ON t.id = f.rowid
            WHERE transcripts_fts MATCH ?
            ORDER BY t.id DESC
            LIMIT ?;
        """
        return runQuery(sql, args: [query, String(limit)])
    }

    private func fetchRecent(limit: Int) -> [TranscriptRecord] {
        let sql = """
            SELECT id, timestamp, duration_seconds, text, audio_file_path
            FROM transcripts
            ORDER BY id DESC
            LIMIT ?;
        """
        return runQuery(sql, args: [String(limit)])
    }

    private func runQuery(_ sql: String, args: [String]) -> [TranscriptRecord] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        for (i, arg) in args.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), arg, -1, SQLITE_TRANSIENT)
        }
        var results: [TranscriptRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id   = sqlite3_column_int64(stmt, 0)
            let tsStr = String(cString: sqlite3_column_text(stmt, 1))
            let dur  = Int(sqlite3_column_int(stmt, 2))
            let text = String(cString: sqlite3_column_text(stmt, 3))
            let path = String(cString: sqlite3_column_text(stmt, 4))
            let ts   = ISO8601DateFormatter().date(from: tsStr) ?? Date()
            results.append(TranscriptRecord(id: id, timestamp: ts, durationSeconds: dur,
                                            text: text, audioFilePath: path))
        }
        return results
    }

    private func execSQL(_ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &err)
        if result != SQLITE_OK, let e = err {
            Log.error(.system, "SQLite exec error: \(String(cString: e))")
            sqlite3_free(err)
        }
    }
}

// Needed for sqlite3_bind_text with SQLITE_TRANSIENT
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
