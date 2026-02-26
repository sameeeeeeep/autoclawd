// Sources/TodoFramingService.swift
import Foundation

/// Rewrites a raw spoken task payload into a clean, actionable title
/// using the local Ollama model with project README/CLAUDE.md as context.
actor TodoFramingService {

    private let ollama: OllamaService

    init(ollama: OllamaService) {
        self.ollama = ollama
    }

    /// Returns a framed task title, or `rawPayload` unchanged on any failure.
    func frame(rawPayload: String, for project: Project) async -> String {
        let context = loadContext(from: project.localPath)
        let prompt = buildPrompt(raw: rawPayload, projectName: project.name, context: context)

        do {
            // numPredict: 60 — title only, no long response needed
            let raw = try await withTimeout(seconds: 8) {
                try await self.ollama.generate(prompt: prompt, numPredict: 60)
            }
            let cleaned = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return cleaned.isEmpty ? rawPayload : cleaned
        } catch {
            Log.warn(.system, "TodoFramingService: framing failed — \(error). Using raw payload.")
            return rawPayload
        }
    }

    // MARK: - Private

    private func loadContext(from localPath: String) -> String {
        var parts: [String] = []
        for filename in ["README.md", "CLAUDE.md"] {
            let url = URL(fileURLWithPath: localPath).appendingPathComponent(filename)
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                let truncated = String(text.prefix(1500))
                parts.append("[\(filename)]\n\(truncated)")
            }
        }
        return parts.joined(separator: "\n\n")
    }

    private func buildPrompt(raw: String, projectName: String, context: String) -> String {
        var p = """
        You are a task management assistant for a software project.
        Rewrite the raw spoken task as a single clean, actionable task title.
        Requirements: imperative mood, max 12 words, no filler words, no punctuation at end.
        Respond with ONLY the task title — no explanation, no quotes.

        Project: \(projectName)
        """
        if !context.isEmpty {
            p += "\n\nProject context:\n\(context)"
        }
        p += "\n\nRaw spoken task: \"\(raw)\""
        return p
    }
}

// MARK: - Timeout helper

/// Runs `operation` and cancels it if it takes longer than `seconds`.
private func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw CancellationError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
