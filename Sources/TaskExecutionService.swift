import Foundation

// MARK: - TaskExecutionService

/// Stage 4: Executes tasks based on their workflow. Logs steps progressively.
final class TaskExecutionService: @unchecked Sendable {
    private let pipelineStore: PipelineStore
    private let claudeCodeRunner: ClaudeCodeRunner
    private let projectStore: ProjectStore

    init(pipelineStore: PipelineStore, claudeCodeRunner: ClaudeCodeRunner,
         projectStore: ProjectStore) {
        self.pipelineStore = pipelineStore
        self.claudeCodeRunner = claudeCodeRunner
        self.projectStore = projectStore
    }

    // MARK: - Public API

    func execute(task: PipelineTaskRecord) async {
        guard task.mode == .auto, task.status == .upcoming else { return }

        // Mark as ongoing
        pipelineStore.updateTaskStatus(id: task.id, status: .ongoing, startedAt: Date())
        logStep(taskID: task.id, index: 0, description: "Task execution started")

        // Resolve project path
        guard let projectID = task.projectID,
              let project = projectStore.all().first(where: { $0.id == projectID }) else {
            logStep(taskID: task.id, index: 1, description: "No project path resolved", status: "failed")
            pipelineStore.updateTaskStatus(id: task.id, status: .needs_input)
            Log.warn(.taskExec, "Task \(task.id): no project path, marking needs_input")
            return
        }

        // Route based on workflow
        switch task.workflowID {
        case "autoclawd-claude-code":
            await executeViaClaude(task: task, project: project)
        case "autoclawd-claude-code-linear":
            await executeViaClaude(task: task, project: project)
        case "autoclawd-claude-code-meta":
            await executeViaClaude(task: task, project: project)
        default:
            logStep(taskID: task.id, index: 1,
                    description: "No executable workflow for '\(task.workflowID ?? "none")'",
                    status: "failed")
            pipelineStore.updateTaskStatus(id: task.id, status: .needs_input)
            Log.info(.taskExec, "Task \(task.id): no executable workflow, marking needs_input")
        }
    }

    // MARK: - Claude Code Execution

    private func executeViaClaude(task: PipelineTaskRecord, project: Project) async {
        logStep(taskID: task.id, index: 1, description: "Dispatching to Claude Code CLI")
        Log.info(.taskExec, "Task \(task.id): executing via Claude Code in \(project.localPath)")

        var stepIdx = 2

        do {
            for try await line in claudeCodeRunner.run(task.prompt, in: project) {
                logStep(taskID: task.id, index: stepIdx, description: line)
                stepIdx += 1
            }
            logStep(taskID: task.id, index: stepIdx, description: "Task completed successfully")
            pipelineStore.updateTaskStatus(id: task.id, status: .completed, completedAt: Date())
            Log.info(.taskExec, "Task \(task.id): completed")
        } catch {
            logStep(taskID: task.id, index: stepIdx,
                    description: "Execution failed: \(error.localizedDescription)", status: "failed")
            pipelineStore.updateTaskStatus(id: task.id, status: .needs_input)
            Log.error(.taskExec, "Task \(task.id): execution failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Step Logging

    private func logStep(taskID: String, index: Int, description: String, status: String = "completed") {
        let step = TaskExecutionStep(
            id: UUID().uuidString,
            taskID: taskID,
            stepIndex: index,
            description: description,
            status: status,
            timestamp: Date(),
            output: nil
        )
        pipelineStore.insertStep(step)
    }
}
