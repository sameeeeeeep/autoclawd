import Foundation

// MARK: - Skill Category

enum SkillCategory: String, Codable, CaseIterable {
    case pipeline       // transcript-cleaning, transcript-analysis, task-creation
    case development    // frontend-design, backend-dev
    case analysis       // data-analysis
    case management     // project-management
    case creative       // video-generation, image-generation
    case marketing      // campaign-activation
    case search         // web search, research, information retrieval
    case communication  // email, messaging, notifications, reminders
    case automation     // shell scripts, system tasks, file operations
    case system         // system utilities, settings, configuration
    case other
}

// MARK: - Skill

/// A skill defines a prompt template and optional workflow for a specific task type.
/// Skills are stored as individual JSON files in ~/.autoclawd/skills/ so users can view/edit them.
/// OpenClaw skills are loaded from SKILL.md files in ~/.autoclawd/openclaw-skills/.
struct Skill: Identifiable, Codable {
    let id: String
    var name: String
    var description: String
    var promptTemplate: String
    var workflowID: String?
    var category: SkillCategory
    var isBuiltin: Bool

    // MARK: - OpenClaw Extensions

    /// Full markdown instructions from SKILL.md body. Injected into Claude's prompt during execution.
    var instructions: String?

    /// Binaries required on PATH for this skill to be available (e.g. ["git", "gh"]).
    var requiredBins: [String]?

    /// Environment variables to inject into the execution process.
    var envVars: [String: String]?

    /// Whether this skill was loaded from an OpenClaw SKILL.md file.
    var isOpenClaw: Bool?

    /// Filesystem path to the SKILL.md file (for display/editing in UI).
    var skillMDPath: String?

    // MARK: - Availability

    /// Check if all required binaries are available on the system.
    func checkBinRequirements() -> Bool {
        guard let bins = requiredBins, !bins.isEmpty else { return true }
        return bins.allSatisfy { binName in
            Self.commandExists(binName)
        }
    }

    /// Returns names of missing required binaries.
    func missingBins() -> [String] {
        guard let bins = requiredBins, !bins.isEmpty else { return [] }
        return bins.filter { !Self.commandExists($0) }
    }

    /// Check if all required environment variables are set.
    func checkEnvRequirements() -> Bool {
        guard let vars = envVars, !vars.isEmpty else { return true }
        // Check that the keys referenced in envVars are available
        // (envVars stores key=value pairs to inject, but we check if keys without
        //  values need to be provided by the user)
        return true // envVars are injected, not required from environment
    }

    /// Whether this skill is fully available (all requirements met).
    var isAvailable: Bool {
        checkBinRequirements()
    }

    static func commandExists(_ name: String) -> Bool {
        let candidates = [
            "/usr/local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/bin/\(name)",
        ]
        let home = FileManager.default.homeDirectoryForCurrentUser
        let localBin = home.appendingPathComponent(".local/bin/\(name)").path
        if FileManager.default.isExecutableFile(atPath: localBin) { return true }
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) { return true }
        }
        // Fall back to `which`
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [name]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }
}
