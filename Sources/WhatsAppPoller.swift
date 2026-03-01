import Foundation

// MARK: - WhatsAppPoller

/// Polls the WhatsApp sidecar for new messages every 2 seconds.
/// Routes voice notes through the app's selected transcription engine,
/// then processes all messages through the existing pipeline.
@MainActor
final class WhatsAppPoller: ObservableObject {

    @Published var recentMessages: [WhatsAppMessage] = []
    @Published var isPolling = false

    private let service = WhatsAppService.shared
    private var pollTimer: Timer?
    private var lastMessageTimestamp: TimeInterval = 0
    private weak var appState: AppState?

    /// IDs of messages we've already processed (prevents double-processing and bot reply loops).
    private var processedMessageIDs: Set<String> = []
    /// Prevents concurrent polls (QA can take >2s, overlapping polls cause loops).
    private var isPollInProgress = false

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

        // Ensure myJID is set — fetch from health if needed
        Task { @MainActor in
            await ensureMyJID()
        }

        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.poll()
            }
        }

        Log.info(.system, "[WhatsApp] Poller started")
    }

    /// Make sure whatsAppMyJID is populated — fetch from sidecar health if not.
    private func ensureMyJID() async {
        let existing = SettingsManager.shared.whatsAppMyJID
        if !existing.isEmpty { return }

        // Poll health up to 10 times until we get the phone number
        for _ in 1...10 {
            let (status, phone) = await service.checkHealth()
            if let phone, !phone.isEmpty {
                SettingsManager.shared.whatsAppMyJID = phone
                Log.info(.system, "[WhatsApp] myJID set to \(phone)")
                return
            }
            if status == .connected { break } // connected but no phone? shouldn't happen
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
        }
        Log.warn(.system, "[WhatsApp] Could not determine phone number for self-chat filtering")
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        isPolling = false
        Log.info(.system, "[WhatsApp] Poller stopped")
    }

    // MARK: - Polling

    private func poll() async {
        // Prevent re-entrant polls — QA reply can take >2s, timer keeps firing
        guard !isPollInProgress else { return }
        isPollInProgress = true
        defer { isPollInProgress = false }

        let messages = await service.getMessages(since: lastMessageTimestamp)
        guard !messages.isEmpty else { return }

        // Update cursor to latest message
        if let latest = messages.map({ $0.timestamp }).max() {
            lastMessageTimestamp = latest
        }

        // Only accept messages from "Message Yourself" chat (self-chat).
        // All other conversations are ignored until we build out full messaging.
        let myJID = SettingsManager.shared.whatsAppMyJID
        guard !myJID.isEmpty else {
            Log.warn(.system, "[WhatsApp] whatsAppMyJID not set — can't filter self-chat messages")
            return
        }

        // Exact self-chat JID: must be a personal chat (@s.whatsapp.net) with our number
        let selfChatJID = "\(myJID)@s.whatsapp.net"

        for msg in messages {
            // Reject group chats and broadcast lists — must be a personal JID
            guard msg.jid.hasSuffix("@s.whatsapp.net") else { continue }
            // Only process messages in the self-chat conversation (exact match)
            guard msg.jid == selfChatJID else { continue }

            // Skip already-processed messages (prevents bot reply infinite loops)
            guard !processedMessageIDs.contains(msg.id) else { continue }
            processedMessageIDs.insert(msg.id)

            // Cap the processed IDs set so it doesn't grow forever
            if processedMessageIDs.count > 500 {
                processedMessageIDs = Set(processedMessageIDs.suffix(250))
            }

            var processedText = msg.text

            // Transcribe voice notes using the app's selected transcription engine
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

            // Process via QA assistant (reply) + pipeline (task creation) in parallel
            if let appState {
                let jid = msg.jid
                await handleMessage(text: processedText, from: msg.senderName, jid: jid, appState: appState)
            }
        }
    }

    // MARK: - Voice Note Transcription

    /// Transcribe a voice note file using whatever transcription engine is selected in Settings
    /// (Groq Whisper or Local SFSpeechRecognizer).
    /// WhatsApp voice notes arrive as OGG — Groq handles this natively, but Local mode
    /// (SFSpeechRecognizer) needs conversion to WAV first.
    private func transcribeVoiceNote(at path: String) async -> String? {
        let fileURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            Log.warn(.system, "[WhatsApp] Voice note file not found: \(path)")
            return nil
        }

        guard let transcriber = appState?.transcriptionService else {
            Log.warn(.system, "[WhatsApp] No transcription service available — check transcription settings")
            return nil
        }

        Log.info(.system, "[WhatsApp] Transcribing voice note with \(transcriber.modelName)...")

        // For local SFSpeechRecognizer, OGG isn't supported — convert to WAV first
        let isLocal = transcriber.modelName.contains("local") || transcriber.modelName.contains("SFSpeech")
        var transcribeURL = fileURL
        var tempWAV: URL? = nil

        if isLocal {
            if let wav = convertOGGtoWAV(oggURL: fileURL) {
                transcribeURL = wav
                tempWAV = wav
            } else {
                Log.warn(.system, "[WhatsApp] Failed to convert OGG to WAV for local transcription")
                return nil
            }
        }

        do {
            let transcript = try await transcriber.transcribe(fileURL: transcribeURL)
            // Clean up voice note + temp WAV after successful transcription
            try? FileManager.default.removeItem(at: fileURL)
            if let wav = tempWAV { try? FileManager.default.removeItem(at: wav) }
            return transcript
        } catch {
            Log.warn(.system, "[WhatsApp] Transcription failed (\(transcriber.modelName)): \(error)")
            if let wav = tempWAV { try? FileManager.default.removeItem(at: wav) }
            return nil
        }
    }

    /// Convert OGG voice note to WAV using macOS `afconvert` (available on all Macs).
    private func convertOGGtoWAV(oggURL: URL) -> URL? {
        let wavURL = oggURL.deletingPathExtension().appendingPathExtension("wav")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        proc.arguments = [
            "-f", "WAVE",   // output format
            "-d", "LEI16",  // 16-bit PCM
            oggURL.path,
            wavURL.path,
        ]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()

        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0 {
                return wavURL
            }
            // afconvert may not handle OGG — try ffmpeg as fallback
            return convertOGGtoWAVWithFFmpeg(oggURL: oggURL, wavURL: wavURL)
        } catch {
            return convertOGGtoWAVWithFFmpeg(oggURL: oggURL, wavURL: wavURL)
        }
    }

    /// Fallback: use ffmpeg if available.
    private func convertOGGtoWAVWithFFmpeg(oggURL: URL, wavURL: URL) -> URL? {
        // Check common ffmpeg locations
        let ffmpegPaths = ["/usr/local/bin/ffmpeg", "/opt/homebrew/bin/ffmpeg"]
        guard let ffmpeg = ffmpegPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            Log.warn(.system, "[WhatsApp] Neither afconvert nor ffmpeg can convert OGG — install ffmpeg or use Groq transcription")
            return nil
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ffmpeg)
        proc.arguments = ["-i", oggURL.path, "-y", wavURL.path]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()

        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0 ? wavURL : nil
        } catch {
            return nil
        }
    }

    // MARK: - Message Handling (QA Reply + Pipeline)

    /// Handle a WhatsApp message: reply via QA assistant and feed into pipeline.
    private func handleMessage(text: String, from sender: String, jid: String, appState: AppState) async {
        // 1. Reply via QA assistant
        await replyViaQA(text: text, jid: jid, appState: appState)

        // 2. Feed into pipeline for task creation (background)
        await feedPipeline(text: text, from: sender, appState: appState)
    }

    /// Use QAService to generate an answer and send it back via WhatsApp.
    private func replyViaQA(text: String, jid: String, appState: AppState) async {
        do {
            let context = await appState.buildQAContext()
            let answer = try await appState.qaService.answer(question: text, context: context, speak: false)

            guard !answer.isEmpty else {
                Log.warn(.system, "[WhatsApp → QA] Empty answer")
                return
            }

            Log.info(.system, "[WhatsApp → QA] Reply: \(answer.prefix(100))...")

            // Send reply back via WhatsApp with "Dot:" prefix
            try await WhatsAppService.shared.sendMessage(jid: jid, text: "Dot: \(answer)")
            // Bump cursor to skip the bot's own reply in the next poll
            lastMessageTimestamp = Date().timeIntervalSince1970
            Log.info(.system, "[WhatsApp] Reply sent to \(jid)")

            // Store in QA history
            await MainActor.run {
                appState.qaStore.append(question: text, answer: answer)
            }
        } catch {
            Log.warn(.system, "[WhatsApp → QA] Failed: \(error)")
            // Send error message back so user knows something went wrong
            try? await WhatsAppService.shared.sendMessage(
                jid: jid,
                text: "Dot: ⚠️ Sorry, I couldn't process that. Error: \(error.localizedDescription)"
            )
        }
    }

    /// Save transcript and feed through pipeline for task creation.
    private func feedPipeline(text: String, from sender: String, appState: AppState) async {
        let formatted = "[\(sender) via WhatsApp]: \(text)"
        Log.info(.system, "[WhatsApp → Pipeline] \(formatted.prefix(100))")

        let transcriptID = appState.transcriptStore.saveSync(
            text: formatted,
            durationSeconds: 0,
            audioFilePath: "",
            sessionID: "whatsapp-\(Date().timeIntervalSince1970)",
            sessionChunkSeq: 0,
            speakerName: sender
        )

        guard let tid = transcriptID else {
            Log.warn(.system, "[WhatsApp → Pipeline] Failed to save transcript")
            return
        }

        await appState.pipelineOrchestrator.processTranscript(
            text: formatted,
            transcriptID: tid,
            sessionID: "whatsapp",
            sessionChunkSeq: 0,
            durationSeconds: 0,
            speakerName: sender,
            source: .whatsapp
        )

        await MainActor.run {
            appState.refreshPipeline()
        }
    }
}
