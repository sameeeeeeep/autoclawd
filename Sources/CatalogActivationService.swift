import Foundation

// MARK: - CatalogActivationService
//
// One-click activation of catalog entries:
//   1. Check if binary is installed → run install command if needed
//   2. Write SKILL.md to ~/.autoclawd/openclaw-skills/{slug}/
//   3. Create a Capability record in CapabilityStore with triggers
//   4. Notify UI via capabilityStoreDidChange
//
// All work happens on a background queue. Progress reported via callbacks.

final class CatalogActivationService: @unchecked Sendable {

    static let shared = CatalogActivationService()
    private init() {}

    private let queue = DispatchQueue(label: "com.autoclawd.catalog-activation", qos: .userInitiated)

    // MARK: - Activation Status

    enum ActivationStatus: Equatable {
        case idle
        case checking
        case installing
        case writingSkill
        case registeringCapability
        case done
        case failed(String)
    }

    // MARK: - Activate

    /// Activate a catalog entry. Installs binary if needed, writes SKILL.md, registers Capability.
    func activate(
        _ entry: CatalogEntry,
        onStatus: @escaping @Sendable (ActivationStatus) -> Void,
        onComplete: @escaping @Sendable (Result<Capability, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            self.performActivation(entry, onStatus: onStatus, onComplete: onComplete)
        }
    }

    private func performActivation(
        _ entry: CatalogEntry,
        onStatus: @escaping @Sendable (ActivationStatus) -> Void,
        onComplete: @escaping @Sendable (Result<Capability, Error>) -> Void
    ) {
        let report: (ActivationStatus) -> Void = { status in
            DispatchQueue.main.async { onStatus(status) }
        }

        // 1. Check if already activated
        if entry.hasSkillMD {
            Log.info(.system, "CatalogActivation: '\(entry.name)' already has SKILL.md, re-registering capability")
        }

        // 2. Check / install binary
        report(.checking)

        if let binary = entry.binary, !entry.isInstalled {
            guard let cmd = entry.install.command else {
                // Manual install — can't auto-install
                report(.failed("Manual install required. See GitHub: \(entry.githubURL)"))
                DispatchQueue.main.async { onComplete(.failure(ActivationError.manualInstallRequired(entry.name))) }
                return
            }

            // Built-in tools are always available
            if case .builtIn = entry.install {
                Log.info(.system, "CatalogActivation: '\(entry.name)' is built-in, skipping install")
            } else {
                report(.installing)
                Log.info(.system, "CatalogActivation: installing '\(entry.name)' via: \(cmd)")

                let result = shell(cmd)
                if result.exitCode != 0 {
                    let msg = "Install failed (exit \(result.exitCode)): \(result.stderr.prefix(200))"
                    Log.warn(.system, "CatalogActivation: \(msg)")
                    report(.failed(msg))
                    DispatchQueue.main.async { onComplete(.failure(ActivationError.installFailed(entry.name, msg))) }
                    return
                }

                // Verify binary is now available
                if !isAvailable(binary) {
                    let msg = "Binary '\(binary)' not found after install"
                    report(.failed(msg))
                    DispatchQueue.main.async { onComplete(.failure(ActivationError.binaryNotFound(binary))) }
                    return
                }

                Log.info(.system, "CatalogActivation: '\(entry.name)' installed successfully")
            }
        }

        // 3. Write SKILL.md
        report(.writingSkill)

        let skillDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".autoclawd/openclaw-skills/\(entry.id)")

        do {
            try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)

            let skillContent = buildSkillMD(entry)
            let skillPath = skillDir.appendingPathComponent("SKILL.md")
            try skillContent.write(to: skillPath, atomically: true, encoding: .utf8)

