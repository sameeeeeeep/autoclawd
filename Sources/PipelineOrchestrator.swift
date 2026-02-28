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

    /// Process a new transcript through the full pipeline.
    /// Called by ChunkManager.processChunk() in ambient intelligence mode.
    func processTranscript(
        text: String,
        transcriptID: Int64,
        sessionID: String?,
        sessionChunkSeq: Int,
        durationSeconds: Int,
        speakerName: String?
    ) async {
        Log.info(.pipeline, "Pipeline: processing transcript (\(text.count) chars, session=\(sessionID ?? "none"), seq=\(sessionChunkSeq))")

        // Stage 1: Clean
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

        // Stage 2: Analyze
        guard let analysis = await analysisService.analyze(cleaned: cleaned) else {
            Log.info(.pipeline, "Pipeline: analysis returned nil")
            return
        }

        await notifyUpdate()

        // Stage 3: Create tasks
        let tasks = await taskCreationService.createTasks(from: analysis)

        await notifyUpdate()

        if tasks.isEmpty {
            Log.info(.pipeline, "Pipeline: no tasks created (non-actionable transcript)")
            return
        }

        Log.info(.pipeline, "Pipeline: \(tasks.count) task(s) created")

        // Stage 4: Execute auto tasks
        for task in tasks where task.mode == .auto {
            await taskExecutionService.execute(task: task)
            await notifyUpdate()
        }

        Log.info(.pipeline, "Pipeline: complete")
    }

    // MARK: - Private

    @MainActor
    private func notifyUpdate() {
        onPipelineUpdated?()
    }
}
