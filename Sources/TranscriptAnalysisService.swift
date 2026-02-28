import Foundation

// MARK: - TranscriptAnalysisService

/// Stage 2: Deep semantic analysis of cleaned transcripts.
/// Determines project, priority, people, tags, and creates task prompts.
/// Dot-words ("dot p0") are optional speedup hints, not the sole source of analysis.
final class TranscriptAnalysisService: @unchecked Sendable {
    private let ollama: OllamaService
    private let projectStore: ProjectStore
    private let pipelineStore: PipelineStore
    private let skillStore: SkillStore

    init(ollama: OllamaService, projectStore: ProjectStore,
         pipelineStore: PipelineStore, skillStore: SkillStore) {
        self.ollama = ollama
        self.projectStore = projectStore
        self.pipelineStore = pipelineStore
        self.skillStore = skillStore
    }

    // MARK: - Public API

    func analyze(cleaned: CleanedTranscript) async -> TranscriptAnalysis? {
        // 1. Pre-LLM: detect dot-words as hints
        let dotWords = Self.detectDotWords(in: cleaned.cleanedText)
        let dotPriority = dotWords.first(where: { $0.hasPrefix("p") })

        // 2. Build context for LLM
        let projects = projectStore.all()
        let projectList = projects.isEmpty
            ? "none"
            : projects.map(\.name).joined(separator: ", ")

        let dotHints: String
        if !dotWords.isEmpty {
            dotHints = "DETECTED DOT-WORDS: \(dotWords.joined(separator: ", "))"
        } else {
            dotHints = ""
        }

        // 3. LLM call: full semantic analysis
        let skill = skillStore.load(id: "transcript-analysis")
        let template = skill?.promptTemplate ?? Self.defaultAnalysisPrompt

        let prompt = template
            .replacingOccurrences(of: "{{project_list}}", with: projectList)
            .replacingOccurrences(of: "{{dot_word_hints}}", with: dotHints)
            .replacingOccurrences(of: "{{transcript}}", with: cleaned.cleanedText)

        let response: String
        do {
            response = try await ollama.generate(prompt: prompt, numPredict: 1024)
        } catch {
            Log.error(.analysis, "Stage 2 LLM failed: \(error.localizedDescription)")
            return nil
        }

        // 4. Parse response into analysis blocks
        let blocks = parseAnalysisBlocks(response)
        guard !blocks.isEmpty else {
            Log.warn(.analysis, "Stage 2: no valid blocks parsed from response")
            // Create a minimal analysis with just a summary
            let minimal = TranscriptAnalysis(
                id: UUID().uuidString,
                cleanedTranscriptID: cleaned.id,
                priority: dotPriority,
                projectName: nil,
                projectID: nil,
                personNames: [],
                tags: [],
                summary: String(cleaned.cleanedText.prefix(80)),
                taskDescriptions: [],
                timestamp: Date()
            )
            pipelineStore.insertAnalysis(minimal)
            return minimal
        }

        // 5. Use the first block for primary analysis fields, collect all task descriptions
        let primary = blocks[0]
        var allTaskDescs: [AnalysisTaskDesc] = []
        for block in blocks {
            if let title = block["TASK_TITLE"], title != "NONE", !title.isEmpty,
               let prompt = block["TASK_PROMPT"], prompt != "NONE", !prompt.isEmpty {
                allTaskDescs.append(AnalysisTaskDesc(title: title, prompt: prompt))
            }
        }

        // 6. Resolve project
        let rawProjectName = primary["PROJECT"]
        let resolvedProject: (name: String?, id: String?) = resolveProject(
            rawName: rawProjectName, projects: projects
        )

        // 7. Parse people
        let peopleRaw = primary["PEOPLE"] ?? ""
        let people = peopleRaw == "none" || peopleRaw.isEmpty
            ? []
            : peopleRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        // 8. Parse priority — use dot-word if detected, otherwise from LLM
        let llmPriority = primary["PRIORITY"]
        let priority = dotPriority ?? (llmPriority == "none" ? nil : llmPriority)

        // 9. Parse tags
        let tagsRaw = primary["TAGS"] ?? ""
        let tags = tagsRaw == "none" || tagsRaw.isEmpty
            ? []
            : tagsRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        // 10. Summary
        let summary = primary["SUMMARY"] ?? String(cleaned.cleanedText.prefix(80))

        let analysis = TranscriptAnalysis(
            id: UUID().uuidString,
            cleanedTranscriptID: cleaned.id,
            priority: priority,
            projectName: resolvedProject.name,
            projectID: resolvedProject.id,
            personNames: people,
            tags: tags,
            summary: summary,
            taskDescriptions: allTaskDescs,
            timestamp: Date()
        )

        pipelineStore.insertAnalysis(analysis)

        Log.info(.analysis, "Stage 2 done: project=\(resolvedProject.name ?? "none"), " +
                 "priority=\(priority ?? "none"), tasks=\(allTaskDescs.count), tags=\(tags.joined(separator: ","))")

        return analysis
    }

