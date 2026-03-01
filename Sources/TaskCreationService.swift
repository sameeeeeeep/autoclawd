import Foundation

// MARK: - TaskCreationService

/// Stage 3: Execution planning. Receives task titles + prompts from analysis,
/// determines skill, workflow, certainty, and creates PipelineTaskRecords.
final class TaskCreationService: @unchecked Sendable {
    private let ollama: OllamaService
    private let pipelineStore: PipelineStore
    private let skillStore: SkillStore
    private let workflowRegistry: WorkflowRegistry
    private let projectStore: ProjectStore

    init(ollama: OllamaService, pipelineStore: PipelineStore,
         skillStore: SkillStore, workflowRegistry: WorkflowRegistry,
         projectStore: ProjectStore) {
        self.ollama = ollama
        self.pipelineStore = pipelineStore
        self.skillStore = skillStore
        self.workflowRegistry = workflowRegistry
        self.projectStore = projectStore
    }

    // MARK: - Public API

    func createTasks(from analysis: TranscriptAnalysis, attachmentPaths: [String] = []) async -> [PipelineTaskRecord] {
        guard !analysis.taskDescriptions.isEmpty else {
            Log.info(.taskCreate, "Stage 3: no task descriptions from analysis, skipping")
            return []
        }

        var results: [PipelineTaskRecord] = []

        for desc in analysis.taskDescriptions {
            let plan = await planExecution(
                title: desc.title,
                prompt: desc.prompt,
                projectName: analysis.projectName
            )

            // Resolve skill and workflow
            let skill = skillStore.load(id: plan.skillID)
            let workflowID = skill?.workflowID ?? "autoclawd-claude-code"
            let workflow = workflowRegistry.workflow(for: workflowID)
            let missingConnection = workflow.flatMap { workflowRegistry.checkConnections(for: $0) }

            // Determine mode based on certainty and connections
            let mode: TaskMode
            let status: TaskStatus
            let pendingQuestion: String?

            if missingConnection != nil {
                mode = .ask
                status = .needs_input
                pendingQuestion = "Missing connection: \(missingConnection!). Set up \(missingConnection!) to proceed."
            } else if plan.needsInput != nil {
                mode = .ask
                status = .needs_input
                pendingQuestion = plan.needsInput
            } else {
                // Check user-configured autonomous rules first.
                // If the task title or prompt matches any rule, force .auto regardless of certainty.
                let autonomousRules = SettingsManager.shared.autonomousTaskRules
                let taskText = "\(desc.title) \(desc.prompt)".lowercased()
                let matchesAutonomousRule = autonomousRules.contains { rule in
                    let keywords = rule.lowercased()
                        .components(separatedBy: .whitespacesAndNewlines)
                        .filter { !$0.isEmpty && $0.count > 2 }
                    return keywords.allSatisfy { taskText.contains($0) }
                }

                if matchesAutonomousRule {
                    mode = .auto
                    status = .upcoming
                    pendingQuestion = nil
                } else {
                    switch plan.certainty {
                    case "high":
                        mode = .auto
                        status = .upcoming
                        pendingQuestion = nil
                    case "medium":
                        mode = .ask
                        status = .pending_approval
                        pendingQuestion = "Review and approve this task before execution?"
                    default: // "low" or unknown
                        mode = .ask
                        status = .needs_input
                        pendingQuestion = plan.needsInput ?? "Low certainty. Please review before proceeding."
                    }
                }
            }

            // Generate task ID
            let prefix = projectPrefix(for: analysis.projectName)
            let taskID = pipelineStore.nextTaskID(prefix: prefix)

            let task = PipelineTaskRecord(
                id: taskID,
                analysisID: analysis.id,
                title: desc.title,
                prompt: desc.prompt,
                projectID: analysis.projectID,
                projectName: analysis.projectName,
                mode: mode,
                status: status,
                skillID: plan.skillID,
                workflowID: workflowID,
                workflowSteps: workflow?.steps ?? [],
                missingConnection: missingConnection,
                pendingQuestion: pendingQuestion,
                attachmentPaths: attachmentPaths,
                createdAt: Date(),
                startedAt: nil,
                completedAt: nil
            )

            pipelineStore.insertTask(task)
            results.append(task)

            Log.info(.taskCreate, "Stage 3: created \(taskID) '\(desc.title)' skill=\(plan.skillID) " +
                     "certainty=\(plan.certainty) mode=\(mode.rawValue)")
        }

        return results
    }

