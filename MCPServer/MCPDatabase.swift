import Foundation
import SQLite3

private let SQLITE_TRANSIENT_MCP = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - Logging (stderr only — stdout is reserved for JSON-RPC)

func mcpLog(_ msg: String) {
    FileHandle.standardError.write(Data("[autoclawd-mcp] \(msg)\n".utf8))
}

// MARK: - SQL Helpers

private func execSQL(_ db: OpaquePointer?, _ sql: String) {
    var err: UnsafeMutablePointer<CChar>?
    let result = sqlite3_exec(db, sql, nil, nil, &err)
    if result != SQLITE_OK, let e = err {
        // Silence "duplicate column" errors from migrations
        let msg = String(cString: e)
        if !msg.contains("duplicate column") {
            mcpLog("SQL error: \(msg)")
        }
        sqlite3_free(err)
    }
}

private func bind(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String) {
    sqlite3_bind_text(stmt, idx, value, -1, SQLITE_TRANSIENT_MCP)
}

private func bindNullable(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String?) {
    if let v = value {
        sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT_MCP)
    } else {
        sqlite3_bind_null(stmt, idx)
    }
}

private func columnString(_ stmt: OpaquePointer?, _ idx: Int32) -> String {
    String(cString: sqlite3_column_text(stmt, idx))
}

private func columnOptionalString(_ stmt: OpaquePointer?, _ idx: Int32) -> String? {
    sqlite3_column_type(stmt, idx) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, idx))
}

// MARK: - MCPTodoStore

final class MCPTodoStore {
    private var db: OpaquePointer?

    init(url: URL) {
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            mcpLog("Failed to open todos DB at \(url.path)")
            return
        }
        execSQL(db, "PRAGMA journal_mode=WAL;")
        createTables()
    }

    deinit { sqlite3_close(db) }

    func all(projectID: String? = nil, status: String? = nil) -> [[String: Any]] {
        var sql = """
            SELECT id, content, priority, project_id, created_at,
                   is_executed, execution_output, execution_date
            FROM structured_todos
        """
        var conditions: [String] = []
        var args: [String] = []

        if let pid = projectID {
            conditions.append("project_id = ?")
            args.append(pid)
        }
        if let s = status {
            switch s {
            case "pending":  conditions.append("is_executed = 0")
            case "executed": conditions.append("is_executed = 1")
            default: break  // "all" — no filter
            }
        }
        if !conditions.isEmpty {
            sql += " WHERE " + conditions.joined(separator: " AND ")
        }
        sql += " ORDER BY created_at DESC;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        for (i, arg) in args.enumerated() {
            bind(stmt, Int32(i + 1), arg)
        }

        var results: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [
                "id": columnString(stmt, 0),
                "content": columnString(stmt, 1),
                "is_executed": sqlite3_column_int(stmt, 5) != 0,
                "created_at": columnString(stmt, 4)
            ]
            if let p = columnOptionalString(stmt, 2) { row["priority"] = p }
            if let pid = columnOptionalString(stmt, 3) { row["project_id"] = pid }
            if let out = columnOptionalString(stmt, 6) { row["execution_output"] = out }
            if let ed = columnOptionalString(stmt, 7) { row["execution_date"] = ed }
            results.append(row)
        }
        return results
    }

    func insert(content: String, priority: String?, projectID: String?) -> [String: Any] {
        let id = UUID().uuidString
        let ts = ISO8601DateFormatter().string(from: Date())
        let sql = """
            INSERT INTO structured_todos (id, content, priority, project_id, created_at, is_executed)
            VALUES (?, ?, ?, ?, ?, 0);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return ["error": "Failed to prepare insert"]
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, id)
        bind(stmt, 2, content)
        bindNullable(stmt, 3, priority)
        bindNullable(stmt, 4, projectID)
        bind(stmt, 5, ts)
        sqlite3_step(stmt)

        var row: [String: Any] = [
            "id": id, "content": content, "is_executed": false, "created_at": ts
        ]
        if let p = priority { row["priority"] = p }
        if let pid = projectID { row["project_id"] = pid }
        return row
    }

    func updateContent(id: String, content: String) {
        let sql = "UPDATE structured_todos SET content = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, content)
        bind(stmt, 2, id)
        sqlite3_step(stmt)
    }

    func updatePriority(id: String, priority: String?) {
        let sql = "UPDATE structured_todos SET priority = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindNullable(stmt, 1, priority)
        bind(stmt, 2, id)
        sqlite3_step(stmt)
    }

    func setProject(id: String, projectID: String?) {
        let sql = "UPDATE structured_todos SET project_id = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindNullable(stmt, 1, projectID)
        bind(stmt, 2, id)
        sqlite3_step(stmt)
    }

    func markExecuted(id: String, output: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let sql = """
            UPDATE structured_todos
            SET is_executed = 1, execution_output = ?, execution_date = ?
            WHERE id = ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, output)
        bind(stmt, 2, ts)
        bind(stmt, 3, id)
        sqlite3_step(stmt)
    }

    func delete(id: String) {
        let sql = "DELETE FROM structured_todos WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, id)
        sqlite3_step(stmt)
    }

    private func createTables() {
        execSQL(db, """
            CREATE TABLE IF NOT EXISTS structured_todos (
                id               TEXT PRIMARY KEY,
                content          TEXT NOT NULL,
                priority         TEXT,
                project_id       TEXT,
                created_at       TEXT NOT NULL,
                is_executed      INTEGER NOT NULL DEFAULT 0,
                execution_output TEXT,
                execution_date   TEXT
            );
        """)
        execSQL(db, "ALTER TABLE structured_todos ADD COLUMN project_id TEXT;")
        execSQL(db, "ALTER TABLE structured_todos ADD COLUMN execution_output TEXT;")
        execSQL(db, "ALTER TABLE structured_todos ADD COLUMN execution_date TEXT;")
    }
}

