import Foundation
import SQLite3

// MARK: - Project

struct Project: Identifiable {
    let id: String         // UUID string
    var name: String
    var localPath: String  // absolute folder path
    let createdAt: Date
}

// MARK: - ProjectStore

final class ProjectStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.autoclawd.projectstore", qos: .utility)

    init(url: URL) {
        let status = sqlite3_open(url.path, &db)
        if status != SQLITE_OK {
            Log.error(.system, "ProjectStore: SQLite open failed: \(status)")
            return
        }
        createTables()
        Log.info(.system, "ProjectStore opened at \(url.lastPathComponent)")
    }

    deinit { sqlite3_close(db) }

    // MARK: - Write

    @discardableResult
    func insert(name: String, localPath: String) -> Project {
        let id = UUID().uuidString
        let now = Date()
        let ts = ISO8601DateFormatter().string(from: now)
        let sql = """
            INSERT INTO projects (id, name, local_path, created_at)
            VALUES (?, ?, ?, ?);
        """
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_text(stmt, 2, name, -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_text(stmt, 3, localPath, -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_text(stmt, 4, ts, -1, SQLITE_TRANSIENT_PS)
            sqlite3_step(stmt)
        }
        return Project(id: id, name: name, localPath: localPath, createdAt: now)
    }

    func update(_ project: Project) {
        let sql = "UPDATE projects SET name = ?, local_path = ? WHERE id = ?;"
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, project.name, -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_text(stmt, 2, project.localPath, -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_text(stmt, 3, project.id, -1, SQLITE_TRANSIENT_PS)
            sqlite3_step(stmt)
        }
    }

    func delete(id: String) {
        let sql = "DELETE FROM projects WHERE id = ?;"
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT_PS)
            sqlite3_step(stmt)
        }
    }

    // MARK: - Read

    func all() -> [Project] {
        queue.sync { fetchAll() }
    }

    // MARK: - Schema

    private func createTables() {
        let sql = """
            CREATE TABLE IF NOT EXISTS projects (
                id         TEXT PRIMARY KEY,
                name       TEXT NOT NULL,
                local_path TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
        """
        execSQL(sql)
    }

    // MARK: - SQL Helpers

    private func fetchAll() -> [Project] {
        let sql = "SELECT id, name, local_path, created_at FROM projects ORDER BY created_at ASC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var results: [Project] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id    = String(cString: sqlite3_column_text(stmt, 0))
            let name  = String(cString: sqlite3_column_text(stmt, 1))
            let path  = String(cString: sqlite3_column_text(stmt, 2))
            let tsStr = String(cString: sqlite3_column_text(stmt, 3))
            let ts    = ISO8601DateFormatter().date(from: tsStr) ?? Date()
            results.append(Project(id: id, name: name, localPath: path, createdAt: ts))
        }
        return results
    }

    private func execSQL(_ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &err)
        if result != SQLITE_OK, let e = err {
            Log.error(.system, "ProjectStore SQL error: \(String(cString: e))")
            sqlite3_free(err)
        }
    }
}

// Renamed to avoid symbol conflict with TranscriptStore's SQLITE_TRANSIENT
private let SQLITE_TRANSIENT_PS = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
