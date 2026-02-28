import Foundation

// MARK: - WhatsAppPoller

/// Polls the WhatsApp sidecar for new messages every 2 seconds.
/// Routes voice notes through Groq transcription, then processes all messages
/// through the existing pipeline.
@MainActor
final class WhatsAppPoller: ObservableObject {

    @Published var recentMessages: [WhatsAppMessage] = []
    @Published var isPolling = false

    private let service = WhatsAppService.shared
    private var pollTimer: Timer?
    private var lastMessageTimestamp: TimeInterval = 0
    private weak var appState: AppState?

    /// Maximum messages to keep in the recent buffer.
    private let maxRecentMessages = 100

    init() {}

    // MARK: - Lifecycle

    func start(appState: AppState) {
        guard !isPolling else { return }
        self.appState = appState
        isPolling = true

        // Set cursor to now so we don't replay old messages
        lastMessageTimestamp = Date().timeIntervalSince1970

        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.poll()
            }
        }

        Log.info(.system, "[WhatsApp] Poller started")
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        isPolling = false
        Log.info(.system, "[WhatsApp] Poller stopped")
    }

    // MARK: - Polling

    private func poll() async {
        let messages = await service.getMessages(since: lastMessageTimestamp)
        guard !messages.isEmpty else { return }

        // Update cursor to latest message
        if let latest = messages.map({ $0.timestamp }).max() {
            lastMessageTimestamp = latest
        }

        for msg in messages {
            // Skip our own messages
            if msg.isFromMe { continue }

            var processedText = msg.text

            // Transcribe voice notes via Groq
            if msg.isVoiceNote, let mediaPath = msg.mediaPath {
                if let transcript = await transcribeVoiceNote(at: mediaPath) {
                    processedText = transcript
                    Log.info(.system, "[WhatsApp] Voice note transcribed: \(transcript.prefix(80))...")
                } else {
                    processedText = "[Voice note - transcription failed]"
                }
            }

            // Create a processed message for the UI
            let processed = WhatsAppMessage(
                id: msg.id,
                jid: msg.jid,
                sender: msg.sender,
                senderName: msg.senderName,
                text: processedText,
                timestamp: msg.timestamp,
                mediaPath: msg.mediaPath,
                isVoiceNote: msg.isVoiceNote,
                isFromMe: msg.isFromMe
            )

            recentMessages.append(processed)

            // Cap recent messages
            if recentMessages.count > maxRecentMessages {
                recentMessages = Array(recentMessages.suffix(maxRecentMessages / 2))
            }

            // Log the message
            Log.info(.system, "[WhatsApp] \(msg.senderName): \(processedText.prefix(100))")

            // Route through pipeline if we have an appState
            // The message text gets treated like a transcript chunk
            if let appState {
                await routeToPipeline(text: processedText, from: msg.senderName, appState: appState)
            }
        }
    }

    // MARK: - Voice Note Transcription

    /// Transcribe an OGG voice note file using the existing Groq Whisper API.
    private func transcribeVoiceNote(at path: String) async -> String? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            Log.warn(.system, "[WhatsApp] Voice note file not found: \(path)")
            return nil
        }

        let apiKey = SettingsManager.shared.groqAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            Log.warn(.system, "[WhatsApp] No Groq API key — cannot transcribe voice note")
            return nil
        }

        // Use Groq Whisper API directly for OGG transcription
        do {
            let transcript = try await transcribeWithGroq(fileURL: url, apiKey: apiKey)
            // Clean up the voice note file after successful transcription
            try? FileManager.default.removeItem(at: url)
            return transcript
        } catch {
            Log.warn(.system, "[WhatsApp] Transcription failed: \(error)")
            return nil
        }
    }

    /// Direct Groq Whisper API call for audio file transcription.
    private func transcribeWithGroq(fileURL: URL, apiKey: String) async throws -> String {
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent

        var body = Data()
        // File field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/ogg\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        // Model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-large-v3-turbo\r\n".data(using: .utf8)!)
        // Response format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("text\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let errMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw WhatsAppError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0, errMsg)
        }

        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - Pipeline Integration

    /// Route a WhatsApp message through the existing pipeline.
    private func routeToPipeline(text: String, from sender: String, appState: AppState) async {
        // Format as a labeled transcript for the pipeline
        let formatted = "[\(sender) via WhatsApp]: \(text)"
        Log.info(.system, "[WhatsApp → Pipeline] \(formatted.prefix(100))")

        // The pipeline orchestrator expects transcript text.
        // We feed WhatsApp messages as "cleaned transcripts" so they flow through
        // analysis → task creation → execution.
        // For now, log and let the existing ambient processing pick up context.
    }
}
