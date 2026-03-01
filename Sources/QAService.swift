import Foundation

// MARK: - QAContext

/// Rich context gathered from all AutoClawd data sources for the QA assistant.
struct QAContext: Sendable {
    let sessionContext: String         // from SessionStore.buildContextBlock
    let worldModel: String             // from WorldModelService
    let projects: [(name: String, tags: String)]
    let recentAnalyses: [(summary: String, people: String, project: String?)]
    let recentTasks: [(title: String, status: String, project: String?)]
    let todos: String                  // freeform
    let structuredTodos: [(content: String, priority: String?, done: Bool)]
    let extractionFacts: [(content: String, bucket: String)]
}

// MARK: - QAService

final class QAService: @unchecked Sendable {
    private let ollama: OllamaService

    init(ollama: OllamaService) {
        self.ollama = ollama
    }

    // MARK: - Legacy (backward-compatible for ChunkManager)

    func answer(question: String) async throws -> String {
        let contextBlock = SessionStore.shared.buildContextBlock(
            currentSSID: await MainActor.run { LocationService.shared.currentSSID }
        )
        let prompt = buildPrompt(question: question, contextBlock: contextBlock)
        return try await runQuery(question: question, prompt: prompt, speak: true)
    }

    // MARK: - Rich Context Answer

    /// Answer a question using the full context from all AutoClawd data sources.
    func answer(question: String, context: QAContext, speak: Bool = false) async throws -> String {
        let contextBlock = buildRichContext(context)
        let prompt = buildPrompt(question: question, contextBlock: contextBlock)
        return try await runQuery(question: question, prompt: prompt, speak: speak)
    }

    // MARK: - Private

    private func runQuery(question: String, prompt: String, speak: Bool) async throws -> String {
        Log.info(.qa, "Question: \"\(question)\" (prompt: \(prompt.count) chars)")
        let t0 = Date()
        let answer = try await ollama.generate(prompt: prompt, numPredict: 1024)
        let elapsed = Date().timeIntervalSince(t0)
        Log.info(.qa, "Answer in \(String(format: "%.1f", elapsed))s: \"\(String(answer.prefix(80)))\"")
        if speak {
            SpeechService.shared.speak(answer)
        }
        return answer
    }

    private func buildPrompt(question: String, contextBlock: String) -> String {
        let contextPrefix = contextBlock.isEmpty ? "" : "\(contextBlock)\n\n---\n\n"
        return """
        \(contextPrefix)You are AutoClawd, a personal AI assistant. You have access to the user's projects, \
        tasks, notes, conversations, and world knowledge. Answer helpfully and concisely. \
        Use the context above to give informed, specific answers. If you don't have the information, say so.

        Question: \(question)
        """
    }

    private func buildRichContext(_ ctx: QAContext) -> String {
        var sections: [String] = []

        // 1. Session context (user profile + location + recent sessions)
        if !ctx.sessionContext.isEmpty {
            sections.append(ctx.sessionContext)
        }

        // 2. World knowledge
        let world = ctx.worldModel.prefix(800)
        if !world.isEmpty {
            sections.append("[WORLD KNOWLEDGE]\n\(world)")
        }

        // 3. Projects
        if !ctx.projects.isEmpty {
            let list = ctx.projects.prefix(10).map { p in
                let tags = p.tags.isEmpty ? "" : " [\(p.tags)]"
                return "• \(p.name)\(tags)"
            }.joined(separator: "\n")
            sections.append("[YOUR PROJECTS]\n\(list)")
        }

        // 4. Recent intelligence (analyses)
        if !ctx.recentAnalyses.isEmpty {
            let list = ctx.recentAnalyses.prefix(5).map { a in
                var line = "• \(a.summary)"
                if let proj = a.project, !proj.isEmpty { line += " (project: \(proj))" }
                if !a.people.isEmpty { line += " — people: \(a.people)" }
                return line
            }.joined(separator: "\n")
            sections.append("[RECENT CONVERSATIONS & INTELLIGENCE]\n\(list)")
        }

        // 5. Tasks
        if !ctx.recentTasks.isEmpty {
            let list = ctx.recentTasks.prefix(10).map { t in
                var line = "• [\(t.status)] \(t.title)"
                if let proj = t.project, !proj.isEmpty { line += " (\(proj))" }
                return line
            }.joined(separator: "\n")
            sections.append("[TASKS]\n\(list)")
        }

        // 6. Todos
        var todoLines: [String] = []
        if !ctx.structuredTodos.isEmpty {
            for t in ctx.structuredTodos.prefix(15) {
                let check = t.done ? "✓" : "○"
                let pri = t.priority.map { " [\($0)]" } ?? ""
                todoLines.append("\(check) \(t.content)\(pri)")
            }
        }
        let freeformTodos = ctx.todos.prefix(400)
        if !freeformTodos.isEmpty {
            todoLines.append(String(freeformTodos))
        }
        if !todoLines.isEmpty {
            sections.append("[TODOS]\n\(todoLines.joined(separator: "\n"))")
        }

        // 7. Extracted facts (people, decisions, preferences)
        if !ctx.extractionFacts.isEmpty {
            let list = ctx.extractionFacts.prefix(20).map { f in
                "• [\(f.bucket)] \(f.content)"
            }.joined(separator: "\n")
            sections.append("[EXTRACTED FACTS & NOTES]\n\(list)")
        }

        // Truncate total context to ~3000 chars to fit llama3.2 context window
        let combined = sections.joined(separator: "\n\n")
        if combined.count > 3000 {
            return String(combined.prefix(3000)) + "\n[...truncated]"
        }
        return combined
    }
}
