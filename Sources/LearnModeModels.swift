import Foundation

// MARK: - Suggestion Match Types

/// A single signal that fired during capability scoring.
/// Passed through to the toast so it can surface "why" in the headline.
enum MatchSignal: Equatable, Sendable {
    case app(String)      // matched app name, e.g. "Threads"
    case url(String)      // matched URL pattern, e.g. "threads.net"
    case ocr(String)      // matched OCR pattern, e.g. "New Post"
    case keyword(String)  // matched keyword, e.g. "campaign"
}

/// Returned by CapabilityStore.suggest() instead of bare Capability.
/// Carries everything the toast needs. Transient — never persisted.
struct SuggestionMatch: Sendable {
    let capability: Capability
    let score: Int
    let matchedSignals: [MatchSignal]  // all signals that contributed to the score
    let contextualHeadline: String     // resolved question, e.g. "Launching a Threads campaign?"
}

// MARK: - Unified Suggestion Item

enum SuggestionItem {
    case capability(SuggestionMatch)
    case task(TaskSuggestion)
}

struct TaskSuggestion: Identifiable {
    let id: String
    let title: String           // e.g. "Send quarterly report to Josh"
    let intent: String          // "email" | "hire" | "post" | "message" | "other"
    let detectedContext: TaskContext
    let executionPrompt: String // built prompt ready for Claude Code
    let confidence: Float       // 0.0–1.0
}

struct TaskContext {
    let files: [String]    // filenames from OCR (e.g. "Q4-Report.pdf")
    let contacts: [String] // names/emails from transcript or OCR
    let urls: [String]     // relevant URLs visible on screen
    let rawOCR: String     // full OCR snapshot — canvas fallback

    // Intentionally permissive: Claude Code clarifies at runtime if a piece is missing.
    var isComplete: Bool { !files.isEmpty || !contacts.isEmpty || !urls.isEmpty }
}

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

// MARK: - Capability (Unified Model)

/// The universal entity for anything AutoClawd can do.
/// A capability = skill content (SKILL.md or prompt) + triggers (when to suggest) + dependencies (what to install).
///
/// Sources:
///   .openclaw  — parsed from SKILL.md via OpenClawSkillLoader + SkillTagRegistry triggers
///   .fucbc     — built by FUCBC/LearnModeService
///   .catalog   — activated from CapabilityCatalog
///   .builtin   — seeded default execution skills
struct Capability: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let emoji: String
    let category: CapabilityCategory
    let createdAt: Date

    /// Trigger conditions — used to auto-suggest when pattern is detected from screen context.
    let triggers: CapabilityTriggers

    /// Sub-workflows that make up this capability.
    let subWorkflows: [SubWorkflow]

    /// Path to the SKILL.md file created in ~/.autoclawd/openclaw-skills/{slug}/
    let skillMDPath: String?

    /// Slug used as the OpenClaw skill directory name.
    let slug: String

    // ── Unified fields (absorbed from Skill + SkillTagRegistry + CatalogEntry) ──

    /// Where this capability came from. Defaults to .fucbc for backward compat with existing JSON.
    var source: CapabilitySource

    /// Dependencies required to run this capability (binaries, env vars, install hints).
    var dependencies: CapabilityDependencies?

    /// Inline prompt template for Claude Code execution (from Skill.promptTemplate).
    var promptTemplate: String?

    /// Full markdown instructions from SKILL.md body.
    var instructions: String?

    /// Tags for WorkflowBuilder matching (e.g. ["video-production", "content-creation"]).
    var workflowTags: [String]

    /// Context-specific question shown in the toast headline.
    /// Tokens: {app}, {url}, {ocr} are filled at match time.
    /// Empty string → fallback headline derivation at suggestion time.
    var contextualQuestionTemplate: String

    /// Whether all dependencies are met and this capability can run.
    var isAvailable: Bool { dependencies?.isReady ?? true }

    /// Which binaries are missing (empty if all deps met).
    var missingDeps: [String] { dependencies?.missingBins ?? [] }

    // MARK: - Codable (backward-compatible decoder)

    enum CodingKeys: String, CodingKey {
        case id, name, description, emoji, category, createdAt
        case triggers, subWorkflows, skillMDPath, slug
        case source, dependencies, promptTemplate, instructions, workflowTags
        case contextualQuestionTemplate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        emoji = try c.decode(String.self, forKey: .emoji)
        category = try c.decode(CapabilityCategory.self, forKey: .category)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        triggers = try c.decode(CapabilityTriggers.self, forKey: .triggers)
        subWorkflows = try c.decode([SubWorkflow].self, forKey: .subWorkflows)
        skillMDPath = try c.decodeIfPresent(String.self, forKey: .skillMDPath)
        slug = try c.decode(String.self, forKey: .slug)
        // New fields — graceful defaults for existing JSON without these keys
        source = try c.decodeIfPresent(CapabilitySource.self, forKey: .source) ?? .fucbc
        dependencies = try c.decodeIfPresent(CapabilityDependencies.self, forKey: .dependencies)
        promptTemplate = try c.decodeIfPresent(String.self, forKey: .promptTemplate)
        instructions = try c.decodeIfPresent(String.self, forKey: .instructions)
        workflowTags = try c.decodeIfPresent([String].self, forKey: .workflowTags) ?? []
        contextualQuestionTemplate = try c.decodeIfPresent(String.self, forKey: .contextualQuestionTemplate) ?? ""
    }

    /// Full memberwise init for programmatic construction.
    init(
        id: String,
        name: String,
        description: String,
        emoji: String,
        category: CapabilityCategory,
        createdAt: Date = Date(),
        triggers: CapabilityTriggers,
        subWorkflows: [SubWorkflow] = [],
        skillMDPath: String? = nil,
        slug: String,
        source: CapabilitySource = .fucbc,
        dependencies: CapabilityDependencies? = nil,
        promptTemplate: String? = nil,
        instructions: String? = nil,
        workflowTags: [String] = [],
        contextualQuestionTemplate: String = ""
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.emoji = emoji
        self.category = category
        self.createdAt = createdAt
        self.triggers = triggers
        self.subWorkflows = subWorkflows
        self.skillMDPath = skillMDPath
        self.slug = slug
        self.source = source
        self.dependencies = dependencies
        self.promptTemplate = promptTemplate
        self.instructions = instructions
        self.workflowTags = workflowTags
        self.contextualQuestionTemplate = contextualQuestionTemplate
    }
}

