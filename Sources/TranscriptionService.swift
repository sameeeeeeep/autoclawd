import Foundation

// MARK: - TranscriptionService (Groq Whisper)

final class TranscriptionService: @unchecked Sendable {
    private let apiKey: String
    private let baseURL: String
    private let model = "whisper-large-v3"
    private let timeoutSeconds: TimeInterval = 30

    init(apiKey: String, baseURL: String = "https://api.groq.com/openai/v1") {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    static func validateAPIKey(_ key: String) async -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let url = URL(string: "https://api.groq.com/openai/v1/models") else { return false }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    func transcribe(fileURL: URL) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await self.transcribeAudio(fileURL: fileURL) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(self.timeoutSeconds * 1_000_000_000))
                throw TranscriptionError.timedOut(self.timeoutSeconds)
            }
            guard let result = try await group.next() else {
                throw TranscriptionError.failed("No result")
            }
            group.cancelAll()
            return result
        }
    }

    private func transcribeAudio(fileURL: URL) async throws -> String {
        guard let url = URL(string: "\(baseURL)/audio/transcriptions") else {
            throw TranscriptionError.failed("Invalid URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: fileURL)
        let body = makeMultipartBody(
            audioData: audioData,
            fileName: fileURL.lastPathComponent,
            boundary: boundary
        )

        let (data, response) = try await URLSession.shared.upload(for: req, from: body)
        guard let httpResp = response as? HTTPURLResponse else {
            throw TranscriptionError.failed("No HTTP response")
        }
        guard httpResp.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TranscriptionError.failed("HTTP \(httpResp.statusCode): \(body)")
        }
        return try parseText(from: data)
    }

    private func makeMultipartBody(audioData: Data, fileName: String, boundary: String) -> Data {
        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("\(model)\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: \(mimeType(for: fileName))\r\n\r\n")
        body.append(audioData)
        append("\r\n")
        append("--\(boundary)--\r\n")
        return body
    }

    private func mimeType(for fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "wav":  return "audio/wav"
        case "mp3":  return "audio/mpeg"
        case "m4a":  return "audio/mp4"
        default:     return "audio/wav"
        }
    }

    private func parseText(from data: Data) throws -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["text"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw TranscriptionError.failed("Could not parse response")
    }
}

// MARK: - Errors

enum TranscriptionError: LocalizedError {
    case timedOut(TimeInterval)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .timedOut(let s): return "Transcription timed out after \(Int(s))s"
        case .failed(let m):   return "Transcription failed: \(m)"
        }
    }
}
