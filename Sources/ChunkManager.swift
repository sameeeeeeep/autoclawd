import AppKit
import AVFoundation
import Foundation

// MARK: - Chunk Manager State

enum ChunkManagerState: Equatable {
    case stopped
    case listening(chunkIndex: Int)
    case processing(chunkIndex: Int)
    case paused
}

// MARK: - ChunkManager

/// Orchestrates the sentence-aware 10–30s always-on recording cycle.
/// Flushes at natural silence boundaries (≥10s + 0.8s silence) or force-flushes at 30s.
/// Recording of chunk N+1 starts immediately after chunk N stops — seamless.
/// Processing (transcription + extraction) happens in a background Task.
@MainActor
final class ChunkManager: ObservableObject {

    @Published private(set) var state: ChunkManagerState = .stopped
    @Published private(set) var chunkIndex: Int = 0

    var onStateChange: ((ChunkManagerState) -> Void)?
    var onTranscriptReady: ((String, URL) -> Void)?
    var onItemsClassified: (([ExtractionItem]) -> Void)?

    private let audioRecorder = AudioRecorder()
    private let storage = FileStorageManager.shared
    private let settings = SettingsManager.shared

    private var currentSessionID: String?
    private let sessionStore = SessionStore.shared
    private let locationService = LocationService.shared

    private let minChunkSeconds: TimeInterval = 10
    private let maxChunkSeconds: TimeInterval = 30
    private let silenceGapSeconds: TimeInterval = 0.8
    private var transcriptBuffer: [String] = []

    private var chunkTimer: Task<Void, Never>?
    private var transcriptionService: TranscriptionService?
    private var extractionService: ExtractionService?
    private var transcriptStore: TranscriptStore?
    private var chunkStartTime: Date?

    var pillMode: PillMode = .ambientIntelligence
    var pasteService: TranscriptionPasteService?
    var qaService: QAService?
    var qaStore: QAStore?

    let chunkDuration: TimeInterval  // configurable for testing

    init(chunkDuration: TimeInterval = 30) {
        self.chunkDuration = chunkDuration
    }

    // Dependencies injected after init to avoid circular refs
    func configure(
        transcriptionService: TranscriptionService,
        extractionService: ExtractionService,
        transcriptStore: TranscriptStore,
        pasteService: TranscriptionPasteService,
        qaService: QAService,
        qaStore: QAStore
    ) {
        self.transcriptionService = transcriptionService
        self.extractionService    = extractionService
        self.transcriptStore      = transcriptStore
        self.pasteService         = pasteService
        self.qaService            = qaService
        self.qaStore              = qaStore
    }

    // MARK: - Public API

    var audioLevel: Float { audioRecorder.audioLevel }

    func startListening() {
        guard case .stopped = state else { return }
        Log.info(.system, "ChunkManager: startListening() called")
        beginChunkCycle()
        // Begin a new session row
        let ssid = locationService.currentSSID
        currentSessionID = sessionStore.beginSession(wifiSSID: ssid)
    }

    func stopListening() {
        chunkTimer?.cancel()
        chunkTimer = nil
        _ = audioRecorder.stopRecording()
        // End the session
        if let sid = currentSessionID {
            sessionStore.endSession(id: sid, transcriptSnippet: latestTranscriptSnippet())
            currentSessionID = nil
        }
        transcriptBuffer.removeAll()
        state = .stopped
        Log.info(.system, "ChunkManager: stopped")
    }

