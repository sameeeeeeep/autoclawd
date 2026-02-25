import Foundation

// MARK: - QAService

final class QAService: @unchecked Sendable {
    private let ollama: OllamaService

    init(ollama: OllamaService) {
        self.ollama = ollama
    }

    func answer(question: String) async throws -> String {
        let prompt = """
Answer this question concisely in 1-3 sentences. If you don't know, say so.

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
