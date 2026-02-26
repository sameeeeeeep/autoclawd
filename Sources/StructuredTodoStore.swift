import Foundation
import SQLite3

// MARK: - StructuredTodo

struct StructuredTodo: Identifiable {
    let id: String
    var content: String
    var priority: String?        // "HIGH" / "MEDIUM" / "LOW" / nil
    var projectID: String?       // FK → projects.id (nullable)
    let createdAt: Date
    var isExecuted: Bool
    var executionOutput: String?
    var executionDate: Date?
}

// MARK: - StructuredTodoStore

final class StructuredTodoStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.autoclawd.structuredtodostore", qos: .utility)

    init(url: URL) {
        let status = sqlite3_open(url.path, &db)
        if status != SQLITE_OK {
            Log.error(.system, "StructuredTodoStore: SQLite open failed: \(status)")
            return
        }
        createTables()
        Log.info(.system, "StructuredTodoStore opened at \(url.lastPathComponent)")
    }

    deinit { sqlite3_close(db) }

    // MARK: - Write

    @discardableResult
    func insert(content: String, priority: String?) -> StructuredTodo {
        let id = UUID().uuidString
        let now = Date()
        let ts = ISO8601DateFormatter().string(from: now)
        let sql = """
            INSERT INTO structured_todos (id, content, priority, created_at, is_executed)
            VALUES (?, ?, ?, ?, 0);
        """
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, id)
            bind(stmt, 2, content)
            bindNullable(stmt, 3, priority)
            bind(stmt, 4, ts)
            sqlite3_step(stmt)
        }
        return StructuredTodo(id: id, content: content, priority: priority,
                              projectID: nil, createdAt: now,
                              isExecuted: false, executionOutput: nil, executionDate: nil)
    }

    func setProject(id: String, projectID: String?) {
        let sql = "UPDATE structured_todos SET project_id = ? WHERE id = ?;"
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            bindNullable(stmt, 1, projectID)
            bind(stmt, 2, id)
            sqlite3_step(stmt)
        }
    }

    func updateContent(id: String, content: String) {
        let sql = "UPDATE structured_todos SET content = ? WHERE id = ?;"
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, content)
            bind(stmt, 2, id)
            sqlite3_step(stmt)
        }
    }

    func markExecuted(id: String, output: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let sql = """
            UPDATE structured_todos
            SET is_executed = 1, execution_output = ?, execution_date = ?
            WHERE id = ?;
        """
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, output)
            bind(stmt, 2, ts)
            bind(stmt, 3, id)
            sqlite3_step(stmt)
        }
    }

    func delete(id: String) {
        let sql = "DELETE FROM structured_todos WHERE id = ?;"
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, id)
            sqlite3_step(stmt)
        }
    }

    // MARK: - Read

    func all() -> [StructuredTodo] {
        queue.sync { fetchAll() }
    }

    // MARK: - Schema

    private func createTables() {
        let sql = """
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
        """
        execSQL(sql)
        // Silent migrations for existing databases that predate new columns
        execSQL("ALTER TABLE structured_todos ADD COLUMN project_id TEXT;")
        execSQL("ALTER TABLE structured_todos ADD COLUMN execution_output TEXT;")
        execSQL("ALTER TABLE structured_todos ADD COLUMN execution_date TEXT;")
    }

    // MARK: - SQL Helpers

    private func fetchAll() -> [StructuredTodo] {
        let sql = """
            SELECT id, content, priority, project_id, created_at,
                   is_executed, execution_output, execution_date
            FROM structured_todos
            ORDER BY created_at DESC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var results: [StructuredTodo] = []
        let fmt = ISO8601DateFormatter()
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id      = String(cString: sqlite3_column_text(stmt, 0))
            let content = String(cString: sqlite3_column_text(stmt, 1))
            let priority: String? = sqlite3_column_type(stmt, 2) == SQLITE_NULL
                ? nil : String(cString: sqlite3_column_text(stmt, 2))
            let projectID: String? = sqlite3_column_type(stmt, 3) == SQLITE_NULL
                ? nil : String(cString: sqlite3_column_text(stmt, 3))
            let tsStr   = String(cString: sqlite3_column_text(stmt, 4))
            let ts      = fmt.date(from: tsStr) ?? Date()
            let executed = sqlite3_column_int(stmt, 5) != 0
            let output: String? = sqlite3_column_type(stmt, 6) == SQLITE_NULL
                ? nil : String(cString: sqlite3_column_text(stmt, 6))
            let exDateStr: String? = sqlite3_column_type(stmt, 7) == SQLITE_NULL
                ? nil : String(cString: sqlite3_column_text(stmt, 7))
            let exDate = exDateStr.flatMap { fmt.date(from: $0) }
            results.append(StructuredTodo(
                id: id, content: content, priority: priority,
                projectID: projectID, createdAt: ts,
                isExecuted: executed, executionOutput: output, executionDate: exDate
            ))
        }
        return results
    }

    private func bind(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String) {
        sqlite3_bind_text(stmt, idx, value, -1, SQLITE_TRANSIENT_STS)
    }

    private func bindNullable(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String?) {
        if let v = value {
            sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT_STS)
        } else {
            sqlite3_bind_null(stmt, idx)
        }
    }

    private func execSQL(_ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &err)
        if result != SQLITE_OK, let e = err {
            Log.error(.system, "StructuredTodoStore SQL error: \(String(cString: e))")
            sqlite3_free(err)
        }
    }
}

private let SQLITE_TRANSIENT_STS = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
