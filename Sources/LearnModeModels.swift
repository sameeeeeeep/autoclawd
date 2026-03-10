import Foundation

// MARK: - Learn Mode Data Models (FUCBC Architecture)
//
// No Llama. Events are collected every 5 seconds directly from the screen/audio
// pipeline. When the user triggers Build, the full event dump is sent straight
// to Claude Code with the FUCBC prompt — Claude figures out the use-case pattern,
// builds modular sub-workflows, and writes a SKILL.md into the OpenClaw directory
// so it's auto-discovered by AutoClawd on next refresh.

// MARK: - Event Snapshot

/// A timestamped snapshot of what was happening every 5s during a learn session.
/// Collected without any Llama processing — raw signal only.
struct LearnEvent: Codable {
    let timestamp: Date
    let appName: String?
    let windowTitle: String?
    let ocrSnippet: String        // first 400 chars of OCR (enough for pattern detection)
    let detectedURLs: [String]
    let speechSnippet: String     // raw SFSpeech partial or committed chunk (no cleaning)

    /// Compact text representation for the FUCBC prompt.
    func eventLine() -> String {
        let t = timestamp.formatted(.dateTime.hour().minute().second())
        var parts: [String] = ["[\(t)]"]
        if let app = appName { parts.append("App:\(app)") }
        if let title = windowTitle {
            let short = title.count > 60 ? String(title.prefix(60)) + "…" : title
            parts.append("Win:\(short)")
        }
        if !detectedURLs.isEmpty { parts.append("URLs:\(detectedURLs.prefix(2).joined(separator: ","))") }
        if !speechSnippet.isEmpty {
            let s = speechSnippet.count > 120 ? String(speechSnippet.prefix(120)) + "…" : speechSnippet
            parts.append("Speech:\"\(s)\"")
        }
        if !ocrSnippet.isEmpty {
            let o = ocrSnippet.count > 200 ? String(ocrSnippet.prefix(200)) + "…" : ocrSnippet
            parts.append("Screen:\"\(o)\"")
        }
        return parts.joined(separator: " | ")
    }
}

// MARK: - Capability

/// A modular capability built by Claude via the FUCBC skill.
/// Richer than a simple workflow: has an emoji, category, sub-workflows,
/// and trigger conditions for auto-detection.
struct Capability: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let emoji: String
    let category: CapabilityCategory
    let createdAt: Date

    /// Trigger conditions — used to auto-execute when pattern is detected.
    let triggers: CapabilityTriggers

    /// Sub-workflows that make up this capability.
    let subWorkflows: [SubWorkflow]

    /// Path to the SKILL.md file created in ~/.autoclawd/openclaw-skills/{slug}/
    let skillMDPath: String?

    /// Slug used as the OpenClaw skill directory name.
    let slug: String
}

// MARK: - Capability Category

enum CapabilityCategory: String, Codable, CaseIterable {
    case research      = "research"
    case automation    = "automation"
    case communication = "communication"
    case development   = "development"
    case discovery     = "discovery"
    case organization  = "organization"

    var label: String {
        switch self {
        case .research:      return "Research"
        case .automation:    return "Automation"
        case .communication: return "Communication"
        case .development:   return "Development"
        case .discovery:     return "Discovery"
        case .organization:  return "Organization"
        }
    }

    var icon: String {
        switch self {
        case .research:      return "magnifyingglass"
        case .automation:    return "gearshape.2.fill"
        case .communication: return "message.fill"
        case .development:   return "terminal.fill"
        case .discovery:     return "sparkles"
        case .organization:  return "folder.fill"
        }
    }
}

// MARK: - Capability Triggers

/// Conditions that, when detected from screen/audio, auto-execute the capability.
struct CapabilityTriggers: Codable {
    let apps: [String]        // e.g. ["Safari", "Chrome", "Threads"]
    let urlPatterns: [String] // e.g. ["threads.net", "youtube.com", "reddit.com"]
    let keywords: [String]    // e.g. ["AI model", "open source", "download"]
    let ocrPatterns: [String] // e.g. ["Watch on YouTube", "New model release"]
}

// MARK: - Sub-Workflow

/// A discrete step within a capability (detect → extract → research → execute → notify).
struct SubWorkflow: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let invocation: String?   // shell command or skill slug
}

// MARK: - Session Phase

enum LearnPhase: Equatable {
    case collecting           // recording events
    case building             // running Claude Code FUCBC
    case done(String)         // capability id
    case failed(String)       // error message

    static func == (lhs: LearnPhase, rhs: LearnPhase) -> Bool {
        switch (lhs, rhs) {
        case (.collecting, .collecting): return true
        case (.building, .building):     return true
        case (.done(let a), .done(let b)):     return a == b
        case (.failed(let a), .failed(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - Learn Session

struct LearnSession: Identifiable {
    let id = UUID()
    let startedAt: Date
    var phase: LearnPhase = .collecting
    var events: [LearnEvent] = []         // 5-second snapshots, no Llama
    var buildOutput: String = ""          // FUCBC Claude Code stream
    var builtCapability: Capability?
    var suggestedCapabilities: [Capability] = []

    var hasEnoughContext: Bool {
        events.count >= 3  // at least 15 seconds of observation
    }

    var eventSummary: String {
        "\(events.count) event(s) · \(Int(events.count * 5))s"
    }
}

// MARK: - Capability Manifest (parsed from Claude's JSON output)

/// Transient struct — parsed from Claude's ```json block, then converted to Capability.
struct CapabilityManifest: Codable {
    let name: String
    let description: String
    let emoji: String
    let category: String
    let slug: String
    let triggerApps: [String]
    let triggerURLPatterns: [String]
    let triggerKeywords: [String]
    let triggerOCRPatterns: [String]
    let subWorkflows: [SubWorkflowManifest]

    struct SubWorkflowManifest: Codable {
        let name: String
        let description: String
        let invocation: String?
    }
}
