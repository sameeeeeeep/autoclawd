import Foundation

// MARK: - QAService

final class QAService: @unchecked Sendable {
    private let ollama: OllamaService

    init(ollama: OllamaService) {
        self.ollama = ollama
    }

    func answer(question: String) async throws -> String {
        let contextBlock = SessionStore.shared.buildContextBlock(
            currentSSID: await MainActor.run { LocationService.shared.currentSSID }
        )
        let contextPrefix = contextBlock.isEmpty ? "" : "\(contextBlock)\n\n---\n\n"
        let prompt = """
\(contextPrefix)Answer this question concisely in 1-3 sentences. If you don't know, say so.

Question: \(question)
"""
        Log.info(.qa, "Question: \"\(question)\"")
        let t0 = Date()
        let answer = try await ollama.generate(prompt: prompt, numPredict: 512)
        let elapsed = Date().timeIntervalSince(t0)
        Log.info(.qa, "Answer in \(String(format: "%.1f", elapsed))s: \"\(String(answer.prefix(80)))\"")
        return answer
    }
}
