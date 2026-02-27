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
