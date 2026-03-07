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

// MARK: - Ambient Review (post-session canvas overlay)

/// Tracks which phase the post-session review canvas is in.
enum AmbientReviewPhase: Equatable {
    /// Session just ended — transcript is being cleaned by the LLM (blue glow).
    case cleaning
    /// Cleaning finished — LLM is now extracting tasks (blue glow).
    case analyzing
    /// Pipeline finished (or timed out) — tasks are available for user approval.
    case tasksReady
    /// All approved tasks have been executed — show success state.
    case done
}

/// All state for the post-session ambient review overlay.
/// Non-nil on AppState when an ambient session has just ended.
struct AmbientReviewState {
    var phase: AmbientReviewPhase = .cleaning
    /// Cleaned (or raw) transcript text — updated progressively as pipeline runs.
    var cleanedTranscript: String = ""
    /// The ChunkManager sessionID for this session — used for matching pipeline output.
    var sessionID: String? = nil
    /// Timestamp when this review was created — used to filter analyses to this session only.
    var startedAt: Date = Date()
    /// IDs of TranscriptAnalysis records created from this session.
    var sessionAnalysisIDs: [String] = []
    /// IDs of PipelineTaskRecord records created from this session.
    var sessionTaskIDs: [String] = []
    /// Tasks the user has approved in the review canvas.
    var approvedTaskIDs: Set<String> = []
    /// Tasks the user has skipped in the review canvas.
    var skippedTaskIDs: Set<String> = []
    /// Project chosen in the review (applied retroactively on Done).
    var selectedProjectID: String? = nil
    var selectedProjectName: String? = nil
    /// Remaining task IDs to execute sequentially after "approve all".
    var executionQueue: [String] = []
}
