import Foundation

// MARK: - Workflow Data Models (Phase 3 Foundation)
//
// Three-tier automation: Skills (atomic) → Capabilities (skills + tools) → Workflows.
// A Workflow chains Capabilities and Skills in sequence with context passing,
// delivering a real-world output from minimal user input.

// MARK: - Workflow Record

/// A persistent workflow definition — an ordered chain of capabilities/skills.
struct WorkflowRecord: Codable, Identifiable {
    let id: String                              // "WF-{uuid8}"
    let name: String                            // "Launch Video"
    let description: String
    let emoji: String                           // visual identifier
    let category: WorkflowCategory
    let createdAt: Date
    let steps: [WorkflowStep]                   // ordered sequence
    let inputSpec: WorkflowInputSpec            // what user provides at runtime
    let createdFrom: WorkflowOrigin             // .observed | .manual | .prebuilt

    /// Compact summary for logs.
    var summary: String {
        "\(emoji) \(name) (\(steps.count) step\(steps.count == 1 ? "" : "s"))"
    }
}

// MARK: - Workflow Step

/// One step in a workflow chain. References either a Capability or an OpenClaw skill.
struct WorkflowStep: Codable, Identifiable {
    let id: String
    let order: Int
    let name: String                            // "Download reference videos"
    let description: String
    let capabilityID: String?                   // reference to Capability in CapabilityStore
    let skillSlug: String?                      // OR reference to OpenClaw skill
    let promptTemplate: String?                 // custom Claude prompt (if neither cap nor skill)
    let inputMapping: [String: String]          // maps workflow context keys → step input vars
    let outputKey: String?                      // key to store this step's output in context

    /// The invocation label used in logs.
    var invocationLabel: String {
        if let slug = skillSlug { return "skill:\(slug)" }
        if let capID = capabilityID { return "cap:\(capID)" }
        return "prompt"
    }
}

// MARK: - Input Specification

/// Defines what the user provides before running a workflow.
struct WorkflowInputSpec: Codable {
    let references: [ReferenceField]            // upload/URL fields
    let contextField: String?                   // free-text description prompt
    let projectSelection: Bool                  // show project picker?

    static let empty = WorkflowInputSpec(references: [], contextField: nil, projectSelection: true)
}

/// A single reference field in the input spec.
struct ReferenceField: Codable, Identifiable {
    let id: String
    let label: String                           // "Reference URLs", "Brand guide PDF"
    let type: ReferenceFieldType                // .url, .file, .text
    let required: Bool
}

/// Type of reference the user provides.
enum ReferenceFieldType: String, Codable {
    case url
    case file
    case text
}

// MARK: - Workflow Origin

/// How a workflow was created.
enum WorkflowOrigin: String, Codable {
    case observed   // inferred from FUCBC / capability execution history
    case manual     // user-created
    case prebuilt   // shipped with AutoClawd
}

// MARK: - Workflow Category

/// Broad category for organizing workflows in the UI.
enum WorkflowCategory: String, Codable, CaseIterable {
    case content        = "content"
    case research       = "research"
    case engineering    = "engineering"
    case communication  = "communication"
    case productivity   = "productivity"
    case creative       = "creative"

    var label: String {
        switch self {
        case .content:        return "Content"
        case .research:       return "Research"
        case .engineering:    return "Engineering"
        case .communication:  return "Communication"
        case .productivity:   return "Productivity"
        case .creative:       return "Creative"
        }
    }

    var icon: String {
        switch self {
        case .content:        return "doc.richtext"
        case .research:       return "magnifyingglass"
        case .engineering:    return "terminal.fill"
        case .communication:  return "message.fill"
        case .productivity:   return "checklist"
        case .creative:       return "paintbrush.fill"
        }
    }
}

// MARK: - Runtime Types (not persisted as part of the record)

/// User-provided inputs collected before workflow execution.
struct WorkflowInputs {
    let references: [String: String]            // fieldID → value (URL/path/text)
    let context: String                         // free-text context
    let projectID: String?
}

/// Mutable context passed between workflow steps during execution.
struct WorkflowContext {
    var inputs: WorkflowInputs
    var stepOutputs: [String: String] = [:]     // outputKey → result text
    var currentStepIndex: Int = 0
    var status: WorkflowExecutionStatus = .running

    /// Build the prompt preamble from accumulated context.
    func contextPreamble() -> String {
        var parts: [String] = []
        if !inputs.context.isEmpty {
            parts.append("User context: \(inputs.context)")
        }
        for (key, value) in inputs.references {
            parts.append("Reference [\(key)]: \(value)")
        }
        for (key, value) in stepOutputs {
            parts.append("Previous step output [\(key)]:\n\(value)")
        }
        return parts.joined(separator: "\n\n")
    }
}

/// Execution status for a workflow or individual step.
enum WorkflowExecutionStatus: String, Codable {
    case pending
    case running
    case completed
    case failed
    case cancelled
}

// MARK: - Execution Log

/// Log entry for one step's execution.
struct WorkflowStepLog: Codable, Identifiable {
    let id: String
    let stepID: String
    let stepName: String
    let startedAt: Date
    var completedAt: Date?
    var status: WorkflowExecutionStatus
    var output: String?
    var error: String?

    var durationSeconds: Double? {
        guard let end = completedAt else { return nil }
        return end.timeIntervalSince(startedAt)
    }
}

/// Full execution log for a workflow run.
struct WorkflowExecutionLog: Identifiable {
    let id: String
    let workflowID: String
    let workflowName: String
    let startedAt: Date
    var completedAt: Date?
    var status: WorkflowExecutionStatus = .running
    var stepLogs: [WorkflowStepLog] = []

    var completedSteps: Int { stepLogs.filter { $0.status == .completed }.count }
    var totalSteps: Int { stepLogs.count }
}
