import Foundation
import SQLite3

// MARK: - Models

struct SessionRecord: Identifiable {
    let id: String           // UUID
    let startedAt: Date
    let endedAt: Date?
    let wifiSSID: String?
    let placeID: String?
    let placeName: String?   // joined from places table
    let transcriptSnippet: String  // first 120 chars for canvas card
}

struct PlaceRecord: Identifiable {
    let id: String
    let wifiSSID: String
    let name: String
}

// MARK: - SessionStore

final class SessionStore: @unchecked Sendable {
    static let shared = SessionStore(url: FileStorageManager.shared.sessionsDatabaseURL)

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.autoclawd.sessionstore", qos: .utility)

    init(url: URL) {
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            Log.error(.system, "SessionStore: failed to open \(url.lastPathComponent)")
            return
        }
        createTables()
        Log.info(.system, "SessionStore opened at \(url.lastPathComponent)")
    }

    deinit { sqlite3_close(db) }

    // MARK: - Session CRUD

    /// Create a new session row, returns the new session UUID.
    @discardableResult
    func beginSession(wifiSSID: String?) -> String {
        let id = UUID().uuidString
        let now = ISO8601DateFormatter().string(from: Date())
        let sql = """
            INSERT INTO sessions (id, started_at, wifi_ssid)
            VALUES (?, ?, ?);
        """
        execBindOptional(sql, args: [id, now, wifiSSID])
        Log.info(.system, "Session started: \(id)")
        return id
    }

    func endSession(id: String, transcriptSnippet: String) {
        let now = ISO8601DateFormatter().string(from: Date())
        let sql = """
            UPDATE sessions SET ended_at = ?, transcript_snippet = ?
            WHERE id = ?;
        """
        execBind(sql, args: [now, transcriptSnippet, id])
    }

    func updateSessionPlace(id: String, placeID: String) {
        execBind("UPDATE sessions SET place_id = ? WHERE id = ?;", args: [placeID, id])
    }

    // MARK: - Place CRUD

    func findPlace(wifiSSID: String) -> PlaceRecord? {
        let sql = "SELECT id, wifi_ssid, name FROM places WHERE wifi_ssid = ? LIMIT 1;"
        return queue.sync { queryPlaces(sql, args: [wifiSSID]).first }
    }

    @discardableResult
    func createPlace(wifiSSID: String, name: String) -> String {
        let id = UUID().uuidString
        let now = ISO8601DateFormatter().string(from: Date())
        execBind("INSERT INTO places (id, wifi_ssid, name, created_at) VALUES (?, ?, ?, ?);",
                 args: [id, wifiSSID, name, now])
        return id
    }

    // MARK: - Recent Sessions

    func recentSessions(limit: Int = 50) -> [SessionRecord] {
        let sql = """
            SELECT s.id, s.started_at, s.ended_at, s.wifi_ssid,
                   s.place_id, p.name, s.transcript_snippet
            FROM sessions s
            LEFT JOIN places p ON s.place_id = p.id
            ORDER BY s.started_at DESC
            LIMIT ?;
        """
        return queue.sync { querySessions(sql, args: [String(limit)]) }
    }

    // MARK: - User Profile (singleton row)

    func userContextBlob() -> String? {
        let sql = "SELECT context_blob FROM user_profile WHERE id = 1;"
        var result: String?
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            if sqlite3_step(stmt) == SQLITE_ROW,
               let raw = sqlite3_column_text(stmt, 0) {
                result = String(cString: raw)
            }
        }
        return result
    }

    func saveUserContextBlob(_ blob: String) {
        let now = ISO8601DateFormatter().string(from: Date())
        let sql = """
            INSERT INTO user_profile (id, context_blob, updated_at)
            VALUES (1, ?, ?)
            ON CONFLICT(id) DO UPDATE SET context_blob = excluded.context_blob,
                                          updated_at = excluded.updated_at;
        """
        execBind(sql, args: [blob, now])
    }

    // MARK: - Schema

    private func createTables() {
        execSQL("""
            CREATE TABLE IF NOT EXISTS sessions (
                id               TEXT PRIMARY KEY,
                started_at       TEXT NOT NULL,
                ended_at         TEXT,
                wifi_ssid        TEXT,
                place_id         TEXT,
                transcript_snippet TEXT NOT NULL DEFAULT ''
            );
        """)
        execSQL("""
            CREATE TABLE IF NOT EXISTS places (
                id         TEXT PRIMARY KEY,
                wifi_ssid  TEXT UNIQUE NOT NULL,
                name       TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
        """)
        execSQL("""
            CREATE TABLE IF NOT EXISTS user_profile (
                id           INTEGER PRIMARY KEY CHECK (id = 1),
                context_blob TEXT,
                updated_at   TEXT
            );
        """)
    }

    // MARK: - Helpers (internal for use by other services)

    func execBind(_ sql: String, args: [String]) {
        queue.async { [weak self] in
            guard let self else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            for (i, arg) in args.enumerated() {
                sqlite3_bind_text(stmt, Int32(i + 1), arg, -1, SQLITE_TRANSIENT)
            }
            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE {
                Log.error(.system, "SessionStore execBind failed (rc=\(rc)) for: \(sql.prefix(80))")
            }
        }
    }

    /// Variant that accepts optional strings — nil values are bound as SQL NULL.
    func execBindOptional(_ sql: String, args: [String?]) {
        queue.async { [weak self] in
            guard let self else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            for (i, arg) in args.enumerated() {
                if let value = arg {
                    sqlite3_bind_text(stmt, Int32(i + 1), value, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, Int32(i + 1))
                }
            }
            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE {
                Log.error(.system, "SessionStore execBindOptional failed (rc=\(rc)) for: \(sql.prefix(80))")
            }
        }
    }

    private func execSQL(_ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, sql, nil, nil, &err)
        if let e = err {
            Log.error(.system, "SessionStore SQL error: \(String(cString: e))")
            sqlite3_free(err)
        }
    }

    private func queryPlaces(_ sql: String, args: [String]) -> [PlaceRecord] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        for (i, arg) in args.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), arg, -1, SQLITE_TRANSIENT)
        }
        var results: [PlaceRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id   = String(cString: sqlite3_column_text(stmt, 0))
            let ssid = String(cString: sqlite3_column_text(stmt, 1))
            let name = String(cString: sqlite3_column_text(stmt, 2))
            results.append(PlaceRecord(id: id, wifiSSID: ssid, name: name))
        }
        return results
    }

    private func querySessions(_ sql: String, args: [String]) -> [SessionRecord] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        for (i, arg) in args.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), arg, -1, SQLITE_TRANSIENT)
        }
        var results: [SessionRecord] = []
        let iso = ISO8601DateFormatter()
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id        = String(cString: sqlite3_column_text(stmt, 0))
            let startStr  = String(cString: sqlite3_column_text(stmt, 1))
            let endRaw    = sqlite3_column_text(stmt, 2)
            let ssidRaw   = sqlite3_column_text(stmt, 3)
            let placeRaw  = sqlite3_column_text(stmt, 4)
            let nameRaw   = sqlite3_column_text(stmt, 5)
            let snippet   = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? ""
            results.append(SessionRecord(
                id: id,
                startedAt: iso.date(from: startStr) ?? Date(),
                endedAt: endRaw.flatMap { iso.date(from: String(cString: $0)) },
                wifiSSID: ssidRaw.map { String(cString: $0) },
                placeID: placeRaw.map { String(cString: $0) },
                placeName: nameRaw.map { String(cString: $0) },
                transcriptSnippet: snippet
            ))
        }
        return results
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - Context Block Builder

