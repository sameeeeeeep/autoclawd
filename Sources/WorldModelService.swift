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

    /// Returns the most relevant excerpt from the global world model for a Haiku/vision prompt.
    ///
    /// Strategy:
    /// 1. Always include the "## Suggestion Feedback" section (personalisation signal).
    /// 2. If an app name is provided, include any `##` section whose heading contains the app name.
    /// 3. Fill remaining budget with the top of the model.
    func excerpt(forApp app: String?, maxChars: Int = 2000) -> String {
        let full = read()
        guard !full.isEmpty else { return "" }

        var result = ""

        // Always include Suggestion Feedback (learning signal)
        if let feedbackRange = full.range(of: "## Suggestion Feedback") {
            let feedbackSection = String(full[feedbackRange.lowerBound...])
            let feedbackLines = feedbackSection.components(separatedBy: "\n").prefix(20)
            result += feedbackLines.joined(separator: "\n") + "\n\n"
        }

        // Include section matching the active app
        if let appName = app, !appName.isEmpty {
            let sections = full.components(separatedBy: "\n## ")
            for section in sections {
                let heading = section.components(separatedBy: "\n").first ?? ""
                if heading.localizedCaseInsensitiveContains(appName) {
                    let snip = "## \(section)".prefix(600)
                    result += snip + "\n\n"
                }
            }
        }

        // Fill remaining budget from the top of the model
        let remaining = maxChars - result.count
        if remaining > 200 {
            let topSlice = String(full.prefix(remaining))
            result += topSlice
        }

        return String(result.prefix(maxChars))
    }

    /// Append a suggestion feedback note to the global world model.
    /// Used to teach the system what the user considers actionable vs. irrelevant.
    func appendSuggestionFeedback(_ note: String) {
        queue.async { [self] in
            var content = self.read()
            if !content.contains("## Suggestion Feedback") {
                content += "\n\n## Suggestion Feedback\n"
            }
            let date = ISO8601DateFormatter().string(from: Date())
            content += "- [\(date)] \(note)\n"
            self.write(content)
        }
    }
}
