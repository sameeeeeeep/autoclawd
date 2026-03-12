import Foundation

// MARK: - OpenClawSkillLoader

/// Loads OpenClaw-compatible skills from SKILL.md files.
///
/// Real OpenClaw SKILL.md format uses YAML frontmatter with JSON metadata:
/// ```
/// ---
/// name: himalaya
/// description: "CLI to manage emails via IMAP/SMTP..."
/// homepage: https://github.com/pimalaya/himalaya
/// metadata: { "openclaw": { "emoji": "📧", "requires": { "bins": ["himalaya"] } } }
/// ---
///
/// # Himalaya Email CLI
/// ...instructions...
/// ```
///
/// Skills are discovered by recursively scanning a directory for SKILL.md files.
/// Each skill directory can also contain supporting files (references/, scripts/)
/// referenced by the instructions.
final class OpenClawSkillLoader {

    /// Scan a directory recursively for SKILL.md files and parse them into Skill objects.
    static func loadSkills(from directory: URL) -> [Skill] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else {
            Log.info(.pipeline, "OpenClawSkillLoader: directory does not exist: \(directory.path)")
            return []
        }

        var skills: [Skill] = []

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            Log.warn(.pipeline, "OpenClawSkillLoader: cannot enumerate \(directory.path)")
            return []
        }

        for case let fileURL as URL in enumerator {
            let fileName = fileURL.lastPathComponent
            // Accept SKILL.md (OpenClaw convention) and *.skill.md (alternative)
            guard fileName == "SKILL.md" || fileName.hasSuffix(".skill.md") else { continue }

            if let skill = parseSkillMD(at: fileURL) {
                skills.append(skill)
                Log.info(.pipeline, "OpenClawSkillLoader: loaded skill '\(skill.name)' from \(fileURL.path)")
            } else {
                Log.warn(.pipeline, "OpenClawSkillLoader: failed to parse \(fileURL.path)")
            }
        }

        Log.info(.pipeline, "OpenClawSkillLoader: loaded \(skills.count) skills from \(directory.path)")
        return skills
    }

    /// Parse a single SKILL.md file into a Skill.
    static func parseSkillMD(at url: URL) -> Skill? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        let (frontmatter, body) = splitFrontmatter(content)
        let metadata = parseFrontmatter(frontmatter)

        // Derive skill ID from directory name or frontmatter
        let skillDir = url.deletingLastPathComponent()
        let dirName = skillDir.lastPathComponent
        let id = "openclaw-" + (metadata["name"] as? String ?? dirName)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")

        let name = metadata["name"] as? String ?? dirName
        let description = metadata["description"] as? String ?? "OpenClaw skill: \(name)"

        // Parse required binaries from multiple possible locations:
        // 1. metadata.openclaw.requires.bins (real OpenClaw format - JSON in YAML)
        // 2. requires.bins (flat YAML format)
        // 3. bins (top-level flat format)
        var requiredBins: [String] = []
        requiredBins = extractRequiredBins(from: metadata)

        // Parse environment variables from:
        // 1. requires.env (some skills use this)
        // 2. env (top-level)
        var envVars: [String: String] = [:]
        if let requires = metadata["requires"] as? [String: Any],
           let envList = requires["env"] as? [String] {
            for envKey in envList {
                envVars[envKey] = ""
            }
        }
        if let env = metadata["env"] as? [String: Any] {
            for (key, value) in env {
                envVars[key] = "\(value)"
            }
        }

        // Parse category from metadata or infer from content
        let categoryStr = metadata["category"] as? String ?? ""
        let category = categoryStr.isEmpty ? inferCategory(name: name, description: description) : mapCategory(categoryStr)

        // Extract emoji from metadata.openclaw.emoji
        let emoji = extractEmoji(from: metadata)

        // The markdown body IS the instructions
        let instructions = body.trimmingCharacters(in: .whitespacesAndNewlines)

        // Build prompt template — OpenClaw skills use instructions as context + the task prompt
        let promptTemplate = """
        {{instructions}}

        ---

        TASK: {{prompt}}
        """

        return Skill(
            id: id,
            name: emoji != nil ? "\(emoji!) \(name)" : name,
            description: description,
            promptTemplate: promptTemplate,
            workflowID: "autoclawd-openclaw",
            category: category,
            isBuiltin: false,
            instructions: instructions.isEmpty ? nil : instructions,
            requiredBins: requiredBins.isEmpty ? nil : requiredBins,
            envVars: envVars.isEmpty ? nil : envVars,
            isOpenClaw: true,
            skillMDPath: url.path
        )
    }

    // MARK: - Capability Conversion

    /// Scan a directory for SKILL.md files and convert them to Capability objects.
    /// Injects trigger tags from SkillTagRegistry for auto-detection.
    static func loadCapabilities(from directory: URL) -> [Capability] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }

        var capabilities: [Capability] = []

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for case let fileURL as URL in enumerator {
            let fileName = fileURL.lastPathComponent
            guard fileName == "SKILL.md" || fileName.hasSuffix(".skill.md") else { continue }

            if let cap = loadCapability(at: fileURL) {
                capabilities.append(cap)
            }
        }

        Log.info(.pipeline, "OpenClawSkillLoader: converted \(capabilities.count) skills → capabilities")
        return capabilities
    }

    /// Parse a single SKILL.md into a Capability with SkillTagRegistry trigger injection.
    static func loadCapability(at url: URL) -> Capability? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        let (frontmatter, body) = splitFrontmatter(content)
        let metadata = parseFrontmatter(frontmatter)

        let skillDir = url.deletingLastPathComponent()
        let dirName = skillDir.lastPathComponent

        let name = metadata["name"] as? String ?? dirName
        let description = metadata["description"] as? String ?? "OpenClaw skill: \(name)"
        let requiredBins = extractRequiredBins(from: metadata)
        let emoji = extractEmoji(from: metadata) ?? "🔧"
        let instructions = body.trimmingCharacters(in: .whitespacesAndNewlines)

        // Category: from metadata, then infer
        let categoryStr = metadata["category"] as? String ?? ""
        let skillCategory = categoryStr.isEmpty
            ? inferCategory(name: name, description: description)
            : mapCategory(categoryStr)
        let capCategory = mapSkillCategoryToCapabilityCategory(skillCategory)

        // Inject trigger tags from SkillTagRegistry
        let tags = SkillTagRegistry.tags(for: dirName)

        // Parse env vars
        var envVars: [String: String] = [:]
        if let requires = metadata["requires"] as? [String: Any],
           let envList = requires["env"] as? [String] {
            for envKey in envList { envVars[envKey] = "" }
        }
        if let env = metadata["env"] as? [String: Any] {
            for (key, value) in env { envVars[key] = "\(value)" }
        }

        let deps = CapabilityDependencies(
            requiredBins: requiredBins,
            envVars: envVars,
            installHint: nil  // OpenClaw skills don't have install info in SKILL.md
        )

        let id = "openclaw-" + name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")

        let promptTemplate = """
        {{instructions}}

        ---

        TASK: {{prompt}}
        """

        return Capability(
            id: id,
            name: name,
            description: description,
            emoji: emoji,
            category: capCategory,
            createdAt: Date(),
            triggers: CapabilityTriggers(
                apps: tags?.apps ?? [],
                urlPatterns: tags?.urls ?? [],
                keywords: tags?.keywords ?? [],
                ocrPatterns: []
            ),
            subWorkflows: [
                SubWorkflow(
                    id: "main",
                    name: "Run \(name)",
                    description: description,
                    invocation: requiredBins.first
                )
            ],
            skillMDPath: url.path,
            slug: dirName,
            source: .openclaw,
            dependencies: deps,
            promptTemplate: promptTemplate,
            instructions: instructions.isEmpty ? nil : instructions,
            workflowTags: tags?.workflowTags ?? []
        )
    }

    /// Map SkillCategory → CapabilityCategory for unified model.
    static func mapSkillCategoryToCapabilityCategory(_ sc: SkillCategory) -> CapabilityCategory {
        switch sc {
        case .pipeline:      return .automation
        case .development:   return .development
        case .analysis:      return .analysis
        case .management:    return .organization
        case .creative:      return .creative
        case .marketing:     return .marketing
        case .search:        return .search
        case .communication: return .communication
        case .automation:    return .automation
        case .system:        return .system
        case .other:         return .automation
        }
    }

    // MARK: - Metadata Extraction

    /// Extract required binaries from metadata, handling all OpenClaw formats.
    private static func extractRequiredBins(from metadata: [String: Any]) -> [String] {
        // Format 1: metadata.openclaw.requires.bins (real OpenClaw JSON format)
        if let metadataObj = metadata["metadata"] as? [String: Any],
           let openclaw = metadataObj["openclaw"] as? [String: Any],
           let requires = openclaw["requires"] as? [String: Any],
           let bins = requires["bins"] as? [String] {
            return bins
        }

        // Format 2: requires.bins (flat YAML)
        if let requires = metadata["requires"] as? [String: Any],
           let bins = requires["bins"] as? [String] {
            return bins
        }

        // Format 3: flat bins list
        if let bins = metadata["bins"] as? [String] {
            return bins
        }

        return []
    }

    /// Extract emoji from metadata.openclaw.emoji
    private static func extractEmoji(from metadata: [String: Any]) -> String? {
        if let metadataObj = metadata["metadata"] as? [String: Any],
           let openclaw = metadataObj["openclaw"] as? [String: Any],
           let emoji = openclaw["emoji"] as? String {
            return emoji
        }
        return nil
    }

    /// Infer category from skill name and description when not explicitly set.
    private static func inferCategory(name: String, description: String) -> SkillCategory {
        let combined = (name + " " + description).lowercased()
        if combined.contains("email") || combined.contains("slack") || combined.contains("discord") || combined.contains("message") || combined.contains("chat") || combined.contains("reminder") {
            return .communication
        }
        if combined.contains("search") || combined.contains("research") || combined.contains("summarize") || combined.contains("browse") || combined.contains("web") || combined.contains("fetch") {
            return .search
        }
        if combined.contains("github") || combined.contains("code") || combined.contains("coding") || combined.contains("git") || combined.contains("pr ") || combined.contains("issue") {
            return .development
        }
        if combined.contains("weather") || combined.contains("stock") || combined.contains("price") || combined.contains("api") {
            return .automation
        }
        if combined.contains("image") || combined.contains("video") || combined.contains("audio") || combined.contains("music") || combined.contains("spotify") || combined.contains("photo") {
            return .creative
        }
        if combined.contains("note") || combined.contains("todo") || combined.contains("task") || combined.contains("project") || combined.contains("trello") || combined.contains("notion") {
            return .management
        }
        return .other
    }

    // MARK: - Frontmatter Parsing

    /// Split a SKILL.md into YAML frontmatter and markdown body.
    /// Frontmatter is delimited by `---` at the start and end.
    private static func splitFrontmatter(_ content: String) -> (String, String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for --- delimiter
        guard trimmed.hasPrefix("---") else {
            // No frontmatter — entire content is the body
            return ("", content)
        }

        // Find the closing ---
        let afterFirst = trimmed.dropFirst(3).trimmingCharacters(in: .newlines)
        guard let closingRange = afterFirst.range(of: "\n---") else {
            // No closing --- — treat everything after first --- as frontmatter
            return (afterFirst, "")
        }

        let frontmatter = String(afterFirst[afterFirst.startIndex..<closingRange.lowerBound])
        let bodyStart = afterFirst.index(closingRange.upperBound, offsetBy: 0)
        let body = String(afterFirst[bodyStart...])

        return (frontmatter, body)
    }

    /// Parse YAML frontmatter that may contain JSON values (OpenClaw format).
    ///
    /// Handles:
    /// - Simple key: value pairs
    /// - Inline JSON values: `metadata: { "openclaw": { ... } }`
    /// - Multi-line JSON values (continued lines starting with { or whitespace)
    /// - Simple YAML lists (- item)
    /// - One-level nested YAML maps
    private static func parseFrontmatter(_ yaml: String) -> [String: Any] {
        var result: [String: Any] = [:]
        let lines = yaml.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = line.prefix(while: { $0 == " " }).count

            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                i += 1
                continue
            }

            // Only process top-level keys (indent == 0)
            guard indent == 0 else {
                i += 1
                continue
            }

            // Find the key
            if let colonRange = trimmed.range(of: ":") {
                let key = String(trimmed[trimmed.startIndex..<colonRange.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
                let afterColon = String(trimmed[colonRange.upperBound...])
                    .trimmingCharacters(in: .whitespaces)

                if afterColon.isEmpty {
                    // Key with no inline value — could be YAML map, list, or multi-line JSON
                    i += 1
                    let (value, newIndex) = parseBlock(lines: lines, startIndex: i, baseIndent: 0)
                    result[key] = value
                    i = newIndex
                } else if afterColon.hasPrefix("{") || afterColon.hasPrefix("[") {
                    // Inline JSON value — collect all lines until JSON is balanced
                    i += 1
                    let (jsonValue, newIndex) = collectJSON(firstPart: afterColon, lines: lines, startIndex: i)
                    result[key] = jsonValue
                    i = newIndex
                } else {
                    // Simple scalar value
                    let cleaned = afterColon
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    result[key] = cleaned
                    i += 1
                }
            } else {
                i += 1
            }
        }

        return result
    }

    /// Parse a YAML block (list or map) starting at the given index.
    /// Returns the parsed value and the next line index to process.
    private static func parseBlock(lines: [String], startIndex: Int, baseIndent: Int) -> (Any, Int) {
        guard startIndex < lines.count else { return ([:] as [String: Any], startIndex) }

        let firstLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
        let _ = lines[startIndex].prefix(while: { $0 == " " }).count

        // If the first indented line starts with JSON
        if firstLine.hasPrefix("{") || firstLine.hasPrefix("[") {
            let (jsonValue, newIndex) = collectJSON(firstPart: firstLine, lines: lines, startIndex: startIndex + 1)
            return (jsonValue, newIndex)
        }

        // Check if this is a list (starts with "- ")
        if firstLine.hasPrefix("- ") {
            var list: [String] = []
            var idx = startIndex
            while idx < lines.count {
                let l = lines[idx]
                let lTrimmed = l.trimmingCharacters(in: .whitespaces)
                let lIndent = l.prefix(while: { $0 == " " }).count
                if lTrimmed.isEmpty { idx += 1; continue }
                guard lIndent > baseIndent, lTrimmed.hasPrefix("- ") else { break }
                list.append(String(lTrimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                idx += 1
            }
            return (list, idx)
        }

        // Otherwise it's a map
        var map: [String: Any] = [:]
        var idx = startIndex
        while idx < lines.count {
            let l = lines[idx]
            let lTrimmed = l.trimmingCharacters(in: .whitespaces)
            let lIndent = l.prefix(while: { $0 == " " }).count
            if lTrimmed.isEmpty { idx += 1; continue }
            guard lIndent > baseIndent else { break }

            if let colonRange = lTrimmed.range(of: ":") {
                let nestedKey = String(lTrimmed[lTrimmed.startIndex..<colonRange.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
                let afterColon = String(lTrimmed[colonRange.upperBound...])
                    .trimmingCharacters(in: .whitespaces)

                if afterColon.isEmpty {
                    // Nested block
                    idx += 1
                    let (nestedValue, newIdx) = parseBlock(lines: lines, startIndex: idx, baseIndent: lIndent)
                    map[nestedKey] = nestedValue
                    idx = newIdx
                } else if afterColon.hasPrefix("{") || afterColon.hasPrefix("[") {
                    idx += 1
                    let (jsonValue, newIdx) = collectJSON(firstPart: afterColon, lines: lines, startIndex: idx)
                    map[nestedKey] = jsonValue
                    idx = newIdx
                } else {
                    map[nestedKey] = afterColon.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    idx += 1
                }
            } else {
                idx += 1
            }
        }
        return (map, idx)
    }

    /// Collect a JSON value that may span multiple lines, parse it, and return the result.
    private static func collectJSON(firstPart: String, lines: [String], startIndex: Int) -> (Any, Int) {
        var jsonStr = firstPart
        var idx = startIndex

        // Check if JSON is already balanced
        if isBalancedJSON(jsonStr) {
            return (parseJSONValue(jsonStr), idx)
        }

        // Collect more lines until balanced
        while idx < lines.count {
            let line = lines[idx]
            jsonStr += "\n" + line
            idx += 1
            if isBalancedJSON(jsonStr) {
                break
            }
        }

        return (parseJSONValue(jsonStr), idx)
    }

    /// Check if braces/brackets are balanced in a JSON string.
    private static func isBalancedJSON(_ str: String) -> Bool {
        var braces = 0
        var brackets = 0
        var inString = false
        var prev: Character = " "

        for ch in str {
            if ch == "\"" && prev != "\\" { inString = !inString }
            if !inString {
                if ch == "{" { braces += 1 }
                if ch == "}" { braces -= 1 }
                if ch == "[" { brackets += 1 }
                if ch == "]" { brackets -= 1 }
            }
            prev = ch
        }

        return braces == 0 && brackets == 0
    }

    /// Parse a JSON string into Swift dictionary/array/value.
    /// Falls back to the raw string if parsing fails.
    private static func parseJSONValue(_ jsonStr: String) -> Any {
        // OpenClaw uses relaxed JSON (trailing commas, unquoted keys sometimes)
        // Try standard JSON first, then try cleaning it up
        let cleaned = cleanJSON(jsonStr)
        guard let data = cleaned.data(using: .utf8) else { return jsonStr }

        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            return obj
        } catch {
            // Try even more aggressive cleaning
            let aggressive = aggressiveCleanJSON(jsonStr)
            if let data2 = aggressive.data(using: .utf8),
               let obj2 = try? JSONSerialization.jsonObject(with: data2, options: [.fragmentsAllowed]) {
                return obj2
            }
            Log.warn(.pipeline, "OpenClawSkillLoader: failed to parse JSON: \(error.localizedDescription)")
            return jsonStr
        }
    }

    /// Clean relaxed JSON (remove trailing commas, etc.) for standard parsing.
    private static func cleanJSON(_ json: String) -> String {
        var result = json
        // Remove trailing commas before } or ]
        // This handles OpenClaw's relaxed JSON format
        let trailingCommaPattern = ",\\s*([}\\]])"
        if let regex = try? NSRegularExpression(pattern: trailingCommaPattern, options: []) {
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "$1"
            )
        }
        return result
    }

    /// More aggressive JSON cleaning for edge cases.
    private static func aggressiveCleanJSON(_ json: String) -> String {
        var result = cleanJSON(json)
        // Replace single quotes with double quotes (some YAML-style JSON uses single quotes)
        // But be careful not to replace quotes inside strings
        result = result.replacingOccurrences(of: "'", with: "\"")
        return result
    }

    // MARK: - Category Mapping

    /// Map OpenClaw category strings to SkillCategory.
    private static func mapCategory(_ raw: String) -> SkillCategory {
        let lower = raw.lowercased()
        switch lower {
        case "pipeline":
            return .pipeline
        case "development", "coding", "dev", "code", "frontend", "backend", "web":
            return .development
        case "analysis", "data", "data-analysis":
            return .analysis
        case "management", "project-management", "project", "pm":
            return .management
        case "creative", "image", "video", "design", "art":
            return .creative
        case "marketing", "campaign", "ads":
            return .marketing
        case "search", "research", "web-search", "browse", "browser":
            return .search
        case "communication", "email", "messaging", "chat", "notify", "reminder", "reminders":
            return .communication
        case "automation", "shell", "script", "file", "files", "devops", "cloud", "infra":
            return .automation
        case "system", "utility", "config", "settings":
            return .system
        default:
            return .other
        }
    }
}