            Log.info(.system, "CatalogActivation: wrote SKILL.md → \(skillPath.path)")
        } catch {
            let msg = "Failed to write SKILL.md: \(error.localizedDescription)"
            report(.failed(msg))
            DispatchQueue.main.async { onComplete(.failure(ActivationError.skillWriteFailed(msg))) }
            return
        }

        // 4. Register capability
        report(.registeringCapability)

        let capability = buildCapability(from: entry, skillDir: skillDir)
        CapabilityStore.shared.save(capability)

        Log.info(.system, "CatalogActivation: registered capability '\(capability.name)'")
        report(.done)
        DispatchQueue.main.async { onComplete(.success(capability)) }
    }

    // MARK: - Deactivate

    /// Remove a catalog entry's SKILL.md and capability.
    func deactivate(_ entry: CatalogEntry) {
        queue.async {
            let skillDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".autoclawd/openclaw-skills/\(entry.id)")
            try? FileManager.default.removeItem(at: skillDir)

            // Remove from CapabilityStore
            let allCaps = CapabilityStore.shared.all()
            if let existing = allCaps.first(where: { $0.slug == entry.id }) {
                // CapabilityStore doesn't have delete, but we can overwrite with empty
                // For now, just log — full delete support can be added to CapabilityStore
                Log.info(.system, "CatalogActivation: removed SKILL.md for '\(entry.name)' (capability '\(existing.name)' remains in store)")
            }

            Log.info(.system, "CatalogActivation: deactivated '\(entry.name)'")
        }
    }

    // MARK: - Build SKILL.md

    private func buildSkillMD(_ entry: CatalogEntry) -> String {
        var lines: [String] = []
        lines.append("# \(entry.emoji) \(entry.name)")
        lines.append("")
        lines.append(entry.description)
        lines.append("")
        lines.append("## Source")
        lines.append("")
        lines.append("GitHub: \(entry.githubURL)")
        lines.append("")
        lines.append("## Install")
        lines.append("")
        if let cmd = entry.install.command {
            lines.append("```bash")
            lines.append(cmd)
            lines.append("```")
        } else if case .builtIn = entry.install {
            lines.append("Built-in macOS tool — no installation needed.")
        } else if case .manual(let instructions) = entry.install {
            lines.append(instructions)
        }
        lines.append("")
        lines.append("## Usage")
        lines.append("")
        lines.append(entry.skillTemplate)
        lines.append("")
        lines.append("## Workflow Tags")
        lines.append("")
        lines.append(entry.workflowTags.map { "- \($0)" }.joined(separator: "\n"))
        lines.append("")

        return lines.joined(separator: "\n")
    }

    // MARK: - Build Capability

    private func buildCapability(from entry: CatalogEntry, skillDir: URL) -> Capability {
        let category: CapabilityCategory
        switch entry.category {
        case .videoAudio:    category = .creative
        case .imageMedia:    category = .creative
        case .contentPublish: category = .marketing
        case .communication: category = .communication
        case .storageFiles:  category = .organization
        case .codeDev:       category = .development
        case .dataResearch:  category = .research
        case .aiProcessing:  category = .automation
        case .productivity:  category = .organization
        case .systemUtils:   category = .system
        }

        // Build install hint from catalog entry
        let installHint: InstallHint? = {
            switch entry.install {
            case .brew(let f):          return InstallHint(type: "brew", argument: f, tap: nil)
            case .brewTap(let t, let f): return InstallHint(type: "brewTap", argument: f, tap: t)
            case .pip(let p):           return InstallHint(type: "pip", argument: p, tap: nil)
            case .npm(let p):           return InstallHint(type: "npm", argument: p, tap: nil)
            case .go(let m):            return InstallHint(type: "go", argument: m, tap: nil)
            case .cargo(let c):         return InstallHint(type: "cargo", argument: c, tap: nil)
            case .manual(let i):        return InstallHint(type: "manual", argument: i, tap: nil)
            case .builtIn:              return InstallHint(type: "builtIn", argument: nil, tap: nil)
            }
        }()

        let deps = CapabilityDependencies(
            requiredBins: entry.binary.map { [$0] } ?? [],
            envVars: [:],
            installHint: installHint
        )

        return Capability(
            id: "catalog-\(entry.id)",
            name: entry.name,
            description: entry.description,
            emoji: entry.emoji,
            category: category,
            createdAt: Date(),
            triggers: CapabilityTriggers(
                apps: entry.triggerApps,
                urlPatterns: entry.triggerURLs,
                keywords: entry.triggerKeywords,
                ocrPatterns: []
            ),
            subWorkflows: [
                SubWorkflow(
                    id: "main",
                    name: "Run \(entry.name)",
                    description: entry.description,
                    invocation: entry.binary
                )
            ],
            skillMDPath: skillDir.appendingPathComponent("SKILL.md").path,
            slug: entry.id,
            source: .catalog,
            dependencies: deps,
            workflowTags: entry.workflowTags
        )
    }

    // MARK: - Shell Helpers

    private func shell(_ command: String) -> (stdout: String, stderr: String, exitCode: Int32) {
        let process = Process()
        process.launchPath = "/bin/zsh"
        process.arguments = ["-l", "-c", command]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ("", error.localizedDescription, 1)
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

        return (
            String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            process.terminationStatus
        )
    }

    private func isAvailable(_ binary: String) -> Bool {
        FileManager.default.fileExists(atPath: "/usr/local/bin/\(binary)")
            || FileManager.default.fileExists(atPath: "/opt/homebrew/bin/\(binary)")
            || shell("which \(binary)").exitCode == 0
    }
}

// MARK: - Errors

enum ActivationError: Error, LocalizedError {
    case manualInstallRequired(String)
    case installFailed(String, String)
    case binaryNotFound(String)
    case skillWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .manualInstallRequired(let name): return "\(name) requires manual installation"
        case .installFailed(let name, let msg): return "Failed to install \(name): \(msg)"
        case .binaryNotFound(let bin):          return "Binary '\(bin)' not found after install"
        case .skillWriteFailed(let msg):        return "Failed to write SKILL.md: \(msg)"
        }
    }
}
