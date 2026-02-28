import Foundation
import SQLite3

// MARK: - TranscriptRecord

struct TranscriptRecord: Identifiable {
    let id: Int64
    let timestamp: Date
    let durationSeconds: Int
    let text: String
    let audioFilePath: String
    let sessionID: String?     // nil for legacy rows
    let sessionChunkSeq: Int   // 0=A, 1=B, 2=C… (0 for legacy rows)
    var projectID: UUID?
    var speakerName: String?    // nil if speaker not tagged
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

    func save(text: String, durationSeconds: Int, audioFilePath: String,
              sessionID: String? = nil, sessionChunkSeq: Int = 0,
              projectID: UUID? = nil, timestamp: Date? = nil,
              speakerName: String? = nil) {
        queue.async { [weak self] in
            self?.insertTranscript(text: text, duration: durationSeconds, path: audioFilePath,
                                   sessionID: sessionID, sessionChunkSeq: sessionChunkSeq,
                                   projectID: projectID, timestamp: timestamp,
                                   speakerName: speakerName)
        }
    }

    /// Synchronous save that returns the new transcript's row ID.
    func saveSync(text: String, durationSeconds: Int, audioFilePath: String,
                  sessionID: String? = nil, sessionChunkSeq: Int = 0,
                  projectID: UUID? = nil, timestamp: Date? = nil,
                  speakerName: String? = nil) -> Int64? {
        queue.sync {
            insertTranscript(text: text, duration: durationSeconds, path: audioFilePath,
                             sessionID: sessionID, sessionChunkSeq: sessionChunkSeq,
                             projectID: projectID, timestamp: timestamp,
                             speakerName: speakerName)
            guard let db else { return nil }
            return sqlite3_last_insert_rowid(db)
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

    /// All chunks for a session, ordered by sequence ascending.
    func fetchBySession(sessionID: String) -> [TranscriptRecord] {
        queue.sync { fetchBySessionInternal(sessionID: sessionID) }
    }

    /// Merge all chunks for a session into a single transcript row, then delete the originals.
    func mergeSessionChunks(sessionID: String) {
        queue.sync {
            let chunks = fetchBySessionInternal(sessionID: sessionID)
            guard chunks.count > 1 else { return }
            let mergedText = chunks.map(\.text).joined(separator: " ")
            let totalDuration = chunks.map(\.durationSeconds).reduce(0, +)
            let earliest = chunks.map(\.timestamp).min() ?? Date()
            let projectID = chunks.first?.projectID
            for chunk in chunks { deleteInternal(id: chunk.id) }
            insertTranscript(text: mergedText, duration: totalDuration, path: "",
                             sessionID: sessionID, sessionChunkSeq: 0,
                             projectID: projectID, timestamp: earliest)
            Log.info(.system, "Merged \(chunks.count) transcript chunks for session \(sessionID)")
        }
    }

    func delete(id: Int64) {
        queue.async { [weak self] in self?.deleteInternal(id: id) }
    }

    func setProject(_ projectID: UUID?, for transcriptID: Int64) {
        queue.async { [weak self] in self?.setProjectInternal(projectID, for: transcriptID) }
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
        // Safe migrations — "duplicate column" errors are silently swallowed by execSQL
        execSQL("ALTER TABLE transcripts ADD COLUMN session_id TEXT;")
        execSQL("ALTER TABLE transcripts ADD COLUMN session_chunk_seq INTEGER NOT NULL DEFAULT 0;")
        execSQL("ALTER TABLE transcripts ADD COLUMN project_id TEXT;")
        execSQL("ALTER TABLE transcripts ADD COLUMN speaker_name TEXT;")
    }

    // MARK: - SQL Helpers

    private func insertTranscript(text: String, duration: Int, path: String,
                                  sessionID: String?, sessionChunkSeq: Int,
                                  projectID: UUID?, timestamp: Date?,
                                  speakerName: String? = nil) {
        let ts = ISO8601DateFormatter().string(from: timestamp ?? Date())
        let sql = """
            INSERT INTO transcripts
                (timestamp, duration_seconds, text, audio_file_path, session_id, session_chunk_seq, project_id, speaker_name)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, ts, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(duration))
        sqlite3_bind_text(stmt, 3, text, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, path, -1, SQLITE_TRANSIENT)
        if let sid = sessionID {
            sqlite3_bind_text(stmt, 5, sid, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        sqlite3_bind_int(stmt, 6, Int32(sessionChunkSeq))
        if let pid = projectID {
            sqlite3_bind_text(stmt, 7, pid.uuidString, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 7)
        }
        if let sname = speakerName {
            sqlite3_bind_text(stmt, 8, sname, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 8)
        }
        let result = sqlite3_step(stmt)
        if result == SQLITE_DONE {
            let label = String(UnicodeScalar(UInt32(65 + min(sessionChunkSeq, 25)))!)
            Log.info(.system, "Transcript saved [sess:\(label)] (\(text.split(separator: " ").count) words)")
        } else {
            Log.error(.system, "Transcript save failed: \(result)")
        }
    }

    private func ftsSearch(query: String, limit: Int) -> [TranscriptRecord] {
        let sql = """
            SELECT t.id, t.timestamp, t.duration_seconds, t.text, t.audio_file_path,
                   t.session_id, t.session_chunk_seq, t.project_id, t.speaker_name
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
            SELECT id, timestamp, duration_seconds, text, audio_file_path,
                   session_id, session_chunk_seq, project_id, speaker_name
            FROM transcripts
            ORDER BY id DESC
            LIMIT ?;
        """
        return runQuery(sql, args: [String(limit)])
    }

    private func fetchBySessionInternal(sessionID: String) -> [TranscriptRecord] {
        let sql = """
            SELECT id, timestamp, duration_seconds, text, audio_file_path,
                   session_id, session_chunk_seq, project_id, speaker_name
            FROM transcripts
            WHERE session_id = ?
            ORDER BY session_chunk_seq ASC;
        """
        return runQuery(sql, args: [sessionID])
    }

    private func deleteInternal(id: Int64) {
        let sql = "DELETE FROM transcripts WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        sqlite3_step(stmt)
    }

    private func setProjectInternal(_ projectID: UUID?, for transcriptID: Int64) {
        let sql = "UPDATE transcripts SET project_id = ? WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        if let pid = projectID {
            sqlite3_bind_text(stmt, 1, pid.uuidString, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 1)
        }
        sqlite3_bind_int64(stmt, 2, transcriptID)
        sqlite3_step(stmt)
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
            let id    = sqlite3_column_int64(stmt, 0)
            let tsStr = String(cString: sqlite3_column_text(stmt, 1))
            let dur   = Int(sqlite3_column_int(stmt, 2))
            let text  = String(cString: sqlite3_column_text(stmt, 3))
            let path  = String(cString: sqlite3_column_text(stmt, 4))
            let sid   = sqlite3_column_type(stmt, 5) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(stmt, 5))
                : nil
            let seq   = Int(sqlite3_column_int(stmt, 6))
            let pidStr = sqlite3_column_type(stmt, 7) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(stmt, 7))
                : nil
            let pid   = pidStr.flatMap { UUID(uuidString: $0) }
            let speakerName = sqlite3_column_type(stmt, 8) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(stmt, 8))
                : nil
            let ts    = ISO8601DateFormatter().date(from: tsStr) ?? Date()
            results.append(TranscriptRecord(id: id, timestamp: ts, durationSeconds: dur,
                                            text: text, audioFilePath: path,
                                            sessionID: sid, sessionChunkSeq: seq,
                                            projectID: pid, speakerName: speakerName))
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
