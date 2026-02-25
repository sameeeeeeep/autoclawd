import Foundation

// MARK: - CleanupService
//
// Pass 3: Supervisory cleanup — two focused LLM calls.
//   Call 1: Rewrite world-model.md + todos.md (deduplicate + generate dev todos).
//   Call 2: Collapse duplicate ExtractionItems in DB into canonical entries.

final class CleanupService: @unchecked Sendable {
    private let ollama: OllamaService
    private let worldModel: WorldModelService
    private let todos: TodoService
    private let store: ExtractionStore

    init(ollama: OllamaService,
         worldModel: WorldModelService,
         todos: TodoService,
         store: ExtractionStore) {
        self.ollama = ollama
        self.worldModel = worldModel
        self.todos = todos
        self.store = store
    }

    func cleanup() async {
        Log.info(.cleanup, "Pass 3 start")
        async let call1: Void = rewriteKnowledge()
        async let call2: Void = collapseItems()
        _ = await (call1, call2)
        Log.info(.cleanup, "Pass 3 complete")
    }

    // MARK: - Call 1: Knowledge Rewrite

    private func rewriteKnowledge() async {
        let currentWorld = worldModel.read()
        let currentTodos = todos.read()

        let dateStr: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date())
        }()

        let prompt = """
You are a supervisory AI managing a personal knowledge base.

TODAY: \(dateStr)

CURRENT WORLD MODEL:
\(currentWorld)

CURRENT TO-DO LIST:
\(currentTodos)

Your tasks:
1. Rewrite the world model into clean structured markdown. Use these sections: ## People, ## Projects, ## Plans, ## Preferences, ## Decisions. Merge near-duplicates into one clear fact per line. Fix any malformed lines or stray punctuation.
2. Rewrite the to-do list. Merge near-duplicate todos into one canonical entry per intent. Organize by ## HIGH, ## MEDIUM, ## LOW, ## DONE.
3. Analyze the world model and todos for gaps, missing action items, or improvements needed in the AutoClawd app. Add these as new todos under the appropriate priority section.

Output ONLY the two XML blocks below. No explanation. No markdown outside the tags. Start immediately with <WORLD_MODEL>.

<WORLD_MODEL>
[rewritten world model]
</WORLD_MODEL>
<TODOS>
[rewritten todos including new dev todos]
</TODOS>
"""

        let response: String
        do {
            response = try await ollama.generate(prompt: prompt, numPredict: 2048)
        } catch {
            Log.error(.cleanup, "Call 1 Ollama error: \(error.localizedDescription)")
            return
        }

        let updatedWorld = extract(from: response, tag: "WORLD_MODEL")
        let updatedTodos = extract(from: response, tag: "TODOS")

        if updatedWorld == nil && updatedTodos == nil {
            let preview = String(response.prefix(200)).replacingOccurrences(of: "\n", with: " ")
            Log.error(.cleanup, "Call 1: XML tags missing. Preview: \(preview)")
            return
        }

        if let w = updatedWorld, !w.isEmpty {
            worldModel.write(w)
            Log.info(.cleanup, "World model rewritten (\(w.count) chars)")
        }

        if let t = updatedTodos, !t.isEmpty {
            todos.write(t)
            Log.info(.cleanup, "Todos rewritten (\(t.count) chars)")
        }
    }

    // MARK: - Call 2: Intelligence Item Collapsing

    private func collapseItems() async {
        let all = store.all()
        guard all.count > 1 else {
            Log.info(.cleanup, "Call 2: fewer than 2 items, skipping collapse")
            return
        }

        // Feed all items as a flat list: id | bucket | type | content
        let itemList = all.map { "\($0.id) | \($0.bucket.rawValue) | \($0.type.rawValue) | \($0.content)" }
            .joined(separator: "\n")

        let prompt = """
You are deduplicating a list of extracted knowledge items.

ITEMS (format: id | bucket | type | content):
\(itemList)

Find groups of items that express the same idea (same fact or same action).
For each group of 2+ near-duplicates, output ONE line:
<canonical text> | <id to keep> | <comma-separated ids to drop>

Rules:
- Only output lines for groups that have duplicates.
- The canonical text should be the clearest, most complete version.
- If an item is unique, do NOT output anything for it.
- No header. No explanation. No blank lines.

Example:
User prefers dark mode | abc123 | def456,ghi789
"""

        let response: String
        do {
            response = try await ollama.generate(prompt: prompt, numPredict: 1024)
        } catch {
            Log.error(.cleanup, "Call 2 Ollama error: \(error.localizedDescription)")
            return
        }

        var collapseCount = 0
        let lines = response.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.components(separatedBy: " | ")
            guard parts.count >= 3 else { continue }

            let canonical = parts[0].trimmingCharacters(in: .whitespaces)
            let keepId    = parts[1].trimmingCharacters(in: .whitespaces)
            let dropIds   = parts[2].components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            guard !canonical.isEmpty, !keepId.isEmpty, !dropIds.isEmpty else { continue }

            // Verify keepId exists in our item list to avoid LLM hallucinations
            guard all.contains(where: { $0.id == keepId }) else {
                Log.warn(.cleanup, "Call 2: keepId \(keepId) not found, skipping")
                continue
            }

            store.collapse(keepId: keepId, canonical: canonical, dropIds: dropIds)
            collapseCount += 1
            Log.info(.cleanup, "Collapsed \(dropIds.count) → 1: \"\(String(canonical.prefix(60)))\"")
        }

        Log.info(.cleanup, "Call 2 complete: \(collapseCount) groups collapsed")
    }

    // MARK: - Private Helpers

    private func extract(from text: String, tag: String) -> String? {
        let openTag  = "<\(tag)>"
        let closeTag = "</\(tag)>"
        guard let openRange  = text.range(of: openTag),
              let closeRange = text.range(of: closeTag),
              openRange.upperBound < closeRange.lowerBound
        else { return nil }
        return String(text[openRange.upperBound..<closeRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
