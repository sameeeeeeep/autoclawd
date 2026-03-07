import Foundation

// MARK: - CleaningLevel

/// Controls how aggressively transcript text is cleaned.
enum CleaningLevel: String, CaseIterable, Identifiable {
    case raw = "raw"
    case minimal = "minimal"
    case polished = "polished"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .raw:      return "Raw"
        case .minimal:  return "Clean"
        case .polished: return "Polished"
        }
    }

    var description: String {
        switch self {
        case .raw:      return "Unprocessed transcript"
        case .minimal:  return "Grammar fixed, fillers removed"
        case .polished: return "Coherent, well-structured"
        }
    }

    var index: Int {
        switch self {
        case .raw:      return 1
        case .minimal:  return 2
        case .polished: return 3
        }
    }

    static func fromIndex(_ i: Int) -> CleaningLevel? {
        switch i {
        case 1: return .raw
        case 2: return .minimal
        case 3: return .polished
        default: return nil
        }
    }
}

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
    private let pendingLock = NSLock()

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

    /// Clean raw text at a specific quality level. Used for multi-pass transcript cleaning.
    /// Returns the cleaned text (or raw text on failure).
    func cleanAtLevel(rawText: String, level: CleaningLevel) async -> String {
        switch level {
        case .raw:
            return rawText
        case .minimal:
            return await cleanWithLLM(rawText: rawText)
        case .polished:
            return await cleanPolished(rawText: rawText)
        }
    }

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
            pendingLock.withLock {
                pendingChunks[sid, default: []].append((
                    id: transcriptID, seq: sessionChunkSeq,
                    text: text, duration: durationSeconds, speaker: speakerName
                ))
            }

            // Always wait the merge window so consecutive force-flushed chunks (e.g. back-to-back
            // 30s auto-chunks) can accumulate before we decide who merges them.
            try? await Task.sleep(for: .seconds(mergeWindow))

            // Gather all pending chunks for this session
            let chunks = pendingLock.withLock { pendingChunks[sid] ?? [] }

            // If more chunks arrived after us, a later chunk will handle the merge
            let maxSeq = chunks.max(by: { $0.seq < $1.seq })?.seq ?? 0
            if sessionChunkSeq < maxSeq {
                return nil // A later chunk will merge all of them
            }

            // We're the latest chunk — merge and clean
            _ = pendingLock.withLock { pendingChunks.removeValue(forKey: sid) }

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

    private func cleanPolished(rawText: String) async -> String {
        let prompt = """
            Rewrite this spoken transcript for better readability. \
            Fix grammar, remove filler words, and improve sentence flow where it helps clarity. \
            Keep the same vocabulary and tone — do NOT make it formal or flowery. \
            Preserve ALL meaning and details exactly. \
            Output ONLY the rewritten text, nothing else.

            RAW TRANSCRIPT:
            \(rawText)

            POLISHED:
            """

        do {
            let response = try await ollama.generate(prompt: prompt, numPredict: 1024)
            let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.count < 5 {
                Log.warn(.cleaning, "Polished cleaning returned too short, using raw text")
                return rawText
            }
            return cleaned
        } catch {
            Log.error(.cleaning, "Polished cleaning failed: \(error.localizedDescription), using raw text")
            return rawText
        }
    }

    private func cleanWithLLM(rawText: String) async -> String {
        // Load prompt template from skill (user-editable)
        let skill = skillStore.load(id: "transcript-cleaning")
        let template = skill?.promptTemplate ?? """
            Fix only grammar, spelling, and punctuation in this spoken transcript. \
            Do NOT remove words, change vocabulary, reorder sentences, or alter meaning in any way. \
            Output ONLY the corrected text, nothing else.

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