    // MARK: - Dot-Word Detection

    /// Detect patterns like "dot p0", "dot p1", "dot bug", ".p0", etc.
    /// These are optional speed-up hints, not the sole source of analysis.
    static func detectDotWords(in text: String) -> [String] {
        let pattern = #"\b(?:dot|\.)\s*(p[0-3]|bug|feature|question|blocker|personal|info)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        return matches.compactMap { match in
            guard match.numberOfRanges >= 2,
                  let wordRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[wordRange]).lowercased()
        }
    }

    // MARK: - Response Parsing

    /// Parse the LLM response into blocks separated by "---".
    /// Each block has KEY: VALUE pairs.
    private func parseAnalysisBlocks(_ response: String) -> [[String: String]] {
        let rawBlocks = response.components(separatedBy: "---")
        var results: [[String: String]] = []

        for rawBlock in rawBlocks {
            var block: [String: String] = [:]
            let lines = rawBlock.components(separatedBy: "\n")

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                // Parse "KEY: value" format
                if let colonRange = trimmed.range(of: ": ") {
                    let key = String(trimmed[trimmed.startIndex..<colonRange.lowerBound])
                        .trimmingCharacters(in: .whitespaces)
                        .uppercased()
                    let value = String(trimmed[colonRange.upperBound...])
                        .trimmingCharacters(in: .whitespaces)

                    // Only accept known keys
                    let knownKeys = ["PROJECT", "PEOPLE", "PRIORITY", "TAGS", "SUMMARY", "TASK_TITLE", "TASK_PROMPT"]
                    if knownKeys.contains(key) {
                        block[key] = value
                    }
                }
            }

            // Only include blocks that have at least a SUMMARY
            if block["SUMMARY"] != nil || block["TASK_TITLE"] != nil {
                results.append(block)
            }
        }

        return results
    }

    // MARK: - Project Resolution

    private func resolveProject(rawName: String?, projects: [Project]) -> (name: String?, id: String?) {
        guard let name = rawName, name != "none", !name.isEmpty else {
            return (nil, nil)
        }

        // Exact match (case-insensitive)
        if let match = projects.first(where: { $0.name.lowercased() == name.lowercased() }) {
            return (match.name, match.id)
        }

        // Partial match
        if let match = projects.first(where: { $0.name.lowercased().contains(name.lowercased()) }) {
            return (match.name, match.id)
        }

        // No match found — return raw name without ID
        return (name, nil)
    }

    // MARK: - Default Prompt

    private static let defaultAnalysisPrompt = """
        You are analyzing a spoken transcript to understand context, intent, and create actionable tasks.

        KNOWN PROJECTS: {{project_list}}
        {{dot_word_hints}}

        TRANSCRIPT:
        {{transcript}}

        For each distinct action or topic, output a block in this format (separate multiple blocks with ---):
        PROJECT: <project name from the list above, or "none">
        PEOPLE: <comma-separated names mentioned, or "none">
        PRIORITY: <p0/p1/p2/p3 if mentioned or implied, or "none">
        TAGS: <comma-separated from: bug, feature, question, schedule-change, personal, info, decision>
        SUMMARY: <one line understanding of what this is about>
        TASK_TITLE: <imperative action title, max 10 words, or "NONE" if no action needed>
        TASK_PROMPT: <detailed instruction for an AI to execute this task, or "NONE">

        If the transcript is casual talk with no actionable content, output only:
        SUMMARY: <brief note>
        TASK_TITLE: NONE
        """
}
