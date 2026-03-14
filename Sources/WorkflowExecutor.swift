import Foundation

// MARK: - WorkflowExecutor
//
// Serial execution engine for workflows. Chains steps sequentially,
// passing context between them. Each step runs via ClaudeCodeRunner.
//
// Pattern: mirrors TaskExecutionService — @unchecked Sendable, callback-based.
// AppState calls execute() and observes progress via callbacks.

final class WorkflowExecutor: @unchecked Sendable {

    /// Callback when a step starts. (stepIndex, stepName, totalSteps)
    var onStepStarted: ((Int, String, Int) -> Void)?

    /// Callback when a step completes. (stepIndex, stepName, output)
    var onStepCompleted: ((Int, String, String?) -> Void)?

    /// Callback when a step fails. (stepIndex, stepName, error)
    var onStepFailed: ((Int, String, String) -> Void)?

    /// Callback when the entire workflow completes. (executionLog)
    var onWorkflowCompleted: ((WorkflowExecutionLog) -> Void)?

    /// Callback for streaming text from the current step. (stepIndex, text)
    var onStepText: ((Int, String) -> Void)?

    // MARK: - Execute

    /// Run a workflow serially — each step's output feeds into the next.
    /// Returns the final execution log. Also fires callbacks for UI updates.
    func execute(
        workflow: WorkflowRecord,
        inputs: WorkflowInputs,
        project: Project,
        claudeCodeRunner: ClaudeCodeRunner
    ) async -> WorkflowExecutionLog {
        var context = WorkflowContext(inputs: inputs)
        var log = WorkflowExecutionLog(
            id: "WFLOG-\(String(UUID().uuidString.prefix(8)).uppercased())",
            workflowID: workflow.id,
            workflowName: workflow.name,
            startedAt: Date()
        )

        Log.info(.pipeline, "Workflow '\(workflow.name)' started (\(workflow.steps.count) steps)")

        let sortedSteps = workflow.steps.sorted { $0.order < $1.order }

        for (index, step) in sortedSteps.enumerated() {
            context.currentStepIndex = index

            // Create step log entry
            var stepLog = WorkflowStepLog(
                id: "WFSL-\(String(UUID().uuidString.prefix(8)).uppercased())",
                stepID: step.id,
                stepName: step.name,
                startedAt: Date(),
                status: .running
            )
            log.stepLogs.append(stepLog)

            onStepStarted?(index, step.name, sortedSteps.count)
            Log.info(.pipeline, "Workflow step \(index + 1)/\(sortedSteps.count): \(step.name)")

            // Build the prompt for this step
            let prompt = buildStepPrompt(step: step, context: context)

            // Execute via Claude Code
            guard let (session, stream) = claudeCodeRunner.startSession(
                prompt: prompt,
                in: project,
                dangerouslySkipPermissions: true
            ) else {
                let errorMsg = "Failed to start Claude CLI for step '\(step.name)'"
                Log.warn(.pipeline, errorMsg)
                stepLog.status = .failed
                stepLog.error = errorMsg
                stepLog.completedAt = Date()
                updateStepLog(&log, stepLog)
                onStepFailed?(index, step.name, errorMsg)

                // Abort workflow on failure
                log.status = .failed
                log.completedAt = Date()
                onWorkflowCompleted?(log)
                return log
            }

            // Stream events and collect output
            let stepOutput = await streamStepEvents(
                session: session,
                stream: stream,
                stepIndex: index
            )

            // Store output in context for next steps
            if let outputKey = step.outputKey, let output = stepOutput {
                context.stepOutputs[outputKey] = output
            }

            // Update step log
            stepLog.status = .completed
            stepLog.output = stepOutput
            stepLog.completedAt = Date()
            updateStepLog(&log, stepLog)

            onStepCompleted?(index, step.name, stepOutput)
            Log.info(.pipeline, "Workflow step \(index + 1) completed: \(step.name)")
        }

        // Workflow complete
        context.status = .completed
        log.status = .completed
        log.completedAt = Date()

        Log.info(.pipeline, "Workflow '\(workflow.name)' completed (\(log.completedSteps)/\(log.totalSteps) steps)")
        onWorkflowCompleted?(log)

        return log
    }

    // MARK: - Prompt Building

