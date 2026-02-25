import Foundation

// MARK: - ExtractionService

/// Two-pass extraction pipeline:
///   Pass 1 (classifyChunk): Classify transcript ideas into structured ExtractionItems.
///   Pass 2 (synthesize):    Apply accepted items to world-model.md and todos.md.
final class ExtractionService: @unchecked Sendable {
    private let ollama: OllamaService
    private let worldModel: WorldModelService
    private let todos: TodoService
    private let store: ExtractionStore
    private let cleanupService: CleanupService

    init(ollama: OllamaService, worldModel: WorldModelService, todos: TodoService, store: ExtractionStore, cleanup: CleanupService) {
        self.ollama = ollama
        self.worldModel = worldModel
        self.todos = todos
        self.store = store
        self.cleanupService = cleanup
    }

    // MARK: - Pass 1: Classify Chunk

    func classifyChunk(
        transcript: String,
        chunkIndex: Int,
        sessionChunkSeq: Int = 0,
        previousChunkTrail: String = ""
    ) async -> [ExtractionItem] {
        let contextBlock = SessionStore.shared.buildContextBlock(
            currentSSID: await MainActor.run { LocationService.shared.currentSSID }
        )
        let contextPrefix = contextBlock.isEmpty ? "" : "\(contextBlock)\n\n---\n\n"

        // Session label: 0=A, 1=B, 2=C…
        let label = String(UnicodeScalar(UInt32(65 + min(sessionChunkSeq, 25)))!)

        // Inject trailing context from previous chunk so the LLM sees cross-boundary continuity
        let continuationPrefix: String
        if !previousChunkTrail.isEmpty && sessionChunkSeq > 0 {
            continuationPrefix = """
[CONTINUATION CONTEXT — chunk \(label) of this session]
The transcript below continues directly from the previous chunk, which ended with:
"\(previousChunkTrail)"
Treat any sentence that begins mid-thought as a continuation of the above.
Do NOT re-extract items already captured from the previous chunk.

---

"""
        } else {
            continuationPrefix = ""
        }

        let prompt = """
\(contextPrefix)\(continuationPrefix)You classify spoken transcript ideas into structured knowledge items.

TRANSCRIPT:
\(transcript)

Output one line per distinct idea using EXACTLY this pipe-delimited format:
<relevance>|<bucket>|<type>|<priority>|<content>

Fields:
- relevance: relevant | nonrelevant | uncertain
- bucket: projects | people | plans | preferences | decisions | other
- type: fact | todo
- priority: HIGH | MEDIUM | LOW | - (use - for facts)
- content: one normalized complete sentence

Rules:
- relevant: clear facts about the user, their work, decisions, preferences, action items
- nonrelevant: filler, incomplete sentences, ambient sound, pure small talk
- uncertain: might matter but lacks context to classify confidently
- No blank lines. No explanations. No markdown.

Example output:
relevant|projects|fact|-|User is testing the AutoClawd macOS app
relevant|projects|todo|HIGH|Complete AutoClawd testing phase
nonrelevant|-|-|-|Filler phrase
"""

        let response: String
        do {
            response = try await ollama.generate(prompt: prompt, numPredict: 512)
        } catch {
            Log.error(.extract, "Pass 1 Ollama error: \(error.localizedDescription)")
            return []
        }

        let sourcePhrase = String(transcript.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        let now = Date()

        var items: [ExtractionItem] = []
        var relevantCount = 0
        var nonrelevantCount = 0
        var uncertainCount = 0

        let lines = response.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Split on | taking first 5 tokens; rejoin remaining as content
            let parts = trimmed.components(separatedBy: "|")
            guard parts.count >= 5 else { continue }

            let relevance = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let bucketRaw = parts[1].trimmingCharacters(in: .whitespaces)
            let typeRaw   = parts[2].trimmingCharacters(in: .whitespaces)
            let priorityRaw = parts[3].trimmingCharacters(in: .whitespaces)
            let content   = parts[4...].joined(separator: "|").trimmingCharacters(in: .whitespaces)

            // Validate relevance
            guard relevance == "relevant" || relevance == "nonrelevant" || relevance == "uncertain" else {
                continue
            }

            let priority: String?
            if priorityRaw == "-" || priorityRaw.isEmpty {
                priority = nil
            } else {
                priority = priorityRaw
            }

            let item = ExtractionItem(
                id: UUID().uuidString,
                chunkIndex: chunkIndex,
                timestamp: now,
                sourcePhrase: sourcePhrase,
                content: content,
                type: ExtractionType(rawValue: typeRaw) ?? .fact,
                bucket: ExtractionBucket.parse(bucketRaw),
                priority: priority,
                modelDecision: relevance,
                userOverride: nil,
                applied: false
            )

            store.insert(item)
            items.append(item)

            switch relevance {
            case "relevant":    relevantCount += 1
            case "nonrelevant": nonrelevantCount += 1
            case "uncertain":   uncertainCount += 1
            default:            break
            }
        }

        Log.info(.extract, "Pass 1 done: chunk \(chunkIndex) [sess:\(label)] → \(items.count) items (\(relevantCount) relevant, \(nonrelevantCount) nonrelevant, \(uncertainCount) uncertain)")

        for item in items {
            let symbol = item.modelDecision == "nonrelevant" ? "✗" : "✓"
            Log.info(.extract, "\(symbol) \(item.modelDecision) | \(item.bucket.rawValue) | \(item.type.rawValue) | \(item.content)")
        }

        // Speak the first relevant item as a brief ambient notification
        if let firstRelevant = items.first(where: { $0.isAccepted }) {
            SpeechService.shared.speak(firstRelevant.content)
        }

        return items
    }