// MARK: - MCPProjectStore

final class MCPProjectStore {
    private var db: OpaquePointer?

    init(url: URL) {
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            mcpLog("Failed to open projects DB at \(url.path)")
            return
        }
        execSQL(db, "PRAGMA journal_mode=WAL;")
        createTables()
    }

    deinit { sqlite3_close(db) }

    func all() -> [[String: Any]] {
        let sql = "SELECT id, name, local_path, tags, linked_project_ids, created_at FROM projects ORDER BY created_at ASC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var results: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let tagsRaw = columnOptionalString(stmt, 3) ?? ""
            let tags = tagsRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            results.append([
                "id": columnString(stmt, 0),
                "name": columnString(stmt, 1),
                "local_path": columnString(stmt, 2),
                "tags": tags,
                "created_at": columnString(stmt, 5)
            ])
        }
        return results
    }

    private func createTables() {
        execSQL(db, """
            CREATE TABLE IF NOT EXISTS projects (
                id         TEXT PRIMARY KEY,
                name       TEXT NOT NULL,
                local_path TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
        """)
        execSQL(db, "ALTER TABLE projects ADD COLUMN tags TEXT DEFAULT '';")
        execSQL(db, "ALTER TABLE projects ADD COLUMN linked_project_ids TEXT DEFAULT '';")
    }
}

// MARK: - MCPTranscriptStore

final class MCPTranscriptStore {
    private var db: OpaquePointer?

    init(url: URL) {
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            mcpLog("Failed to open transcripts DB at \(url.path)")
            return
        }
        execSQL(db, "PRAGMA journal_mode=WAL;")
        createTables()
    }

    deinit { sqlite3_close(db) }

    func search(query: String, limit: Int) -> [[String: Any]] {
        let sql = """
            SELECT t.id, t.timestamp, t.duration_seconds, t.text, t.speaker_name
            FROM transcripts t
            JOIN transcripts_fts f ON t.id = f.rowid
            WHERE transcripts_fts MATCH ?
            ORDER BY t.id DESC
            LIMIT ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, query)
        sqlite3_bind_int(stmt, 2, Int32(limit))
        var results: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [
                "id": sqlite3_column_int64(stmt, 0),
                "timestamp": columnString(stmt, 1),
                "duration_seconds": Int(sqlite3_column_int(stmt, 2)),
                "text": columnString(stmt, 3)
            ]
            if let name = columnOptionalString(stmt, 4) { row["speaker_name"] = name }
            results.append(row)
        }
        return results
    }

    private func createTables() {
        execSQL(db, """
            CREATE TABLE IF NOT EXISTS transcripts (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp       TEXT NOT NULL,
                duration_seconds INTEGER NOT NULL DEFAULT 0,
                text            TEXT NOT NULL,
                audio_file_path TEXT NOT NULL DEFAULT ''
            );
        """)
        execSQL(db, """
            CREATE VIRTUAL TABLE IF NOT EXISTS transcripts_fts
            USING fts5(text, content='transcripts', content_rowid='id');
        """)
        execSQL(db, """
            CREATE TRIGGER IF NOT EXISTS transcripts_ai
            AFTER INSERT ON transcripts BEGIN
                INSERT INTO transcripts_fts(rowid, text) VALUES (new.id, new.text);
            END;
        """)
        execSQL(db, "ALTER TABLE transcripts ADD COLUMN session_id TEXT;")
        execSQL(db, "ALTER TABLE transcripts ADD COLUMN session_chunk_seq INTEGER NOT NULL DEFAULT 0;")
        execSQL(db, "ALTER TABLE transcripts ADD COLUMN project_id TEXT;")
        execSQL(db, "ALTER TABLE transcripts ADD COLUMN speaker_name TEXT;")
    }
}
