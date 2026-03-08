import Foundation

enum MCPConfigManager {

    private static let configURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".autoclawd")
        .appendingPathComponent("mcp-config.json")

    /// Returns the path to the MCP config file, creating/updating it if needed.
    /// Returns nil if the autoclawd-mcp binary cannot be found.
    static func configPath() -> String? {
        guard let mcpBinaryPath = findMCPBinary() else {
            return nil
        }

        let config: [String: Any] = [
            "mcpServers": [
                "autoclawd": [
                    "type": "stdio",
                    "command": mcpBinaryPath,
                    "args": [] as [String]
                ] as [String: Any]
            ]
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted])
            try data.write(to: configURL, options: .atomic)
            return configURL.path
        } catch {
            Log.error(.system, "Failed to write MCP config: \(error)")
            return nil
        }
    }

    // MARK: - Claude Code Hooks Config

    /// Write (or merge) AutoClawd hook entries into ~/.claude/settings.json.
    ///
    /// Registers `PostToolUse` and `Stop` hooks that curl the AutoClawd hook
    /// endpoint on every Claude Code tool event. This lets AutoClawd narrate
    /// what Claude Code is doing in real time inside the call room feed.
    ///
    /// Safe to call repeatedly — only the `hooks` key is overwritten; all
    /// other existing settings are preserved.
    static func writeHooksConfig() {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("settings.json")

        // Load existing settings or start fresh
        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        }

        let hookCommand = "curl -s -X POST http://localhost:7892/hook -H 'Content-Type: application/json' -d @-"
        let hookEntry: [String: Any] = ["type": "command", "command": hookCommand]
        let hookGroup: [String: Any] = ["matcher": "", "hooks": [hookEntry]]

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        hooks["PostToolUse"] = [hookGroup]
        hooks["Stop"]        = [hookGroup]
        settings["hooks"]    = hooks

        do {
            try FileManager.default.createDirectory(
                at: settingsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            let data = try JSONSerialization.data(
                withJSONObject: settings,
                options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(to: settingsURL, options: .atomic)
            Log.info(.system, "MCPConfigManager: hooks written to \(settingsURL.path)")
        } catch {
            Log.warn(.system, "MCPConfigManager: failed to write hooks config — \(error)")
        }
    }

    private static func findMCPBinary() -> String? {
        // 1. Inside the app bundle (distribution)
        let bundleBinary = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/autoclawd-mcp").path
        if FileManager.default.isExecutableFile(atPath: bundleBinary) {
            return bundleBinary
        }
        // 2. Sibling of the app bundle (development — build/ directory)
        let siblingBinary = Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("autoclawd-mcp").path
        if FileManager.default.isExecutableFile(atPath: siblingBinary) {
            return siblingBinary
        }
        // 3. Well-known install path
        let homeBinary = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".autoclawd/autoclawd-mcp").path
        if FileManager.default.isExecutableFile(atPath: homeBinary) {
            return homeBinary
        }
        return nil
    }
}
