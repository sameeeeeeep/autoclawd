import Foundation
import SQLite3
import Vision

// MARK: - FaceEmbeddingStore

/// Persists face feature-print embeddings (VNFeaturePrintObservation) keyed by Person ID.
/// Enables cross-session face recognition: detected faces auto-match known people
/// without the user re-assigning them on every session.
///
/// VNFeaturePrintObservation conforms to NSSecureCoding, so it serialises cleanly
/// to a BLOB. Each person stores one representative embedding; sample_count tracks
/// how many frames contributed to it (higher = more robust).
final class FaceEmbeddingStore: @unchecked Sendable {

    static let shared = FaceEmbeddingStore(url: FileStorageManager.shared.facesDatabaseURL)

    // MARK: - Types

    struct StoredEmbedding {
        let personID: UUID
        let personName: String
        let featurePrint: VNFeaturePrintObservation
        let sampleCount: Int
    }

    // MARK: - State

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.autoclawd.faceembeddings", qos: .utility)

    // MARK: - Init

    init(url: URL) {
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            Log.error(.system, "FaceEmbeddingStore: failed to open \(url.lastPathComponent)")
            return
        }
        createTable()
        Log.info(.camera, "FaceEmbeddingStore opened at \(url.lastPathComponent)")
    }

    deinit { sqlite3_close(db) }

    // MARK: - CRUD

    /// Persist or update a face embedding for a person.
    /// Uses UPSERT: inserts on first save, updates embedding + increments sample_count on refresh.
    func save(personID: UUID, personName: String, featurePrint: VNFeaturePrintObservation) {
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: featurePrint, requiringSecureCoding: true
        ) else {
            Log.warn(.camera, "FaceEmbeddingStore: failed to archive embedding for \(personName)")
            return
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let idStr = personID.uuidString
        let sql = """
            INSERT INTO face_embeddings (person_id, person_name, embedding, sample_count, updated_at)
            VALUES (?, ?, ?, 1, ?)
            ON CONFLICT(person_id) DO UPDATE SET
                person_name  = excluded.person_name,
                embedding    = excluded.embedding,
                sample_count = sample_count + 1,
                updated_at   = excluded.updated_at;
        """

        let capturedData = data
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(stmt, 1, idStr, -1, t)
            sqlite3_bind_text(stmt, 2, personName, -1, t)
            capturedData.withUnsafeBytes { ptr in
                _ = sqlite3_bind_blob(stmt, 3, ptr.baseAddress, Int32(capturedData.count), t)
            }
            sqlite3_bind_text(stmt, 4, now, -1, t)
            sqlite3_step(stmt)
        }
    }

    /// Load all stored embeddings synchronously. Called once at app start.
    /// Embeddings are kept in-memory in FaceTracker for fast per-frame matching.
    func loadAll() -> [StoredEmbedding] {
        let sql = "SELECT person_id, person_name, embedding, sample_count FROM face_embeddings;"
        return queue.sync {
            guard let db = self.db else { return [] }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }

            var results: [StoredEmbedding] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard
                    let rawID   = sqlite3_column_text(stmt, 0),
                    let id      = UUID(uuidString: String(cString: rawID)),
                    let rawName = sqlite3_column_text(stmt, 1)
                else { continue }

                let name    = String(cString: rawName)
                let blobPtr = sqlite3_column_blob(stmt, 2)
                let blobLen = Int(sqlite3_column_bytes(stmt, 2))
                let count   = Int(sqlite3_column_int(stmt, 3))

                guard let ptr = blobPtr, blobLen > 0 else { continue }
                let data = Data(bytes: ptr, count: blobLen)
                guard let fp = try? NSKeyedUnarchiver.unarchivedObject(
                    ofClass: VNFeaturePrintObservation.self, from: data
                ) else { continue }

                results.append(StoredEmbedding(
                    personID: id, personName: name, featurePrint: fp, sampleCount: count
                ))
            }
            Log.info(.camera, "FaceEmbeddingStore: loaded \(results.count) stored face embeddings")
            return results
        }
    }

    /// Remove the stored embedding for a person (e.g. when person is deleted).
    func delete(personID: UUID) {
        let idStr = personID.uuidString
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            var stmt: OpaquePointer?
            let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            guard sqlite3_prepare_v2(
                db, "DELETE FROM face_embeddings WHERE person_id = ?;", -1, &stmt, nil
            ) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, idStr, -1, t)
            sqlite3_step(stmt)
        }
    }

    // MARK: - Schema

    private func createTable() {
        let sql = """
            CREATE TABLE IF NOT EXISTS face_embeddings (
                person_id    TEXT PRIMARY KEY,
                person_name  TEXT NOT NULL DEFAULT '',
                embedding    BLOB NOT NULL,
                sample_count INTEGER NOT NULL DEFAULT 1,
                updated_at   TEXT NOT NULL
            );
        """
        var err: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, sql, nil, nil, &err)
        if let e = err {
            Log.error(.system, "FaceEmbeddingStore SQL error: \(String(cString: e))")
            sqlite3_free(err)
        }
    }
}