extension SessionStore {
    /// Builds the context preamble injected into every LLM prompt.
    func buildContextBlock(currentSSID: String?) -> String {
        var lines: [String] = []

        // User profile
        if let blob = userContextBlob(), !blob.isEmpty {
            lines.append("[USER CONTEXT]\n\(blob)")
        }

        // Current session location
        let place: String
        if let ssid = currentSSID, let p = findPlace(wifiSSID: ssid) {
            place = p.name.isEmpty ? "Unknown" : p.name
        } else {
            place = "Unknown"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM, h:mma"
        let timeStr = formatter.string(from: Date())
        lines.append("[CURRENT SESSION]\nLocation: \(place) | Time: \(timeStr)")

        // Last 3 sessions
        let recent = recentSessions(limit: 3)
        if !recent.isEmpty {
            let sessionSummaries = recent.map { s -> String in
                let df = DateFormatter()
                df.dateFormat = "EEE d MMM"
                let day = df.string(from: s.startedAt)
                let loc = s.placeName.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown"
                let snippet = s.transcriptSnippet.isEmpty ? "(no transcript)" : s.transcriptSnippet
                return "\(day) at \(loc) — \(snippet)"
            }.joined(separator: "\n")
            lines.append("[RECENT SESSIONS]\n\(sessionSummaries)")
        }

        return lines.joined(separator: "\n\n")
    }
}
