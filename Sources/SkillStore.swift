import Foundation

// MARK: - SkillStore

/// File-based persistence for skills. Each skill is a JSON file in ~/.autoclawd/skills/.
/// User can edit these files outside the app.
final class SkillStore: @unchecked Sendable {
    let directory: URL
    private let queue = DispatchQueue(label: "com.autoclawd.skillstore", qos: .utility)

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - CRUD

    func all() -> [Skill] {
        queue.sync { _loadAll() }
    }

    func load(id: String) -> Skill? {
        queue.sync { _load(id: id) }
    }

    func save(_ skill: Skill) {
        queue.async { [self] in
            _save(skill)
        }
    }

    func delete(id: String) {
        queue.async { [self] in
            let url = fileURL(for: id)
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Seed Defaults

    func seedDefaults() {
        queue.async { [self] in
            for skill in Self.defaultSkills {
                let url = fileURL(for: skill.id)
                if !FileManager.default.fileExists(atPath: url.path) {
                    _save(skill)
                }
            }
            Log.info(.pipeline, "SkillStore: seeded \(Self.defaultSkills.count) default skills")
        }
    }

    // MARK: - Private

    private func fileURL(for id: String) -> URL {
        directory.appendingPathComponent("\(id).json")
    }

    private func _loadAll() -> [Skill] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Skill? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(Skill.self, from: data)
            }
            .sorted { $0.id < $1.id }
    }

    private func _load(id: String) -> Skill? {
        let url = fileURL(for: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Skill.self, from: data)
    }

    private func _save(_ skill: Skill) {
        let url = fileURL(for: skill.id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(skill) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Default Skills

    static let defaultSkills: [Skill] = [
        // Pipeline skills
        Skill(
            id: "transcript-cleaning",
            name: "Transcript Cleaning",
            description: "Cleans and denoises raw spoken transcripts. Removes filler words, fixes grammar, merges broken sentences.",
            promptTemplate: """
            Clean this spoken transcript. Remove filler words (um, uh, like, you know, so, basically), fix grammar, merge broken sentences across chunk boundaries. Keep ALL meaning and intent intact. Output ONLY the cleaned text, nothing else.

            RAW TRANSCRIPT:
            {{transcript}}

            CLEANED:
            """,
            workflowID: nil,
            category: .pipeline,
            isBuiltin: true
        ),
        Skill(
            id: "transcript-analysis",
            name: "Transcript Analysis",
            description: "Deeply analyzes cleaned transcripts to understand context, determine project, identify people, and create actionable task prompts.",
            promptTemplate: """
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
            """,
            workflowID: nil,
            category: .pipeline,
            isBuiltin: true
        ),
        Skill(
            id: "task-creation",
            name: "Task Execution Planning",
            description: "Determines the best skill, workflow, and certainty level for executing a task.",
            promptTemplate: """
            You are planning how to execute a task. Determine the best approach.

            AVAILABLE SKILLS: {{skill_list}}
            TASK TITLE: {{title}}
            TASK PROMPT: {{prompt}}
            PROJECT: {{project}}

            Output EXACTLY this format:
            SKILL: <skill id from the list, or "general">
            CERTAINTY: <high/medium/low - can this be done autonomously without human input?>
            NEEDS_INPUT: <what specific input is needed from the user, or "NONE">
            """,
            workflowID: nil,
            category: .pipeline,
            isBuiltin: true
        ),
        // Execution skills
        Skill(
            id: "frontend-design",
            name: "Frontend Design",
            description: "UI changes, component creation, styling, layout modifications in web or native apps.",
            promptTemplate: "{{prompt}}",
            workflowID: "autoclawd-claude-code",
            category: .development,
            isBuiltin: true
        ),
        Skill(
            id: "data-analysis",
            name: "Data Analysis",
            description: "Data aggregation, clustering, summarization, and insight generation.",
            promptTemplate: "{{prompt}}",
            workflowID: nil,
            category: .analysis,
            isBuiltin: true
        ),
        Skill(
            id: "project-management",
            name: "Project Management",
            description: "Task scheduling, sprint planning, team coordination, and status tracking.",
            promptTemplate: "{{prompt}}",
            workflowID: "autoclawd-claude-code-linear",
            category: .management,
            isBuiltin: true
        ),
        Skill(
            id: "video-generation",
            name: "Video Generation",
            description: "Create videos using AI image generation for first/last frames and video interpolation.",
            promptTemplate: "{{prompt}}",
            workflowID: "autoclawd-freepik",
            category: .creative,
            isBuiltin: true
        ),
        Skill(
            id: "campaign-activation",
            name: "Campaign Activation",
            description: "Activate and manage marketing campaigns across platforms.",
            promptTemplate: "{{prompt}}",
            workflowID: "autoclawd-claude-code-meta",
            category: .marketing,
            isBuiltin: true
        ),
    ]
}
