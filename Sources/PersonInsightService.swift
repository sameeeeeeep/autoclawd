import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - PersonInsightService
//
// Synthesises a 2–3 sentence insight about a person from their
// recent conversation summaries.
//
// Priority order:
//   1. Apple Foundation Models (on-device, macOS 26+ / Apple Intelligence)
//   2. Ollama local Llama 3.2 (localhost:11434)
//   3. Simple concatenation fallback (no LLM available)
//
// Results are cached in-memory keyed by (personID, contentHash) so the
// panel doesn't re-infer on every redraw.

actor PersonInsightService {

    static let shared = PersonInsightService()

    private var cache: [String: String] = [:]
    private let ollama = OllamaService()

    // MARK: - Public

    /// Returns a synthesised insight for `person` derived from `analyses`.
    /// Caller should `await` this and display the result asynchronously.
    func insight(personID: String, personName: String, analyses: [TranscriptAnalysis]) async -> String {
        guard !analyses.isEmpty else { return "" }

        let cacheKey = cacheKey(personID: personID, analyses: analyses)
        if let cached = cache[cacheKey] { return cached }

        let result = await generate(personName: personName, analyses: analyses)
        cache[cacheKey] = result
        return result
    }

    // MARK: - Private

    private func cacheKey(personID: String, analyses: [TranscriptAnalysis]) -> String {
        let ids = analyses.prefix(8).map { $0.id }.joined(separator: ",")
        return "\(personID):\(ids)"
    }

    private func generate(personName: String, analyses: [TranscriptAnalysis]) async -> String {
        let summaries = analyses
            .prefix(8)
            .map { $0.summary }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !summaries.isEmpty else { return "" }

        let bulletList = summaries.enumerated()
            .map { "- \($0.element)" }
            .joined(separator: "\n")

        let prompt = """
        Based on these recent conversation excerpts about \(personName), write 2–3 sentences \
        covering their current role or context, recurring priorities, and anything notable. \
        Do not start with "Based on" or "According to".

        \(bulletList)
        """

        #if canImport(FoundationModels)
        // ── Apple Foundation Models (on-device, Apple Intelligence) ──────────
        // Requires macOS 26+, Apple Intelligence enabled, Apple Silicon.
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            if case .available = model.availability {
                do {
                    let session = LanguageModelSession {
                        """
                        You are a concise personal assistant that summarises \
                        someone's recent conversations in 2–3 sentences. \
                        Be factual, direct, and human. Plain text only.
                        """
                    }
                    let response = try await session.respond(to: prompt)
                    let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { return text }
                } catch {
                    Log.warn(.system, "Foundation Models insight failed, falling back to Ollama: \(error)")
                }
            }
        }
        #endif

        // ── Ollama fallback ──────────────────────────────────────────────────
        do {
            let text = try await ollama.generate(prompt: prompt, numPredict: 200)
            // Strip any "Insight:" prefix the model might echo back
            let cleaned = text
                .replacingOccurrences(of: #"^Insight\s*\(.*?\)\s*:\s*"#,
                                      with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned
        } catch {
            Log.warn(.system, "Ollama insight failed: \(error)")
        }

        // ── Plain fallback ───────────────────────────────────────────────────
        return summaries.prefix(2).joined(separator: " ")
    }
}