    // MARK: - Execution Planning

    private struct ExecutionPlan {
        let skillID: String
        let certainty: String     // "high", "medium", "low"
        let needsInput: String?   // nil if no input needed
    }

    private func planExecution(title: String, prompt: String, projectName: String?) async -> ExecutionPlan {
        // Build skill list for the LLM
        let skills = skillStore.all().filter { $0.category != .pipeline }
        let skillListStr = skills.map { "\($0.id): \($0.description)" }.joined(separator: "\n")

        let skill = skillStore.load(id: "task-creation")
        let template = skill?.promptTemplate ?? Self.defaultPlanningPrompt

        let llmPrompt = template
            .replacingOccurrences(of: "{{skill_list}}", with: skillListStr)
            .replacingOccurrences(of: "{{title}}", with: title)
            .replacingOccurrences(of: "{{prompt}}", with: prompt)
            .replacingOccurrences(of: "{{project}}", with: projectName ?? "unknown")

        do {
            let response = try await ollama.generate(prompt: llmPrompt, numPredict: 256)
            return parseExecutionPlan(response)
        } catch {
            Log.error(.taskCreate, "Stage 3 LLM failed: \(error.localizedDescription)")
            return ExecutionPlan(skillID: "general", certainty: "low", needsInput: "LLM planning failed")
        }
    }

    private func parseExecutionPlan(_ response: String) -> ExecutionPlan {
        var skillID = "general"
        var certainty = "medium"
        var needsInput: String? = nil

        let lines = response.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let colonRange = trimmed.range(of: ": ") {
                let key = String(trimmed[trimmed.startIndex..<colonRange.lowerBound])
                    .trimmingCharacters(in: .whitespaces).uppercased()
                let value = String(trimmed[colonRange.upperBound...])
                    .trimmingCharacters(in: .whitespaces)

                switch key {
                case "SKILL":
                    // Validate it's a known skill ID
                    let candidate = value.lowercased().trimmingCharacters(in: .whitespaces)
                    if skillStore.load(id: candidate) != nil {
                        skillID = candidate
                    } else {
                        skillID = "general"
                    }
                case "CERTAINTY":
                    let c = value.lowercased()
                    if ["high", "medium", "low"].contains(c) {
                        certainty = c
                    }
                case "NEEDS_INPUT":
                    if value.uppercased() != "NONE" && !value.isEmpty {
                        needsInput = value
                    }
                default:
                    break
                }
            }
        }

        return ExecutionPlan(skillID: skillID, certainty: certainty, needsInput: needsInput)
    }

    // MARK: - Helpers

    /// Generate a 2-letter prefix from project name (e.g., "autoclawd" → "AC", "trippy" → "TR")
    private func projectPrefix(for projectName: String?) -> String {
        guard let name = projectName, name.count >= 2 else { return "GN" }
        let upper = name.uppercased()
        let first = upper[upper.startIndex]
        // Find first consonant after the first letter
        let consonants: Set<Character> = ["B","C","D","F","G","H","J","K","L","M","N","P","Q","R","S","T","V","W","X","Y","Z"]
        let second = upper.dropFirst().first(where: { consonants.contains($0) }) ?? upper[upper.index(after: upper.startIndex)]
        return "\(first)\(second)"
    }

    // MARK: - Default Prompt

    private static let defaultPlanningPrompt = """
        You are planning how to execute a task. Determine the best approach.

        AVAILABLE SKILLS:
        {{skill_list}}

        TASK TITLE: {{title}}
        TASK PROMPT: {{prompt}}
        PROJECT: {{project}}

        Output EXACTLY this format:
        SKILL: <skill id from the list, or "general">
        CERTAINTY: <high/medium/low - can this be done autonomously without human input?>
        NEEDS_INPUT: <what specific input is needed from the user, or "NONE">
        """
}
