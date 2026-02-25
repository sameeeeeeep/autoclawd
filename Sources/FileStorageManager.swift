import Foundation

/// Manages the ~/.autoclawd/ directory structure and file paths.
final class FileStorageManager: @unchecked Sendable {
    static let shared = FileStorageManager()

    let rootDirectory: URL
    let audioDirectory: URL
    let logsDirectory: URL
    let transcriptsDatabaseURL: URL
    var intelligenceDatabaseURL: URL {
        rootDirectory.appendingPathComponent("intelligence.db")
    }
    let worldModelURL: URL
    let todosURL: URL
    let configURL: URL

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        rootDirectory = home.appendingPathComponent(".autoclawd")
        audioDirectory = rootDirectory.appendingPathComponent("audio")
        logsDirectory = rootDirectory.appendingPathComponent("logs")
        transcriptsDatabaseURL = rootDirectory.appendingPathComponent("transcripts.db")
        worldModelURL = rootDirectory.appendingPathComponent("world-model.md")
        todosURL = rootDirectory.appendingPathComponent("todos.md")
        configURL = rootDirectory.appendingPathComponent("config.json")

        createDirectories()
        seedDefaultFiles()
    }

    func audioFile(date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let name = formatter.string(from: date) + ".wav"
        return audioDirectory.appendingPathComponent(name)
    }

    func logFile(for dateString: String) -> URL {
        logsDirectory.appendingPathComponent("autoclawd-\(dateString).log")
    }

    func purgeOldAudio(retentionDays: Int = 7) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: audioDirectory, includingPropertiesForKeys: [.creationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86400)
        for file in files where file.pathExtension == "wav" {
            if let attrs = try? file.resourceValues(forKeys: [.creationDateKey]),
               let created = attrs.creationDate, created < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    // MARK: - Private

    private func createDirectories() {
        for dir in [rootDirectory, audioDirectory, logsDirectory] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func seedDefaultFiles() {
        if !FileManager.default.fileExists(atPath: worldModelURL.path) {
            let content = """
# AutoClawd World Model
Last updated: (not yet updated)

## People

## Projects

## Plans

## Preferences

## Decisions
"""
            try? content.write(to: worldModelURL, atomically: true, encoding: .utf8)
        }

        if !FileManager.default.fileExists(atPath: todosURL.path) {
            let content = """
# To-Do List
Last updated: (not yet updated)

## HIGH

## MEDIUM

## LOW

## DONE
"""
            try? content.write(to: todosURL, atomically: true, encoding: .utf8)
        }
    }
}