    // MARK: - Pass 2: Synthesize

    func synthesize() async {
        let pending = store.pendingAccepted()

        guard !pending.isEmpty else {
            Log.info(.extract, "Pass 2: no pending items, skipping")
            return
        }

        Log.info(.extract, "Pass 2 start: \(pending.count) pending accepted items")

        let currentWorld = worldModel.read()
        let currentTodos = todos.read()

        let dateStr: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date())
        }()

        // Group accepted items by bucket
        var byBucket: [ExtractionBucket: [ExtractionItem]] = [:]
        var todoItems: [ExtractionItem] = []

        for item in pending {
            if item.type == .todo {
                todoItems.append(item)
            }
            byBucket[item.bucket, default: []].append(item)
        }

        // Build bucket sections (facts only in per-bucket listing)
        let allBuckets: [ExtractionBucket] = [.projects, .people, .plans, .preferences, .decisions, .other]
        var bucketSections = ""
        for bucket in allBuckets {
            bucketSections += "[\(bucket.rawValue)]\n"
            let facts = (byBucket[bucket] ?? []).filter { $0.type == .fact }
            if facts.isEmpty {
                bucketSections += "(none)\n"
            } else {
                for item in facts {
                    bucketSections += "- \(item.content)\n"
                }
            }
            bucketSections += "\n"
        }

        // Build todos section
        var todosSection = ""
        if todoItems.isEmpty {
            todosSection = "(none)"
        } else {
            for item in todoItems {
                let pri = item.priority ?? "-"
                todosSection += "- \(pri): \(item.content)\n"
            }
        }

        let prompt = """
You maintain a user's world model and to-do list. Update them with the new information.

CURRENT WORLD MODEL:
\(currentWorld)

CURRENT TO-DO LIST:
\(currentTodos)

NEW ACCEPTED FACTS (\(dateStr)):
\(bucketSections)
NEW ACCEPTED TODOS:
\(todosSection)

Output ONLY the two XML blocks below. No explanation. No markdown. No extra text.
Start immediately with <WORLD_MODEL>.

<WORLD_MODEL>
[updated world model text here]
</WORLD_MODEL>
<TODOS>
[updated to-do list text here]
</TODOS>
"""

        let response: String
        do {
            response = try await ollama.generate(prompt: prompt, numPredict: 2048)
        } catch {
            Log.error(.extract, "Pass 2 Ollama error: \(error.localizedDescription)")
            return
        }

        let updatedWorld = extract(from: response, tag: "WORLD_MODEL")
        let updatedTodos = extract(from: response, tag: "TODOS")

        if updatedWorld == nil && updatedTodos == nil {
            let preview = String(response.prefix(200)).replacingOccurrences(of: "\n", with: " ")
            Log.error(.extract, "Pass 2: Ollama response missing XML tags. Preview: \(preview)")
            // Do NOT mark items applied — they will retry next synthesize call
            return
        }

        if let w = updatedWorld, !w.isEmpty {
            worldModel.write(w)
            Log.info(.world, "World model updated (\(w.count) chars)")
        } else if updatedWorld == nil {
            Log.warn(.extract, "Pass 2: WORLD_MODEL tag missing in response")
        }

        if let t = updatedTodos, !t.isEmpty {
            todos.write(t)
            Log.info(.todo, "Todos updated (\(t.count) chars)")
        } else if updatedTodos == nil {
            Log.warn(.extract, "Pass 2: TODOS tag missing in response")
        }

        let ids = pending.map { $0.id }
        store.markApplied(ids: ids)

        Log.info(.extract, "Pass 2 complete: \(pending.count) items applied")
        await cleanupService.cleanup()
    }

    // MARK: - Deprecated Stub

    /// Deprecated: use classifyChunk + synthesize instead.
    func process(transcript: String) async {
        Log.warn(.extract, "process() called — use classifyChunk/synthesize instead")
    }

    // MARK: - Private Helpers

    private func extract(from text: String, tag: String) -> String? {
        let openTag  = "<\(tag)>"
        let closeTag = "</\(tag)>"
        guard let openRange  = text.range(of: openTag),
              let closeRange = text.range(of: closeTag),
              openRange.upperBound < closeRange.lowerBound
        else { return nil }
        let content = String(text[openRange.upperBound..<closeRange.lowerBound])
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