    /// Build the Claude prompt for a single workflow step.
    /// Resolves inputMapping to inject context from previous steps.
    private func buildStepPrompt(step: WorkflowStep, context: WorkflowContext) -> String {
        var prompt: String

        if let template = step.promptTemplate {
            prompt = resolveTemplate(template, context: context, step: step)
        } else if let skillSlug = step.skillSlug {
            // Construct a skill-execution prompt
            let contextPreamble = context.contextPreamble()
            prompt = """
            Execute the OpenClaw skill '\(skillSlug)'.

            Task: \(step.name)
            \(step.description)

            \(contextPreamble.isEmpty ? "" : "Context:\n\(contextPreamble)\n")
            Find and read the SKILL.md for '\(skillSlug)' in ~/.autoclawd/openclaw-skills/\(skillSlug)/SKILL.md and follow its instructions.
            """
        } else if let capID = step.capabilityID {
            // Look up capability and use its SKILL.md or subWorkflows
            if let cap = CapabilityStore.shared.all().first(where: { $0.id == capID }) {
                let contextPreamble = context.contextPreamble()
                if let skillPath = cap.skillMDPath {
                    prompt = """
                    \(contextPreamble.isEmpty ? "" : "Context:\n\(contextPreamble)\n\n")Read and execute the skill defined in \(skillPath).
                    Capability: \(cap.name) \u{2014} \(cap.description)
                    """
                } else {
                    let subSteps = cap.subWorkflows
                        .enumerated()
                        .map { i, wf in "\(i + 1). \(wf.name): \(wf.description)" +
                            (wf.invocation.map { "\n   Run: \($0)" } ?? "") }
                        .joined(separator: "\n")
                    prompt = """
                    \(contextPreamble.isEmpty ? "" : "Context:\n\(contextPreamble)\n\n")Execute capability: \(cap.name)
                    \(cap.description)
                    Steps:
                    \(subSteps)
                    """
                }
            } else {
                prompt = "Execute step: \(step.name)\n\(step.description)\n\n\(context.contextPreamble())"
            }
        } else {
            // Fallback: just use description + context
            prompt = "Execute: \(step.name)\n\(step.description)\n\n\(context.contextPreamble())"
        }

        return prompt
    }

    /// Replace {{variable}} placeholders in a template with context values.
    private func resolveTemplate(_ template: String, context: WorkflowContext, step: WorkflowStep) -> String {
        var resolved = template

        // Resolve inputMapping: step's inputMapping maps template vars → context keys
        for (templateVar, contextKey) in step.inputMapping {
            let placeholder = "{{\(templateVar)}}"

            // Try step outputs first
            if let value = context.stepOutputs[contextKey] {
                resolved = resolved.replacingOccurrences(of: placeholder, with: value)
                continue
            }

            // Try input references (e.g., "references.urls" → inputs.references["urls"])
            if contextKey.hasPrefix("references.") {
                let refKey = String(contextKey.dropFirst("references.".count))
                if let value = context.inputs.references[refKey] {
                    resolved = resolved.replacingOccurrences(of: placeholder, with: value)
                    continue
                }
            }

            // Try "context" key → inputs.context
            if contextKey == "context" {
                resolved = resolved.replacingOccurrences(of: placeholder, with: context.inputs.context)
                continue
            }

            // Leave placeholder if unresolved (Claude will handle it)
            Log.warn(.pipeline, "Workflow template: unresolved placeholder {{\(templateVar)}} (key: \(contextKey))")
        }

        return resolved
    }

    // MARK: - Event Streaming

    /// Stream Claude events for one step, collecting the final output text.
    private func streamStepEvents(
        session: ClaudeSession,
        stream: AsyncThrowingStream<ClaudeEvent, Error>,
        stepIndex: Int
    ) async -> String? {
        var accumulatedText = ""
        var finalResult: String?

        do {
            for try await event in stream {
                switch event {
                case .text(let t):
                    accumulatedText += t
                    onStepText?(stepIndex, accumulatedText)

                case .toolUse(let name, _):
                    Log.info(.pipeline, "  Step \(stepIndex + 1) tool: \(name)")

                case .toolResult(_, _):
                    break

                case .result(let text):
                    finalResult = text
                    if !text.isEmpty {
                        onStepText?(stepIndex, text)
                    }

                case .error(let msg):
                    Log.warn(.pipeline, "  Step \(stepIndex + 1) error: \(msg)")

                case .sessionInit:
                    break

                case .status:
                    break
                }
            }
        } catch {
            Log.warn(.pipeline, "  Step \(stepIndex + 1) stream error: \(error.localizedDescription)")
        }

        // Prefer .result text; fall back to accumulated text
        return finalResult ?? (accumulatedText.isEmpty ? nil : accumulatedText)
    }

    // MARK: - Helpers

    private func updateStepLog(_ log: inout WorkflowExecutionLog, _ stepLog: WorkflowStepLog) {
        if let idx = log.stepLogs.firstIndex(where: { $0.id == stepLog.id }) {
            log.stepLogs[idx] = stepLog
        }
    }
}
