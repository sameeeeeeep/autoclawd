import Foundation

// MARK: - WorkflowBuilder
//
// Detects patterns from capability execution history and builds workflows.
// Phase 1: manual workflow creation helpers.
// Phase 2 (future): watches capability execution sequences and infers workflows
//   ("You ran these 4 capabilities together — save as workflow?")

@MainActor
final class WorkflowBuilder: ObservableObject {

    @Published var lastSuggestedWorkflow: WorkflowRecord?

    // MARK: - Manual Workflow Creation

    /// Create a workflow from explicit step definitions.
    func createWorkflow(
        name: String,
        description: String,
        emoji: String,
        category: WorkflowCategory,
        steps: [WorkflowStep],
        inputSpec: WorkflowInputSpec = .empty,
        origin: WorkflowOrigin = .manual
    ) -> WorkflowRecord {
        let workflow = WorkflowRecord(
            id: "WF-\(String(UUID().uuidString.prefix(8)).uppercased())",
            name: name,
            description: description,
            emoji: emoji,
            category: category,
            createdAt: Date(),
            steps: steps,
            inputSpec: inputSpec,
            createdFrom: origin
        )

        WorkflowStore.shared.save(workflow)
        Log.info(.pipeline, "WorkflowBuilder: created workflow '\(name)' with \(steps.count) steps")
        return workflow
    }

    /// Create a workflow step with sensible defaults.
    static func makeStep(
        order: Int,
        name: String,
        description: String,
        skillSlug: String? = nil,
        capabilityID: String? = nil,
        promptTemplate: String? = nil,
        inputMapping: [String: String] = [:],
        outputKey: String? = nil
    ) -> WorkflowStep {
        WorkflowStep(
            id: "ws-\(String(UUID().uuidString.prefix(6)).lowercased())",
            order: order,
            name: name,
            description: description,
            capabilityID: capabilityID,
            skillSlug: skillSlug,
            promptTemplate: promptTemplate,
            inputMapping: inputMapping,
            outputKey: outputKey
        )
    }

    // MARK: - Pattern Detection (Stub — Future Implementation)

    /// Analyze recent capability executions and detect repeating sequences.
    /// Returns a suggested workflow if a pattern is found, nil otherwise.
    ///
    /// Future implementation will:
    /// 1. Watch `PipelineTaskRecord` history for capability executions (CAP-* IDs)
    /// 2. Detect sequences: "same 3+ capabilities executed in similar order within 1 hour, 2+ times"
    /// 3. Group by project or by time window
    /// 4. Build a WorkflowRecord from the detected sequence
    /// 5. Set `lastSuggestedWorkflow` → UI shows "Save as workflow?" prompt
    func detectPattern(from executionHistory: [PipelineTaskRecord]) -> WorkflowRecord? {
        // Stub: no automatic detection yet.
        // When implemented, this will:
        //   - Filter for CAP-* tasks (capability executions)
        //   - Extract capability IDs from task metadata
        //   - Find sequences that repeat across sessions
        //   - Generate a WorkflowRecord with inferred steps and inputSpec
        return nil
    }

    /// Called after each capability execution to check for emerging patterns.
    func onCapabilityExecuted(_ capabilityID: String, projectID: String?) {
        // Stub: accumulate execution history for pattern detection.
        // Future: append to a rolling buffer, call detectPattern() periodically.
        Log.info(.pipeline, "WorkflowBuilder: recorded capability execution \(capabilityID)")
    }
}