    func pause() {
        guard case .listening(let index) = state else { return }
        // End the session on pause
        if let sid = currentSessionID {
            sessionStore.endSession(id: sid, transcriptSnippet: latestTranscriptSnippet())
            currentSessionID = nil
        }
        transcriptBuffer.removeAll()
        let silenceRatio = audioRecorder.silenceRatio
        let duration = Int(Date().timeIntervalSince(chunkStartTime ?? Date()))
        let savedURL = audioRecorder.stopRecording()
        chunkTimer?.cancel()
        chunkTimer = nil
        state = .paused
        Log.info(.system, "ChunkManager: paused at chunk \(index), \(duration)s recorded")

        // Process partial chunk if it has meaningful audio
        guard let savedURL, silenceRatio <= 0.90, duration >= 2 else {
            if duration < 2 {
                Log.info(.audio, "Chunk \(index) paused: too short (\(duration)s), skipping")
            } else {
                Log.info(.audio, "Chunk \(index) paused: \(Int(silenceRatio * 100))% silence, skipping")
            }
            return
        }

        let capturedTS = transcriptionService
        let capturedES = extractionService
        let capturedStore = transcriptStore
        let capturedPillMode     = pillMode
        let capturedPasteService = pasteService
        let capturedQAService    = qaService
        let capturedQAStore      = qaStore

        Task.detached { [weak self] in
            await self?.processChunk(
                index: index,
                audioURL: savedURL,
                duration: max(duration, 1),
                transcriptionService: capturedTS,
                extractionService: capturedES,
                transcriptStore: capturedStore,
                pillMode: capturedPillMode,
                pasteService: capturedPasteService,
                qaService: capturedQAService,
                qaStore: capturedQAStore
            )
        }
    }

    func resume() {
        guard case .paused = state else { return }
        Log.info(.system, "ChunkManager: resuming")
        // Start a fresh session on resume
        let ssid = locationService.currentSSID
        currentSessionID = sessionStore.beginSession(wifiSSID: ssid)
        beginChunkCycle()
    }

    // MARK: - Session Helpers

    private func latestTranscriptSnippet() -> String {
        let combined = transcriptBuffer.suffix(3).joined(separator: " ")
        return String(combined.prefix(120))
    }

    // MARK: - Chunk Cycle

