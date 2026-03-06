import Foundation

// MARK: - Session Lifecycle State

/// User-driven session lifecycle. Sessions are explicitly started and stopped
/// by the user, not by silence detection.
enum SessionLifecycleState: Equatable {
    /// No session configured — shows "+" button in dock
    case undefined
    /// Config panel is open — user selecting project/people/context
    case configuring
    /// Session configured but not yet recording
    case ready
    /// Recording active — raw transcript accumulates
    case active
    /// Recording paused — can resume
    case paused
}

// MARK: - Session Config

/// User-defined context for a recording session.
/// Set before the session starts, passed to the pipeline at session end
/// to enrich cleaning + analysis prompts.
struct SessionConfig {
    var projectID: String?
    var projectName: String?
    var peopleIDs: [String] = []
    var peopleNames: [String] = []
    var contextBullets: [String] = []

    /// Build a context preamble for LLM prompts.
    func promptContext() -> String {
        var lines: [String] = []
        if let name = projectName, !name.isEmpty {
            lines.append("Project: \(name)")
        }
        if !peopleNames.isEmpty {
            lines.append("People: \(peopleNames.joined(separator: ", "))")
        }
        if !contextBullets.isEmpty {
            let bullets = contextBullets.map { "- \($0)" }.joined(separator: "\n")
            lines.append("Session context:\n\(bullets)")
        }
        return lines.joined(separator: "\n")
    }

    /// Whether any context has been provided.
    var hasContext: Bool {
        (projectID != nil) || !peopleNames.isEmpty || !contextBullets.isEmpty
    }
}
