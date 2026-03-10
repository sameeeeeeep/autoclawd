import Foundation

// MARK: - WorkflowTemplateStore (stubbed — replaced by CapabilityStore)
//
// Workflow templates have been superseded by the richer Capability model.
// This file is kept as a stub to avoid import/reference errors during transition.
// All new persistence goes through CapabilityStore.

final class WorkflowTemplateStore: @unchecked Sendable {
    static let shared = WorkflowTemplateStore()
    private init() {}
}
