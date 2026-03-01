import Foundation

// MARK: - PipelineOrchestrator

/// Central coordinator for the multi-stage pipeline.
/// Called by ChunkManager instead of ExtractionService.classifyChunk().
///
/// Pipeline: Raw Transcript → Cleaning → Analysis → Task Creation → Task Execution
final class PipelineOrchestrator: @unchecked Sendable {
    private let cleaningService: TranscriptCleaningService
    private let analysisService: TranscriptAnalysisService
    private let taskCreationService: TaskCreationService
    private let taskExecutionService: TaskExecutionService

    var onPipelineUpdated: (() -> Void)?

    init(cleaningService: TranscriptCleaningService,
         analysisService: TranscriptAnalysisService,
         taskCreationService: TaskCreationService,
         taskExecutionService: TaskExecutionService) {
        self.cleaningService = cleaningService
        self.analysisService = analysisService
        self.taskCreationService = taskCreationService
        self.taskExecutionService = taskExecutionService
    }

    // MARK: - Public API

    /// Process a new transcript through the pipeline.
    ///
    /// `source` controls which stages run:
    /// - `.ambient` / `.whatsapp` — full pipeline (clean → analyze → task → execute)
    /// - `.transcription` — Stage 1 (clean) only; transcript is stored for copy-paste use
    /// - `.code` — skips all LLM stages; the Code widget handles execution itself
    func processTranscript(
        text: String,
        transcriptID: Int64,
        sessionID: String?,
        sessionChunkSeq: Int,
        durationSeconds: Int,
        speakerName: String?,
        source: PipelineSource = .ambient
    ) async {
        Log.info(.pipeline, "Pipeline[\(source.rawValue)]: processing transcript (\(text.count) chars, session=\(sessionID ?? "none"), seq=\(sessionChunkSeq))")

        // Code mode: the widget manages its own execution — no pipeline stages needed.
        if source == .code {
            Log.info(.pipeline, "Pipeline[code]: skipping all stages (code widget handles execution)")
            await notifyUpdate()
            return
        }

        // Stage 1: Clean (runs for all non-code sources)
        guard let cleaned = await cleaningService.processNewTranscript(
            text: text,
            transcriptID: transcriptID,
            sessionID: sessionID,
            sessionChunkSeq: sessionChunkSeq,
            durationSeconds: durationSeconds,
            speakerName: speakerName
        ) else {
            Log.info(.pipeline, "Pipeline: cleaning returned nil (likely waiting for more chunks)")
            return
        }

        await notifyUpdate()

        // Transcription mode: clean only — no task analysis or creation.
        // User is dictating/copy-pasting; the cleaned transcript is the end product.
        if source == .transcription {
            Log.info(.pipeline, "Pipeline[transcription]: stopping after cleaning stage")
            return
        }

        // Stage 2: Analyze (ambient + whatsapp)
        guard let analysis = await analysisService.analyze(cleaned: cleaned) else {
            Log.info(.pipeline, "Pipeline: analysis returned nil")
            return
        }

        await notifyUpdate()

        // Grab any context captures (screenshots, clipboard images) from this session
        let captures = ContextCaptureStore.shared.recentUnattached(sessionID: sessionID)
        let capturePaths = captures.map(\.filePath).filter { !$0.isEmpty }
        if !captures.isEmpty {
            Log.info(.pipeline, "Pipeline: found \(captures.count) context capture(s) for session")
            ContextCaptureStore.shared.markAttached(ids: captures.map(\.id))
        }

        // Stage 3: Create tasks (with attached context captures)
        let tasks = await taskCreationService.createTasks(from: analysis, attachmentPaths: capturePaths)

        await notifyUpdate()

        if tasks.isEmpty {
            Log.info(.pipeline, "Pipeline: no tasks created (non-actionable transcript)")
            return
        }

        Log.info(.pipeline, "Pipeline: \(tasks.count) task(s) created" +
                 (capturePaths.isEmpty ? "" : " with \(capturePaths.count) attachment(s)"))

        // Stage 4: Execute auto tasks
        for task in tasks where task.mode == .auto {
            await taskExecutionService.execute(task: task)
            await notifyUpdate()
        }

        Log.info(.pipeline, "Pipeline: complete")
    }

    /// Execute a task that was manually accepted by the user.
    func executeAcceptedTask(_ task: PipelineTaskRecord) async {
        Log.info(.pipeline, "Pipeline: executing accepted task \(task.id)")
        await taskExecutionService.execute(task: task)
        await notifyUpdate()
    }

    // MARK: - Private

    @MainActor
    private func notifyUpdate() {
        onPipelineUpdated?()
    }
}
