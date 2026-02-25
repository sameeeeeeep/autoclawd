import Foundation
import SQLite3

// MARK: - Project

struct Project: Identifiable {
    let id: String         // UUID string
    var name: String
    var localPath: String  // absolute folder path
    let createdAt: Date
    var tags: [String]           // stored as comma-separated e.g. "ai,personal,work"
    var linkedProjectIDs: [UUID] // stored as comma-separated UUIDs

    init(id: String, name: String, localPath: String, createdAt: Date,
         tags: [String] = [], linkedProjectIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.localPath = localPath
        self.createdAt = createdAt
        self.tags = tags
        self.linkedProjectIDs = linkedProjectIDs
    }

    var tagsString: String { tags.joined(separator: ",") }
    var linkedIDsString: String { linkedProjectIDs.map(\.uuidString).joined(separator: ",") }

    static func parseTags(_ raw: String) -> [String] {
        raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    static func parseLinkedIDs(_ raw: String) -> [UUID] {
        raw.split(separator: ",").compactMap { UUID(uuidString: String($0).trimmingCharacters(in: .whitespaces)) }
    }
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
        // Silent column migrations — fail silently if columns already exist
        sqlite3_exec(db, "ALTER TABLE projects ADD COLUMN tags TEXT DEFAULT ''", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE projects ADD COLUMN linked_project_ids TEXT DEFAULT ''", nil, nil, nil)
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
            INSERT INTO projects (id, name, local_path, tags, linked_project_ids, created_at)
            VALUES (?, ?, ?, ?, ?, ?);
        """
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_text(stmt, 2, name, -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_text(stmt, 3, localPath, -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_text(stmt, 4, "", -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_text(stmt, 5, "", -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_text(stmt, 6, ts, -1, SQLITE_TRANSIENT_PS)
            sqlite3_step(stmt)
        }
        return Project(id: id, name: name, localPath: localPath, createdAt: now)
    }

    func update(_ project: Project) {
        let sql = "UPDATE projects SET name = ?, local_path = ?, tags = ?, linked_project_ids = ? WHERE id = ?;"
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, project.name, -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_text(stmt, 2, project.localPath, -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_text(stmt, 3, project.tagsString, -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_text(stmt, 4, project.linkedIDsString, -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_text(stmt, 5, project.id, -1, SQLITE_TRANSIENT_PS)
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

    // MARK: - Inference

    func inferProject(for payload: String, using ollamaService: OllamaService) async -> Project? {
        let allProjects = all()
        guard !allProjects.isEmpty else { return nil }

        let projectList = allProjects.map { p in
            let tagStr = p.tags.isEmpty ? "no tags" : p.tags.joined(separator: ", ")
            return "- \(p.name): \(tagStr)"
        }.joined(separator: "\n")

        let prompt = """
        Given this text: "\(payload)"

        Pick the most relevant project from this list, or reply "none":
        \(projectList)

        Reply with ONLY the project name exactly as listed, or "none".
        """

        guard let response = try? await ollamaService.generate(prompt: prompt, numPredict: 20) else {
            return nil
        }
        let name = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.lowercased() != "none" else { return nil }
        return allProjects.first { $0.name.lowercased() == name.lowercased() }
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
        let sql = "SELECT id, name, local_path, tags, linked_project_ids, created_at FROM projects ORDER BY created_at ASC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var results: [Project] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id       = String(cString: sqlite3_column_text(stmt, 0))
            let name     = String(cString: sqlite3_column_text(stmt, 1))
            let path     = String(cString: sqlite3_column_text(stmt, 2))
            let tagsRaw: String
            if let ptr = sqlite3_column_text(stmt, 3) { tagsRaw = String(cString: ptr) } else { tagsRaw = "" }
            let linkedRaw: String
            if let ptr = sqlite3_column_text(stmt, 4) { linkedRaw = String(cString: ptr) } else { linkedRaw = "" }
            let tsStr    = String(cString: sqlite3_column_text(stmt, 5))
            let ts       = ISO8601DateFormatter().date(from: tsStr) ?? Date()
            let tags     = Project.parseTags(tagsRaw)
            let linkedIDs = Project.parseLinkedIDs(linkedRaw)
            results.append(Project(id: id, name: name, localPath: path, createdAt: ts,
                                   tags: tags, linkedProjectIDs: linkedIDs))
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