// MARK: - Capability Source

enum CapabilitySource: String, Codable {
    case openclaw       // parsed from SKILL.md via OpenClawSkillLoader
    case fucbc          // built by FUCBC/LearnModeService
    case catalog        // activated from CapabilityCatalog
    case builtin        // seeded default execution skill
}

// MARK: - Capability Dependencies

/// Tracks what needs to be installed for a capability to run.
struct CapabilityDependencies: Codable {
    let requiredBins: [String]          // binaries needed on PATH (e.g. ["ffmpeg", "yt-dlp"])
    let envVars: [String: String]       // environment variables to inject
    let installHint: InstallHint?       // how to install (for one-click activation)

    /// All required binaries are available on this machine.
    var isReady: Bool {
        guard !requiredBins.isEmpty else { return true }
        return requiredBins.allSatisfy { Skill.commandExists($0) }
    }

    /// Binaries that are not currently installed.
    var missingBins: [String] {
        requiredBins.filter { !Skill.commandExists($0) }
    }

    init(requiredBins: [String] = [], envVars: [String: String] = [:], installHint: InstallHint? = nil) {
        self.requiredBins = requiredBins
        self.envVars = envVars
        self.installHint = installHint
    }
}

// MARK: - Install Hint

/// Codable-friendly install method record. Maps to CatalogEntry.InstallMethod but is persistable.
struct InstallHint: Codable {
    let type: String        // "brew", "brewTap", "pip", "npm", "go", "cargo", "manual", "builtIn"
    let argument: String?   // formula/package name
    let tap: String?        // for brewTap only

    /// Shell command to install (nil for manual/builtIn).
    var command: String? {
        switch type {
        case "brew":    return argument.map { "brew install \($0)" }
        case "brewTap": return [tap, argument].compactMap { $0 }.isEmpty ? nil :
                               "brew tap \(tap ?? "") && brew install \(argument ?? "")"
        case "pip":     return argument.map { "pip3 install \($0)" }
        case "npm":     return argument.map { "npm install -g \($0)" }
        case "go":      return argument.map { "go install \($0)" }
        case "cargo":   return argument.map { "cargo install \($0)" }
        default:        return nil
        }
    }

    /// Human-friendly label for the install method.
    var label: String {
        switch type {
        case "brew", "brewTap": return "Homebrew"
        case "pip":     return "pip"
        case "npm":     return "npm"
        case "go":      return "Go"
        case "cargo":   return "Cargo"
        case "manual":  return "Manual"
        case "builtIn": return "Built-in"
        default:        return type
        }
    }
}

// MARK: - Capability Category

enum CapabilityCategory: String, Codable, CaseIterable {
    case research      = "research"
    case automation    = "automation"
    case communication = "communication"
    case development   = "development"
    case discovery     = "discovery"
    case organization  = "organization"
    case creative      = "creative"
    case search        = "search"
    case analysis      = "analysis"
    case marketing     = "marketing"
    case system        = "system"

    var label: String {
        switch self {
        case .research:      return "Research"
        case .automation:    return "Automation"
        case .communication: return "Communication"
        case .development:   return "Development"
        case .discovery:     return "Discovery"
        case .organization:  return "Organization"
        case .creative:      return "Creative"
        case .search:        return "Search"
        case .analysis:      return "Analysis"
        case .marketing:     return "Marketing"
        case .system:        return "System"
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
        case .creative:      return "paintbrush.fill"
        case .search:        return "globe"
        case .analysis:      return "chart.bar.fill"
        case .marketing:     return "megaphone.fill"
        case .system:        return "wrench.and.screwdriver.fill"
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

// MARK: - Canvas Node (replaces flat LearnEvent array in LearnSession)

// Codable required: LearnSession is persisted and CanvasNode travels with it.
struct CanvasNode: Identifiable, Codable {
    let id: String
    let app: String
    let url: String?
    var ocrSnapshots: [String]    // rolling OCR captures while on this app+URL
    var speechSnippets: [String]  // speech heard while here
    var workSummary: String?      // Llama-generated: "User drafted a tweet about WWDC"
    let capturedAt: Date
    var lastUpdated: Date

    var displayTitle: String {
        if let urlStr = url, let host = URL(string: urlStr)?.host { return host }
        return app
    }
    var isPending: Bool { workSummary == nil }
}

// MARK: - Learn Session

struct LearnSession: Identifiable {
    let id = UUID()
    let startedAt: Date
    var phase: LearnPhase = .collecting
    var nodes: [CanvasNode] = []
    var buildOutput: String = ""          // FUCBC Claude Code stream
    var builtCapability: Capability?
    var suggestedCapabilities: [Capability] = []

    var hasEnoughContext: Bool {
        nodes.count >= 3
    }

    var eventSummary: String {
        "\(nodes.count) node(s) captured"
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