    private func beginChunkCycle() {
        chunkTimer = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.runOneChunk()
            }
        }
    }

    private func runOneChunk() async {
        let index = chunkIndex
        chunkIndex += 1
        let fileURL = storage.audioFile(date: Date())

        do {
            try audioRecorder.startRecording(outputURL: fileURL)
        } catch {
            Log.error(.audio, "Failed to start recording chunk \(index): \(error.localizedDescription)")
            try? await Task.sleep(for: .seconds(5))
            return
        }

        state = .listening(chunkIndex: index)
        let chunkStart = Date()
        chunkStartTime = chunkStart
        Log.info(.audio, "Chunk \(index) started → \(fileURL.lastPathComponent)")

        var silenceStart: Date? = nil
        var elapsed: TimeInterval = 0

        // Poll every 0.25s — flush on silence-after-minChunk or hard cap at maxChunk
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            elapsed = Date().timeIntervalSince(chunkStart)

            let silent = audioRecorder.isSilentNow

            if silent {
                if silenceStart == nil { silenceStart = Date() }
            } else {
                silenceStart = nil
            }

            let silenceDuration = silenceStart.map { Date().timeIntervalSince($0) } ?? 0
            let shouldFlushForSilence = elapsed >= minChunkSeconds && silenceDuration >= silenceGapSeconds
            let shouldForceFlush = elapsed >= maxChunkSeconds

            if shouldFlushForSilence || shouldForceFlush {
                let reason = shouldForceFlush
                    ? "force(\(Int(elapsed))s)"
                    : "silence(\(String(format: "%.1f", elapsed))s)"
                Log.info(.audio, "Chunk \(index): flushing — \(reason)")
                break
            }
        }

        // Stop recording
        let silenceRatio = audioRecorder.silenceRatio
        let duration = Int(elapsed)
        guard let savedURL = audioRecorder.stopRecording() else { return }

        let fileSizeMB = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))
            .flatMap { $0.fileSize }
            .map { Double($0) / 1_048_576 } ?? 0

        Log.info(.audio, "Chunk \(index) recorded: \(duration)s, \(String(format: "%.1f", fileSizeMB))MB")

        // Skip near-silence chunks
        if silenceRatio > 0.90 || duration < 2 {
            Log.info(.audio, "Chunk \(index) skipped: \(Int(silenceRatio * 100))% silence / \(duration)s")
            return
        }

        // Dispatch background processing (unchanged from before)
        let capturedIndex = index
        let capturedTranscriptionService = transcriptionService
        let capturedExtractionService = extractionService
        let capturedTranscriptStore = transcriptStore
        let capturedPillMode = pillMode
        let capturedPasteService = pasteService
        let capturedQAService = qaService
        let capturedQAStore = qaStore

        Task.detached { [weak self] in
            await self?.processChunk(
                index: capturedIndex,
                audioURL: savedURL,
                duration: max(duration, 1),
                transcriptionService: capturedTranscriptionService,
                extractionService: capturedExtractionService,
                transcriptStore: capturedTranscriptStore,
                pillMode: capturedPillMode,
                pasteService: capturedPasteService,
                qaService: capturedQAService,
                qaStore: capturedQAStore
            )
        }
    }

    // MARK: - Background Processing

    private func processChunk(
        index: Int,
        audioURL: URL,
        duration: Int,
        transcriptionService: TranscriptionService?,
        extractionService: ExtractionService?,
        transcriptStore: TranscriptStore?,
        pillMode: PillMode,
        pasteService: TranscriptionPasteService?,
        qaService: QAService?,
        qaStore: QAStore?
    ) async {
        guard let transcriptionService else {
            Log.warn(.transcribe, "No transcription service configured")
            return
        }

        Log.info(.transcribe, "Chunk \(index): starting transcription")

        let transcript: String
        do {
            let t0 = Date()
            transcript = try await transcriptionService.transcribe(fileURL: audioURL)
            let elapsed = Date().timeIntervalSince(t0)
            let wordCount = transcript.split(separator: " ").count
            let preview = String(transcript.prefix(60))
            Log.info(.transcribe, "Chunk \(index): \(String(format: "%.1f", elapsed))s, \(wordCount) words — '\(preview)'")
        } catch {
            Log.error(.transcribe, "Chunk \(index) transcription failed: \(error.localizedDescription)")
            return
        }

        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Log.info(.transcribe, "Chunk \(index): empty transcript, skipping extraction")
            return
        }

        // Save transcript to SQLite
        transcriptStore?.save(
            text: transcript,
            durationSeconds: duration,
            audioFilePath: audioURL.path
        )

        // Resolve SSID on main actor, then do SQLite work off main actor
        let (currentSID, ssid) = await MainActor.run { (self.currentSessionID, self.locationService.currentSSID) }
        let placeID = ssid.flatMap { SessionStore.shared.findPlace(wifiSSID: $0)?.id }
        if let sid = currentSID, let pid = placeID {
            SessionStore.shared.updateSessionPlace(id: sid, placeID: pid)
        }

        await MainActor.run {
            self.onTranscriptReady?(transcript, audioURL)
            self.transcriptBuffer.append(transcript)
        }

        switch pillMode {
        case .ambientIntelligence:
            guard let extractionService else {
                Log.warn(.extract, "No extraction service configured")
                break
            }
            Log.info(.extract, "Chunk \(index): starting extraction (Pass 1)")
            let items = await extractionService.classifyChunk(
                transcript: transcript,
                chunkIndex: index
            )
            await MainActor.run { self.onItemsClassified?(items) }

        case .transcription:
            guard let pasteService else { break }
            await MainActor.run { pasteService.paste(text: transcript) }

        case .aiSearch:
            guard let qaService, let qaStore else { break }
            do {
                let answer = try await qaService.answer(question: transcript)
                await MainActor.run {
                    qaStore.append(question: transcript, answer: answer)
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(answer, forType: .string)
                    Log.info(.qa, "Answer copied to clipboard")
                }
            } catch {
                Log.error(.qa, "QA failed: \(error.localizedDescription)")
            }
        }

        // Purge old audio
        FileStorageManager.shared.purgeOldAudio(
            retentionDays: SettingsManager.shared.audioRetentionDays
        )
    }
}
