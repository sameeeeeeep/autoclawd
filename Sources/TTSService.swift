import Foundation

// MARK: - TTSService

/// HTTP client for the LuxTTS Python sidecar running on localhost:7893.
/// Follows the same pattern as WhatsAppService.
final class TTSService: @unchecked Sendable {
    static let shared = TTSService()

    private let baseURL: String
    private let session: URLSession

    init(baseURL: String = TTSSidecar.baseURL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 90
        self.session = URLSession(configuration: config)
    }

    // MARK: - Health

    /// Check sidecar health. Returns (isReachable, status, availableVoiceIDs).
    /// Status can be "idle" (model not loaded), "loading", "ready", or "error".
    func checkHealth() async -> (Bool, [String]) {
        guard let url = URL(string: "\(baseURL)/health") else { return (false, []) }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return (false, [])
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["status"] as? String,
               let voices = json["voices"] as? [String] {
                // "idle" or "ready" both mean the sidecar is reachable and can accept requests
                // (idle = model not loaded yet, will lazy-load on first synthesize)
                let reachable = status == "ready" || status == "idle"
                return (reachable, voices)
            }
            return (false, [])
        } catch {
            return (false, [])
        }
    }

    // MARK: - Unload

    /// Ask the sidecar to unload the model and free RAM.
    func unloadModel() async {
        guard let url = URL(string: "\(baseURL)/unload") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        _ = try? await session.data(for: request)
    }

    // MARK: - Synthesize

    /// Synthesize text to WAV audio data using the specified voice.
    /// Returns nil on failure (network error, sidecar unavailable, etc.).
    func synthesize(text: String, voiceID: String, speed: Float = 1.0) async -> Data? {
        guard let url = URL(string: "\(baseURL)/synthesize") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "text": text,
            "voice_id": voiceID,
            "speed": speed,
            "num_steps": 2,
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                Log.warn(.system, "[TTSService] synthesize: no HTTP response")
                return nil
            }
            guard http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                Log.warn(.system, "[TTSService] synthesize failed HTTP \(http.statusCode): \(body.prefix(200))")
                return nil
            }
            return data
        } catch {
            Log.warn(.system, "[TTSService] synthesize error: \(error)")
            return nil
        }
    }

    // MARK: - Batch Synthesize

    struct BatchTurn {
        let text: String
        let voiceID: String
    }

    /// Synthesize multiple turns in one request. Different voices run in parallel server-side.
    /// Returns audio Data per turn (in order); nil entries indicate a failed turn.
    func synthesizeBatch(turns: [BatchTurn], speed: Float = 1.0) async -> [Data?] {
        guard !turns.isEmpty else { return [] }
        guard let url = URL(string: "\(baseURL)/synthesize_batch") else { return Array(repeating: nil, count: turns.count) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Batch can take N * per-turn seconds; give plenty of room
        request.timeoutInterval = Double(turns.count) * 45

        let turnsPayload = turns.map { ["text": $0.text, "voice_id": $0.voiceID] }
        let payload: [String: Any] = [
            "turns": turnsPayload,
            "num_steps": 2,
            "speed": speed,
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                Log.warn(.system, "[TTSService] synthesizeBatch failed HTTP \(code): \(body.prefix(200))")
                return Array(repeating: nil, count: turns.count)
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let audioList = json["audio"] as? [String] else {
                Log.warn(.system, "[TTSService] synthesizeBatch: invalid response")
                return Array(repeating: nil, count: turns.count)
            }
            return audioList.map { b64 in Data(base64Encoded: b64) }
        } catch {
            Log.warn(.system, "[TTSService] synthesizeBatch error: \(error)")
            return Array(repeating: nil, count: turns.count)
        }
    }

    // MARK: - Voices

    struct TTSVoice: Codable {
        let id: String
        let name: String
        let has_reference: Bool
        let is_encoded: Bool
    }

    /// List available voices from the sidecar.
    func voices() async -> [TTSVoice] {
        guard let url = URL(string: "\(baseURL)/voices") else { return [] }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            return (try? JSONDecoder().decode([TTSVoice].self, from: data)) ?? []
        } catch {
            return []
        }
    }
}
