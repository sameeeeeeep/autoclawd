import Foundation

// MARK: - TranscriptCleaningService

/// Stage 1: Detects continued transcripts, merges chunks, and cleans text via LLM.
/// Multiple raw transcript chunks from the same session → one cleaned transcript.
final class TranscriptCleaningService: @unchecked Sendable {
    private let ollama: OllamaService
    private let transcriptStore: TranscriptStore
    private let pipelineStore: PipelineStore
    private let skillStore: SkillStore

    /// Tracks pending chunks per session for continued transcript merging.
    /// Key: sessionID, Value: list of (transcriptID, chunkSeq, text, duration, speakerName).
    private var pendingChunks: [String: [(id: Int64, seq: Int, text: String, duration: Int, speaker: String?)]] = [:]
    private let pendingLock = DispatchQueue(label: "com.autoclawd.cleaning.pending")

    /// How long to wait for more chunks before processing (seconds).
    private let mergeWindow: TimeInterval = 3.0

    init(ollama: OllamaService, transcriptStore: TranscriptStore,
         pipelineStore: PipelineStore, skillStore: SkillStore) {
        self.ollama = ollama
        self.transcriptStore = transcriptStore
        self.pipelineStore = pipelineStore
        self.skillStore = skillStore
    }

    // MARK: - Public API

    /// Process a new transcript chunk. Handles continued detection and cleaning.
    func processNewTranscript(
        text: String,
        transcriptID: Int64,
        sessionID: String?,
        sessionChunkSeq: Int,
        durationSeconds: Int,
        speakerName: String?
    ) async -> CleanedTranscript? {
        // If this chunk is part of a session, check for continuation
        if let sid = sessionID {
            pendingLock.sync {
                pendingChunks[sid, default: []].append((
                    id: transcriptID, seq: sessionChunkSeq,
                    text: text, duration: durationSeconds, speaker: speakerName
                ))
            }

            // If this is a continuation chunk (seq > 0), wait for more chunks
            if sessionChunkSeq > 0 {
                try? await Task.sleep(for: .seconds(mergeWindow))
            }

            // Gather all pending chunks for this session
            let chunks = pendingLock.sync { pendingChunks[sid] ?? [] }

            // If more chunks arrived after us, a later chunk will handle the merge
            let maxSeq = chunks.max(by: { $0.seq < $1.seq })?.seq ?? 0
            if sessionChunkSeq < maxSeq {
                return nil // A later chunk will merge all of them
            }

            // We're the latest chunk — merge and clean
            pendingLock.sync { pendingChunks.removeValue(forKey: sid) }

            let sortedChunks = chunks.sorted { $0.seq < $1.seq }
            let isContinued = sortedChunks.count > 1
            let mergedText = sortedChunks.map(\.text).joined(separator: " ")
            let sourceIDs = sortedChunks.map(\.id)
            let totalDuration = sortedChunks.reduce(0) { $0 + $1.duration }
            let speaker = sortedChunks.first?.speaker

            return await cleanAndStore(
                rawText: mergedText,
                sourceTranscriptIDs: sourceIDs,
                isContinued: isContinued,
                chunkCount: sortedChunks.count,
                sessionID: sid,
                durationSeconds: totalDuration,
                speakerName: speaker
            )
        } else {
            // No session — clean as single chunk
            return await cleanAndStore(
                rawText: text,
                sourceTranscriptIDs: [transcriptID],
                isContinued: false,
                chunkCount: 1,
                sessionID: nil,
                durationSeconds: durationSeconds,
                speakerName: speakerName
            )
        }
    }

    // MARK: - Private

    private func cleanAndStore(
        rawText: String,
        sourceTranscriptIDs: [Int64],
        isContinued: Bool,
        chunkCount: Int,
        sessionID: String?,
        durationSeconds: Int,
        speakerName: String?
    ) async -> CleanedTranscript? {
        let cleanedText = await cleanWithLLM(rawText: rawText)

        guard !cleanedText.isEmpty else {
            Log.warn(.cleaning, "Cleaning produced empty output for \(sourceTranscriptIDs)")
            return nil
        }

        let ct = CleanedTranscript(
            id: UUID().uuidString,
            sessionID: sessionID,
            sourceTranscriptIDs: sourceTranscriptIDs,
            isContinued: isContinued,
            sourceChunkCount: chunkCount,
            cleanedText: cleanedText,
            timestamp: Date(),
            speakerName: speakerName,
            durationSeconds: durationSeconds
        )

        pipelineStore.insertCleanedTranscript(ct)

        let label = isContinued ? "\(chunkCount) chunks merged" : "single chunk"
        Log.info(.cleaning, "Stage 1 done: \(label), \(cleanedText.count) chars cleaned")

        return ct
    }

    private func cleanWithLLM(rawText: String) async -> String {
        // Load prompt template from skill (user-editable)
        let skill = skillStore.load(id: "transcript-cleaning")
        let template = skill?.promptTemplate ?? """
            Clean this spoken transcript. Remove filler words (um, uh, like, you know, so, basically), fix grammar, merge broken sentences. Keep ALL meaning. Output ONLY the cleaned text.

            RAW TRANSCRIPT:
            {{transcript}}

            CLEANED:
            """

        let prompt = template.replacingOccurrences(of: "{{transcript}}", with: rawText)

        do {
            let response = try await ollama.generate(prompt: prompt, numPredict: 512)
            let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
            // Fallback: if LLM returns empty or very short, use raw text
            if cleaned.count < 5 {
                Log.warn(.cleaning, "LLM returned too short, using raw text")
                return rawText
            }
            return cleaned
        } catch {
            Log.error(.cleaning, "LLM cleaning failed: \(error.localizedDescription), using raw text")
            return rawText
        }
    }
}
