import Foundation

// MARK: - OllamaService

/// Wraps the Ollama REST API (localhost:11434).
/// keep_alive=300 keeps the model loaded for 5 minutes after each call — eliminates cold-start penalty.
final class OllamaService: @unchecked Sendable {
    let baseURL: String
    let model: String
    private let timeoutSeconds: TimeInterval = 120

    init(baseURL: String = "http://localhost:11434", model: String = "llama3.2") {
        self.baseURL = baseURL
        self.model = model
    }

    // MARK: - Generate

    func generate(prompt: String, numPredict: Int = 512) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw OllamaError.invalidURL
        }

        let payload: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "keep_alive": 300,  // keep model loaded 5 min — eliminates cold-start on repeated calls
            "num_predict": numPredict
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = timeoutSeconds
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let t0 = Date()
        let (data, response) = try await URLSession.shared.data(for: req)
        let elapsed = Date().timeIntervalSince(t0)

        guard let httpResp = response as? HTTPURLResponse else {
            throw OllamaError.noResponse
        }
        guard httpResp.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OllamaError.httpError(httpResp.statusCode, body)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            throw OllamaError.parseError
        }

        let inputTokens  = (json["prompt_eval_count"] as? Int) ?? 0
        let outputTokens = (json["eval_count"] as? Int) ?? 0
        Log.info(.extract, "Ollama \(model): \(String(format: "%.1f", elapsed))s, \(inputTokens) in, \(outputTokens) out")

        return responseText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Health Check

    func isAvailable() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return false }
        do {
            let (_, resp) = try await URLSession.shared.data(from: url)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

// MARK: - Errors

enum OllamaError: LocalizedError {
    case invalidURL
    case noResponse
    case httpError(Int, String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .invalidURL:           return "Invalid Ollama URL"
        case .noResponse:           return "No response from Ollama"
        case .httpError(let c, let m): return "Ollama HTTP \(c): \(m)"
        case .parseError:           return "Could not parse Ollama response"
        }
    }
}
