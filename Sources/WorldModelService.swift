import Foundation

final class WorldModelService: @unchecked Sendable {
    private let storage = FileStorageManager.shared
    private let queue = DispatchQueue(label: "com.autoclawd.worldmodel", qos: .utility)

    func read() -> String {
        (try? String(contentsOf: storage.worldModelURL, encoding: .utf8)) ?? ""
    }

    func write(_ content: String) {
        queue.async { [self] in
            do {
                try content.write(to: storage.worldModelURL, atomically: true, encoding: .utf8)
                Log.info(.world, "World model updated (\(content.count) chars)")
            } catch {
                Log.error(.world, "Failed to write world model: \(error.localizedDescription)")
            }
        }
    }

    func read(for projectID: UUID) -> String {
        let file = storage.rootDirectory.appendingPathComponent("world-model-\(projectID.uuidString).md")
        return (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    }

    func write(_ content: String, for projectID: UUID) {
        let file = storage.rootDirectory.appendingPathComponent("world-model-\(projectID.uuidString).md")
        try? content.write(to: file, atomically: true, encoding: .utf8)
    }

    func appendInfo(_ info: String, for projectID: UUID) {
        var existing = read(for: projectID)
        if existing.isEmpty { existing = "## Notes\n\n" }
        existing += "\n- \(info)"
        write(existing, for: projectID)
    }
}
