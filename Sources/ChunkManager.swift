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

/// Orchestrates the 5-minute always-on recording cycle.
/// Recording of chunk N+1 starts immediately when chunk N stops — seamless.
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

    private var chunkTimer: Task<Void, Never>?
    private var transcriptionService: TranscriptionService?
    private var extractionService: ExtractionService?
    private var transcriptStore: TranscriptStore?
    private var chunkStartTime: Date?

    let chunkDuration: TimeInterval  // configurable for testing

    init(chunkDuration: TimeInterval = 300) {
        self.chunkDuration = chunkDuration
    }

    // Dependencies injected after init to avoid circular refs
    func configure(
        transcriptionService: TranscriptionService,
        extractionService: ExtractionService,
        transcriptStore: TranscriptStore
    ) {
        self.transcriptionService = transcriptionService
        self.extractionService = extractionService
        self.transcriptStore = transcriptStore
    }

    // MARK: - Public API

    var audioLevel: Float { audioRecorder.audioLevel }

    func startListening() {
        guard case .stopped = state else { return }
        Log.info(.system, "ChunkManager: startListening() called")
        beginChunkCycle()
    }

    func stopListening() {
        chunkTimer?.cancel()
        chunkTimer = nil
        _ = audioRecorder.stopRecording()
        state = .stopped
        Log.info(.system, "ChunkManager: stopped")
    }

    func pause() {
        guard case .listening(let index) = state else { return }
        let silenceRatio = audioRecorder.silenceRatio
        let duration = Int(Date().timeIntervalSince(chunkStartTime ?? Date()))
        let savedURL = audioRecorder.stopRecording()
        chunkTimer?.cancel()
        chunkTimer = nil
        state = .paused
        Log.info(.system, "ChunkManager: paused at chunk \(index), \(duration)s recorded")

        // Process partial chunk if it has meaningful audio
        guard let savedURL, silenceRatio <= 0.90, duration > 3 else {
            if duration <= 3 {
                Log.info(.audio, "Chunk \(index) paused: too short (\(duration)s), skipping")
            } else {
                Log.info(.audio, "Chunk \(index) paused: \(Int(silenceRatio * 100))% silence, skipping")
            }
            return
        }

        let capturedTS = transcriptionService
        let capturedES = extractionService
        let capturedStore = transcriptStore

        Task.detached { [weak self] in
            await self?.processChunk(
                index: index,
                audioURL: savedURL,
                duration: max(duration, 1),
                transcriptionService: capturedTS,
                extractionService: capturedES,
                transcriptStore: capturedStore
            )
        }
    }

    func resume() {
        guard case .paused = state else { return }
        Log.info(.system, "ChunkManager: resuming")
        beginChunkCycle()
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

        // Start recording this chunk
        do {
            try audioRecorder.startRecording(outputURL: fileURL)
        } catch {
            Log.error(.audio, "Failed to start recording chunk \(index): \(error.localizedDescription)")
            try? await Task.sleep(for: .seconds(5))
            return
        }

        state = .listening(chunkIndex: index)
        chunkStartTime = Date()
        Log.info(.audio, "Chunk \(index) started → \(fileURL.lastPathComponent)")

        // Wait for chunk duration
        let started = Date()
        do {
            try await Task.sleep(for: .seconds(chunkDuration))
        } catch {
            // Task cancelled — clean up
            _ = audioRecorder.stopRecording()
            return
        }

        // Stop recording (seamless: next chunk starts in next loop iteration)
        let silenceRatio = audioRecorder.silenceRatio
        let duration = Int(Date().timeIntervalSince(started))
        guard let savedURL = audioRecorder.stopRecording() else { return }

        // File size
        let fileSizeMB = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))
            .flatMap { $0.fileSize }
            .map { Double($0) / 1_048_576 } ?? 0

        Log.info(.audio, "Chunk \(index) recorded: \(duration)s, \(String(format: "%.1f", fileSizeMB))MB, saved to \(fileURL.lastPathComponent)")

        // Silence detection
        if silenceRatio > 0.90 {
            Log.info(.audio, "Chunk \(index) skipped: \(Int(silenceRatio * 100))% silence")
            return
        }

        // Process this chunk in background (non-blocking — next chunk starts next loop)
        let capturedTranscriptionService = transcriptionService
        let capturedExtractionService = extractionService
        let capturedTranscriptStore = transcriptStore
        let capturedIndex = index

        Task.detached { [weak self] in
            await self?.processChunk(
                index: capturedIndex,
                audioURL: savedURL,
                duration: duration,
                transcriptionService: capturedTranscriptionService,
                extractionService: capturedExtractionService,
                transcriptStore: capturedTranscriptStore
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
        transcriptStore: TranscriptStore?
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

        await MainActor.run {
            self.onTranscriptReady?(transcript, audioURL)
        }

        // Run extraction (world model + todos) via Ollama
        guard let extractionService else {
            Log.warn(.extract, "No extraction service configured")
            return
        }

        Log.info(.extract, "Chunk \(index): starting extraction (Pass 1)")
        let items = await extractionService.classifyChunk(
            transcript: transcript,
            chunkIndex: index
        )
        await MainActor.run { self.onItemsClassified?(items) }

        // Purge old audio
        FileStorageManager.shared.purgeOldAudio(
            retentionDays: SettingsManager.shared.audioRetentionDays
        )
    }
}
