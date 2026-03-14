// Sources/GroqChatService.swift
import Foundation

// MARK: - GroqChatService

/// Groq text-generation client using the OpenAI-compatible Chat Completions API.
/// Reuses the same GROQ_API_KEY already used by SpeechService for Whisper transcription.
///
/// Target model: llama-3.3-70b-versatile
///   - 200+ tokens/sec on Groq's LPU hardware
///   - Much higher quality than local Llama 3.2 3B for nuanced screen understanding
///   - Used for: task/compose extraction in SuggestionPipeline, automation detection
///
/// Falls back gracefully — call sites check `isAvailable` first.
final class GroqChatService: @unchecked Sendable {

    static let shared = GroqChatService()

    private let endpoint  = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    private let model     = "llama-3.3-70b-versatile"
    private let timeout: TimeInterval = 30

    // MARK: - Availability

    /// Returns the Groq API key from env / keychain, or nil if not configured.
    var apiKey: String? {
        AppSettingsStorage.load(account: "groq_api_key_storage")
    }

    /// True when a Groq API key is present. Use before calling `complete()`.
    var isAvailable: Bool { apiKey != nil }

    // MARK: - Complete

    /// Sends a single-turn user prompt and returns the model's reply text.
    ///
    /// - Parameters:
    ///   - prompt: The user message to send.
    ///   - maxTokens: Max output tokens (default 512).
    ///   - temperature: Sampling temperature (default 0.2 for deterministic JSON output).
    func complete(prompt: String, maxTokens: Int = 512, temperature: Double = 0.2) async throws -> String {
        guard let key = apiKey else {
            throw GroqChatError.noAPIKey
        }

        let body: [String: Any] = [
            "model":       model,
            "messages":    [["role": "user", "content": prompt]],
            "max_tokens":  maxTokens,
            "temperature": temperature
        ]

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = timeout
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let t0 = Date()
        let (data, response) = try await URLSession.shared.data(for: req)
        let elapsed = Date().timeIntervalSince(t0)

        guard let http = response as? HTTPURLResponse else {
            throw GroqChatError.noResponse
        }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw GroqChatError.httpError(http.statusCode, msg)
        }

        guard let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"]   as? [[String: Any]],
              let first   = choices.first,
              let message = first["message"]  as? [String: Any],
              let content = message["content"] as? String
        else {
            throw GroqChatError.parseError
        }

        let usage  = json["usage"] as? [String: Any]
        let inTok  = usage?["prompt_tokens"]     as? Int ?? 0
        let outTok = usage?["completion_tokens"] as? Int ?? 0
        Log.info(.extract, "Groq \(model): \(String(format: "%.1f", elapsed))s, \(inTok) in → \(outTok) out")

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Errors

enum GroqChatError: LocalizedError {
    case noAPIKey
    case noResponse
    case httpError(Int, String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .noAPIKey:                   return "No Groq API key configured"
        case .noResponse:                 return "No response from Groq"
        case .httpError(let c, let m):    return "Groq HTTP \(c): \(m)"
        case .parseError:                 return "Could not parse Groq response"
        }
    }
}
