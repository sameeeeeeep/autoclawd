import Foundation
import SQLite3

// MARK: - PipelineStore

/// SQLite store for the multi-stage pipeline: cleaned transcripts, analyses, tasks, execution steps.
/// Database: ~/.autoclawd/pipeline.db
final class PipelineStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.autoclawd.pipelinestore", qos: .utility)

    init(url: URL) {
        let status = sqlite3_open(url.path, &db)
        if status != SQLITE_OK {
            Log.error(.system, "PipelineStore SQLite open failed: \(status)")
            return
        }
        createTables()
        enableWAL()
        Log.info(.system, "PipelineStore opened at \(url.lastPathComponent)")
    }

    deinit { sqlite3_close(db) }

    // MARK: - Schema

    private func createTables() {
        execSQL("""
            CREATE TABLE IF NOT EXISTS cleaned_transcripts (
                id                    TEXT PRIMARY KEY,
                session_id            TEXT,
                source_transcript_ids TEXT NOT NULL,
                is_continued          INTEGER NOT NULL DEFAULT 0,
                source_chunk_count    INTEGER NOT NULL DEFAULT 1,
                cleaned_text          TEXT NOT NULL,
                timestamp             REAL NOT NULL,
                speaker_name          TEXT,
                duration_seconds      INTEGER NOT NULL DEFAULT 0,
                created_at            REAL NOT NULL
            );
        """)

        execSQL("""
            CREATE TABLE IF NOT EXISTS transcript_analyses (
                id                     TEXT PRIMARY KEY,
                cleaned_transcript_id  TEXT NOT NULL,
                priority               TEXT,
                project_name           TEXT,
                project_id             TEXT,
                person_names           TEXT NOT NULL DEFAULT '',
                tags                   TEXT NOT NULL DEFAULT '',
                summary                TEXT NOT NULL DEFAULT '',
                task_descriptions_json TEXT NOT NULL DEFAULT '[]',
                timestamp              REAL NOT NULL,
                created_at             REAL NOT NULL
            );
        """)

        execSQL("""
            CREATE TABLE IF NOT EXISTS pipeline_tasks (
                id                 TEXT PRIMARY KEY,
                analysis_id        TEXT NOT NULL,
                title              TEXT NOT NULL,
                prompt             TEXT NOT NULL,
                project_id         TEXT,
                project_name       TEXT,
                mode               TEXT NOT NULL DEFAULT 'auto',
                status             TEXT NOT NULL DEFAULT 'upcoming',
                skill_id           TEXT,
                workflow_id        TEXT,
                workflow_steps     TEXT NOT NULL DEFAULT '',
                missing_connection TEXT,
                pending_question   TEXT,
                created_at         REAL NOT NULL,
                started_at         REAL,
                completed_at       REAL
            );
        """)

        execSQL("""
            CREATE TABLE IF NOT EXISTS task_execution_steps (
                id          TEXT PRIMARY KEY,
                task_id     TEXT NOT NULL,
                step_index  INTEGER NOT NULL,
                description TEXT NOT NULL,
                status      TEXT NOT NULL DEFAULT 'completed',
                timestamp   REAL NOT NULL,
                output      TEXT
            );
        """)

        execSQL("""
            CREATE TABLE IF NOT EXISTS task_id_counter (
                prefix   TEXT PRIMARY KEY,
                next_seq INTEGER NOT NULL DEFAULT 1
            );
        """)
    }

    private func enableWAL() {
        execSQL("PRAGMA journal_mode=WAL;")
    }

    // MARK: - Cleaned Transcripts

    func insertCleanedTranscript(_ ct: CleanedTranscript) {
        queue.async { [self] in
            let sql = """
                INSERT OR IGNORE INTO cleaned_transcripts
                    (id, session_id, source_transcript_ids, is_continued, source_chunk_count,
                     cleaned_text, timestamp, speaker_name, duration_seconds, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            let idsCSV = ct.sourceTranscriptIDs.map(String.init).joined(separator: ",")

            sqlite3_bind_text(stmt, 1, ct.id, -1, SQLITE_TRANSIENT_PS)
            bindOptionalText(stmt, 2, ct.sessionID)
            sqlite3_bind_text(stmt, 3, idsCSV, -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_int(stmt, 4, ct.isContinued ? 1 : 0)
            sqlite3_bind_int(stmt, 5, Int32(ct.sourceChunkCount))
            sqlite3_bind_text(stmt, 6, ct.cleanedText, -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_double(stmt, 7, ct.timestamp.timeIntervalSince1970)
            bindOptionalText(stmt, 8, ct.speakerName)
            sqlite3_bind_int(stmt, 9, Int32(ct.durationSeconds))
            sqlite3_bind_double(stmt, 10, Date().timeIntervalSince1970)

            if sqlite3_step(stmt) != SQLITE_DONE {
                Log.error(.pipeline, "PipelineStore insertCleanedTranscript failed")
            }
        }
    }

    func fetchRecentCleaned(limit: Int = 100) -> [CleanedTranscript] {
        queue.sync { _fetchRecentCleaned(limit: limit) }
    }

    private func _fetchRecentCleaned(limit: Int) -> [CleanedTranscript] {
        let sql = """
            SELECT id, session_id, source_transcript_ids, is_continued, source_chunk_count,
                   cleaned_text, timestamp, speaker_name, duration_seconds
            FROM cleaned_transcripts ORDER BY created_at DESC LIMIT ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))

        var results: [CleanedTranscript] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let sessionID = columnOptionalText(stmt, 1)
            let idsCSV = String(cString: sqlite3_column_text(stmt, 2))
            let sourceIDs = idsCSV.split(separator: ",").compactMap { Int64($0) }
            let isContinued = sqlite3_column_int(stmt, 3) != 0
            let chunkCount = Int(sqlite3_column_int(stmt, 4))
            let cleanedText = String(cString: sqlite3_column_text(stmt, 5))
            let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))
            let speakerName = columnOptionalText(stmt, 7)
            let duration = Int(sqlite3_column_int(stmt, 8))

            results.append(CleanedTranscript(
                id: id, sessionID: sessionID, sourceTranscriptIDs: sourceIDs,
                isContinued: isContinued, sourceChunkCount: chunkCount,
                cleanedText: cleanedText, timestamp: timestamp,
                speakerName: speakerName, durationSeconds: duration
            ))
        }
        return results
    }

    // MARK: - Transcript Analyses

    func insertAnalysis(_ analysis: TranscriptAnalysis) {
        queue.async { [self] in
            let sql = """
                INSERT OR IGNORE INTO transcript_analyses
                    (id, cleaned_transcript_id, priority, project_name, project_id,
                     person_names, tags, summary, task_descriptions_json, timestamp, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            let personsCSV = analysis.personNames.joined(separator: ",")
            let tagsCSV = analysis.tags.joined(separator: ",")
            let taskDescJSON = encodeTaskDescriptions(analysis.taskDescriptions)

            sqlite3_bind_text(stmt, 1, analysis.id, -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_text(stmt, 2, analysis.cleanedTranscriptID, -1, SQLITE_TRANSIENT_PS)
            bindOptionalText(stmt, 3, analysis.priority)
            bindOptionalText(stmt, 4, analysis.projectName)
            bindOptionalText(stmt, 5, analysis.projectID)
            sqlite3_bind_text(stmt, 6, personsCSV, -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_text(stmt, 7, tagsCSV, -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_text(stmt, 8, analysis.summary, -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_text(stmt, 9, taskDescJSON, -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_double(stmt, 10, analysis.timestamp.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 11, Date().timeIntervalSince1970)

            if sqlite3_step(stmt) != SQLITE_DONE {
                Log.error(.pipeline, "PipelineStore insertAnalysis failed")
            }
        }
    }

    func fetchRecentAnalyses(limit: Int = 100) -> [TranscriptAnalysis] {
        queue.sync { _fetchRecentAnalyses(limit: limit) }
    }

    private func _fetchRecentAnalyses(limit: Int) -> [TranscriptAnalysis] {
        let sql = """
            SELECT id, cleaned_transcript_id, priority, project_name, project_id,
                   person_names, tags, summary, task_descriptions_json, timestamp
            FROM transcript_analyses ORDER BY created_at DESC LIMIT ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))

        var results: [TranscriptAnalysis] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let ctID = String(cString: sqlite3_column_text(stmt, 1))
            let priority = columnOptionalText(stmt, 2)
            let projectName = columnOptionalText(stmt, 3)
            let projectID = columnOptionalText(stmt, 4)
            let personsCSV = String(cString: sqlite3_column_text(stmt, 5))
            let tagsCSV = String(cString: sqlite3_column_text(stmt, 6))
            let summary = String(cString: sqlite3_column_text(stmt, 7))
            let taskDescJSON = String(cString: sqlite3_column_text(stmt, 8))
            let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 9))

            let persons = personsCSV.isEmpty ? [] : personsCSV.split(separator: ",").map(String.init)
            let tags = tagsCSV.isEmpty ? [] : tagsCSV.split(separator: ",").map(String.init)
            let taskDescs = decodeTaskDescriptions(taskDescJSON)

            results.append(TranscriptAnalysis(
                id: id, cleanedTranscriptID: ctID, priority: priority,
                projectName: projectName, projectID: projectID,
                personNames: persons, tags: tags, summary: summary,
                taskDescriptions: taskDescs, timestamp: timestamp
            ))
        }
        return results
    }

    // MARK: - Pipeline Tasks

    func insertTask(_ task: PipelineTaskRecord) {
        queue.async { [self] in
            let sql = """
                INSERT OR IGNORE INTO pipeline_tasks
                    (id, analysis_id, title, prompt, project_id, project_name,
                     mode, status, skill_id, workflow_id, workflow_steps,
                     missing_connection, pending_question, created_at, started_at, completed_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            let stepsCSV = task.workflowSteps.joined(separator: "|")

            sqlite3_bind_text(stmt, 1, task.id, -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_text(stmt, 2, task.analysisID, -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_text(stmt, 3, task.title, -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_text(stmt, 4, task.prompt, -1, SQLITE_TRANSIENT_PS)
            bindOptionalText(stmt, 5, task.projectID)
            bindOptionalText(stmt, 6, task.projectName)
            sqlite3_bind_text(stmt, 7, task.mode.rawValue, -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_text(stmt, 8, task.status.rawValue, -1, SQLITE_TRANSIENT_PS)
            bindOptionalText(stmt, 9, task.skillID)
            bindOptionalText(stmt, 10, task.workflowID)
            sqlite3_bind_text(stmt, 11, stepsCSV, -1, SQLITE_TRANSIENT_PS)
            bindOptionalText(stmt, 12, task.missingConnection)
            bindOptionalText(stmt, 13, task.pendingQuestion)
            sqlite3_bind_double(stmt, 14, task.createdAt.timeIntervalSince1970)
            bindOptionalDouble(stmt, 15, task.startedAt?.timeIntervalSince1970)
            bindOptionalDouble(stmt, 16, task.completedAt?.timeIntervalSince1970)

            if sqlite3_step(stmt) != SQLITE_DONE {
                Log.error(.pipeline, "PipelineStore insertTask failed")
            }
        }
    }

    func updateTaskStatus(id: String, status: TaskStatus, startedAt: Date? = nil, completedAt: Date? = nil) {
        queue.async { [self] in
            var setClauses = ["status = ?"]
            if startedAt != nil { setClauses.append("started_at = ?") }
            if completedAt != nil { setClauses.append("completed_at = ?") }
            let sql = "UPDATE pipeline_tasks SET \(setClauses.joined(separator: ", ")) WHERE id = ?;"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            var idx: Int32 = 1
            sqlite3_bind_text(stmt, idx, status.rawValue, -1, SQLITE_TRANSIENT_PS); idx += 1
            if let sa = startedAt { sqlite3_bind_double(stmt, idx, sa.timeIntervalSince1970); idx += 1 }
            if let ca = completedAt { sqlite3_bind_double(stmt, idx, ca.timeIntervalSince1970); idx += 1 }
            sqlite3_bind_text(stmt, idx, id, -1, SQLITE_TRANSIENT_PS)

            if sqlite3_step(stmt) != SQLITE_DONE {
                Log.error(.pipeline, "PipelineStore updateTaskStatus failed for \(id)")
            }
        }
    }

    func updateTaskMode(id: String, mode: TaskMode) {
        queue.async { [self] in
            let sql = "UPDATE pipeline_tasks SET mode = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, mode.rawValue, -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_text(stmt, 2, id, -1, SQLITE_TRANSIENT_PS)
            sqlite3_step(stmt)
        }
    }

    func fetchRecentTasks(limit: Int = 100) -> [PipelineTaskRecord] {
        queue.sync { _fetchRecentTasks(limit: limit) }
    }

    private func _fetchRecentTasks(limit: Int) -> [PipelineTaskRecord] {
        let sql = """
            SELECT id, analysis_id, title, prompt, project_id, project_name,
                   mode, status, skill_id, workflow_id, workflow_steps,
                   missing_connection, pending_question, created_at, started_at, completed_at
            FROM pipeline_tasks ORDER BY created_at DESC LIMIT ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))

        var results: [PipelineTaskRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let analysisID = String(cString: sqlite3_column_text(stmt, 1))
            let title = String(cString: sqlite3_column_text(stmt, 2))
            let prompt = String(cString: sqlite3_column_text(stmt, 3))
            let projectID = columnOptionalText(stmt, 4)
            let projectName = columnOptionalText(stmt, 5)
            let modeRaw = String(cString: sqlite3_column_text(stmt, 6))
            let statusRaw = String(cString: sqlite3_column_text(stmt, 7))
            let skillID = columnOptionalText(stmt, 8)
            let workflowID = columnOptionalText(stmt, 9)
            let stepsCSV = String(cString: sqlite3_column_text(stmt, 10))
            let missingConn = columnOptionalText(stmt, 11)
            let pendingQ = columnOptionalText(stmt, 12)
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 13))
            let startedAt = columnOptionalDate(stmt, 14)
            let completedAt = columnOptionalDate(stmt, 15)

            let steps = stepsCSV.isEmpty ? [] : stepsCSV.split(separator: "|").map(String.init)

            results.append(PipelineTaskRecord(
                id: id, analysisID: analysisID, title: title, prompt: prompt,
                projectID: projectID, projectName: projectName,
                mode: TaskMode(rawValue: modeRaw) ?? .auto,
                status: TaskStatus(rawValue: statusRaw) ?? .upcoming,
                skillID: skillID, workflowID: workflowID, workflowSteps: steps,
                missingConnection: missingConn, pendingQuestion: pendingQ,
                createdAt: createdAt, startedAt: startedAt, completedAt: completedAt
            ))
        }
        return results
    }

    // MARK: - Execution Steps

    func insertStep(_ step: TaskExecutionStep) {
        queue.async { [self] in
            let sql = """
                INSERT OR IGNORE INTO task_execution_steps
                    (id, task_id, step_index, description, status, timestamp, output)
                VALUES (?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, step.id, -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_text(stmt, 2, step.taskID, -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_int(stmt, 3, Int32(step.stepIndex))
            sqlite3_bind_text(stmt, 4, step.description, -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_text(stmt, 5, step.status, -1, SQLITE_TRANSIENT_PS)
            sqlite3_bind_double(stmt, 6, step.timestamp.timeIntervalSince1970)
            bindOptionalText(stmt, 7, step.output)

            if sqlite3_step(stmt) != SQLITE_DONE {
                Log.error(.pipeline, "PipelineStore insertStep failed")
            }
        }
    }

    func fetchSteps(taskID: String) -> [TaskExecutionStep] {
        queue.sync { _fetchSteps(taskID: taskID) }
    }

    private func _fetchSteps(taskID: String) -> [TaskExecutionStep] {
        let sql = """
            SELECT id, task_id, step_index, description, status, timestamp, output
            FROM task_execution_steps WHERE task_id = ? ORDER BY step_index ASC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, taskID, -1, SQLITE_TRANSIENT_PS)

        var results: [TaskExecutionStep] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let tid = String(cString: sqlite3_column_text(stmt, 1))
            let idx = Int(sqlite3_column_int(stmt, 2))
            let desc = String(cString: sqlite3_column_text(stmt, 3))
            let status = String(cString: sqlite3_column_text(stmt, 4))
            let ts = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
            let output = columnOptionalText(stmt, 6)

            results.append(TaskExecutionStep(
                id: id, taskID: tid, stepIndex: idx,
                description: desc, status: status, timestamp: ts, output: output
            ))
        }
        return results
    }

    // MARK: - Task ID Counter

    func nextTaskID(prefix: String) -> String {
        queue.sync { _nextTaskID(prefix: prefix) }
    }

    private func _nextTaskID(prefix: String) -> String {
        // Ensure row exists
        let upsert = "INSERT OR IGNORE INTO task_id_counter (prefix, next_seq) VALUES (?, 1);"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, upsert, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, prefix, -1, SQLITE_TRANSIENT_PS)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        // Fetch and increment atomically
        let fetchSQL = "SELECT next_seq FROM task_id_counter WHERE prefix = ?;"
        var seq: Int = 1
        if sqlite3_prepare_v2(db, fetchSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, prefix, -1, SQLITE_TRANSIENT_PS)
            if sqlite3_step(stmt) == SQLITE_ROW {
                seq = Int(sqlite3_column_int(stmt, 0))
            }
            sqlite3_finalize(stmt)
        }

        let updateSQL = "UPDATE task_id_counter SET next_seq = ? WHERE prefix = ?;"
        if sqlite3_prepare_v2(db, updateSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(seq + 1))
            sqlite3_bind_text(stmt, 2, prefix, -1, SQLITE_TRANSIENT_PS)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        return "T-\(prefix)-\(String(format: "%03d", seq))"
    }

    // MARK: - Helpers

    private func bindOptionalText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let v = value {
            sqlite3_bind_text(stmt, index, v, -1, SQLITE_TRANSIENT_PS)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bindOptionalDouble(_ stmt: OpaquePointer?, _ index: Int32, _ value: Double?) {
        if let v = value {
            sqlite3_bind_double(stmt, index, v)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func columnOptionalText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL { return nil }
        return String(cString: sqlite3_column_text(stmt, index))
    }

    private func columnOptionalDate(_ stmt: OpaquePointer?, _ index: Int32) -> Date? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(stmt, index))
    }

    private func encodeTaskDescriptions(_ descs: [AnalysisTaskDesc]) -> String {
        let arr = descs.map { ["t": $0.title, "p": $0.prompt] }
        guard let data = try? JSONSerialization.data(withJSONObject: arr),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }

    private func decodeTaskDescriptions(_ json: String) -> [AnalysisTaskDesc] {
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { return [] }
        return arr.compactMap { dict in
            guard let t = dict["t"], let p = dict["p"] else { return nil }
            return AnalysisTaskDesc(title: t, prompt: p)
        }
    }

    private func execSQL(_ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &err)
        if result != SQLITE_OK, let e = err {
            Log.error(.system, "PipelineStore exec error: \(String(cString: e))")
            sqlite3_free(err)
        }
    }
}

// Needed for sqlite3_bind_text with SQLITE_TRANSIENT
private let SQLITE_TRANSIENT_PS = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
