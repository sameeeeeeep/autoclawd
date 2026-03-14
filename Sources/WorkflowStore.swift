import Foundation

// MARK: - WorkflowStore
//
// Persists workflow records to:
//   ~/.autoclawd/workflows/index.json
//
// Follows the same singleton + DispatchQueue pattern as CapabilityStore.
// Seeds pre-built workflows on first run when the index is empty.

final class WorkflowStore: @unchecked Sendable {

    static let shared = WorkflowStore()
    private init() { load() }

    private let queue = DispatchQueue(label: "com.autoclawd.workflow-store", qos: .utility)
    private var workflows: [WorkflowRecord] = []

    // MARK: - Persistence

    private var indexURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".autoclawd/workflows/index.json")
    }

    private func load() {
        queue.async { [weak self] in
            guard let self else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let data = try? Data(contentsOf: self.indexURL),
                  let decoded = try? decoder.decode([WorkflowRecord].self, from: data)
            else { return }
            self.workflows = decoded
            Log.info(.system, "WorkflowStore: loaded \(decoded.count) workflow(s)")
        }
    }

    /// Save (or update) a workflow. Deduplicates by id.
    func save(_ workflow: WorkflowRecord) {
        queue.async { [weak self] in
            guard let self else { return }
            if let idx = self.workflows.firstIndex(where: { $0.id == workflow.id }) {
                self.workflows[idx] = workflow
            } else {
                self.workflows.append(workflow)
            }
            self.persist()
            Log.info(.system, "WorkflowStore: saved '\(workflow.name)' (total: \(self.workflows.count))")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .workflowStoreDidChange, object: nil)
            }
        }
    }

    /// Delete a workflow by id.
    func delete(id: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.workflows.removeAll { $0.id == id }
            self.persist()
            Log.info(.system, "WorkflowStore: deleted workflow \(id) (total: \(self.workflows.count))")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .workflowStoreDidChange, object: nil)
            }
        }
    }

    /// All workflows (thread-safe snapshot).
    func all() -> [WorkflowRecord] {
        queue.sync { workflows }
    }

    /// Find a workflow by id.
    func find(id: String) -> WorkflowRecord? {
        queue.sync { workflows.first { $0.id == id } }
    }

    /// Find workflows by category.
    func byCategory(_ category: WorkflowCategory) -> [WorkflowRecord] {
        queue.sync { workflows.filter { $0.category == category } }
    }

    private func persist() {
        let dir = indexURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(workflows) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    // MARK: - Seed Pre-Built Workflows

    /// Seeds representative workflows on first run (empty index).
    func seedPrebuiltWorkflowsIfNeeded() {
        queue.async { [weak self] in
            guard let self, self.workflows.isEmpty else { return }
            let seeded = Self.prebuiltWorkflows()
            self.workflows = seeded
            self.persist()
            Log.info(.system, "WorkflowStore: seeded \(seeded.count) pre-built workflow(s)")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .workflowStoreDidChange, object: nil)
            }
        }
    }

    // MARK: - Pre-Built Workflow Definitions

    private static func prebuiltWorkflows() -> [WorkflowRecord] {
        let now = Date()
        return [
            launchVideoWorkflow(now),
            bugToPRWorkflow(now),
            meetingToActionsWorkflow(now),
            researchBriefWorkflow(now),
            contentRepurposeWorkflow(now),
            imageFormatConvertWorkflow(now),
        ]
    }

    // 1. Launch Video — the flagship workflow from product.md
    private static func launchVideoWorkflow(_ now: Date) -> WorkflowRecord {
        WorkflowRecord(
            id: "WF-LAUNCH01",
            name: "Launch Video",
            description: "End-to-end launch video: download references, extract frames + transcript, build content strategy, generate motion graphics, AI voice, assemble, upload, and share.",
            emoji: "\u{1F3AC}",
            category: .content,
            createdAt: now,
            steps: [
                WorkflowStep(
                    id: "s1", order: 0,
                    name: "Download reference videos",
                    description: "Download reference videos from provided URLs using yt-dlp",
                    capabilityID: nil, skillSlug: "xurl",
                    promptTemplate: "Download these video URLs to a temporary directory: {{reference_urls}}",
                    inputMapping: ["reference_urls": "references.urls"],
                    outputKey: "video_paths"
                ),
                WorkflowStep(
                    id: "s2", order: 1,
                    name: "Ingest videos to AI",
                    description: "Extract frames + Whisper transcript from each video for AI analysis",
                    capabilityID: nil, skillSlug: "video-frames",
                    promptTemplate: "Extract frames and transcripts from these videos: {{video_paths}}",
                    inputMapping: ["video_paths": "video_paths"],
                    outputKey: "video_analysis"
                ),
                WorkflowStep(
                    id: "s3", order: 2,
                    name: "Content strategy",
                    description: "Analyze reference material and generate brand-aligned content strategy",
                    capabilityID: nil, skillSlug: nil,
                    promptTemplate: "Based on these video analyses, create a content strategy for a launch video.\n\nContext: {{user_context}}\n\nReference analysis:\n{{video_analysis}}",
                    inputMapping: ["user_context": "context", "video_analysis": "video_analysis"],
                    outputKey: "strategy"
                ),
                WorkflowStep(
                    id: "s4", order: 3,
                    name: "Generate motion graphics",
                    description: "Build motion graphic video from the content strategy using Remotion",
                    capabilityID: nil, skillSlug: "coding-agent",
                    promptTemplate: "Create a Remotion project that generates a motion graphic launch video based on this strategy:\n\n{{strategy}}",
                    inputMapping: ["strategy": "strategy"],
                    outputKey: "video_file"
                ),
                WorkflowStep(
                    id: "s5", order: 4,
                    name: "Generate AI voice",
                    description: "Generate AI voiceover from the script",
                    capabilityID: nil, skillSlug: nil,
                    promptTemplate: "Generate an AI voiceover for this launch video script. Extract the narration script from the strategy and use a text-to-speech service.\n\nStrategy:\n{{strategy}}",
                    inputMapping: ["strategy": "strategy"],
                    outputKey: "voice_file"
                ),
                WorkflowStep(
                    id: "s6", order: 5,
                    name: "Assemble final video",
                    description: "Merge motion graphics with voice track, match segment lengths",
                    capabilityID: nil, skillSlug: nil,
                    promptTemplate: "Use ffmpeg to merge the video and voice files, matching segment lengths.\nVideo: {{video_file}}\nVoice: {{voice_file}}",
                    inputMapping: ["video_file": "video_file", "voice_file": "voice_file"],
                    outputKey: "final_video"
                ),
                WorkflowStep(
                    id: "s7", order: 6,
                    name: "Upload to Drive",
                    description: "Upload final video to Google Drive and get shareable link",
                    capabilityID: nil, skillSlug: "gws-drive-upload",
                    promptTemplate: "Upload {{final_video}} to Google Drive and return the shareable link",
                    inputMapping: ["final_video": "final_video"],
                    outputKey: "drive_url"
                ),
            ],
            inputSpec: WorkflowInputSpec(
                references: [
                    ReferenceField(id: "urls", label: "Reference video URLs", type: .url, required: true),
                    ReferenceField(id: "brand", label: "Brand guide / context doc", type: .file, required: false),
                ],
                contextField: "Describe the launch video you need (product, tone, duration, audience)",
                projectSelection: true
            ),
            createdFrom: .prebuilt
        )
    }

    // 2. Bug to PR
    private static func bugToPRWorkflow(_ now: Date) -> WorkflowRecord {
        WorkflowRecord(
            id: "WF-BUGPR001",
            name: "Bug to PR",
            description: "Analyze a bug report, implement a fix, and create a pull request with description.",
            emoji: "\u{1F41B}",
            category: .engineering,
            createdAt: now,
            steps: [
                WorkflowStep(
                    id: "s1", order: 0,
                    name: "Analyze bug",
                    description: "Understand the bug report and identify root cause in the codebase",
                    capabilityID: nil, skillSlug: "coding-agent",
                    promptTemplate: "Analyze this bug report and identify the root cause:\n\n{{bug_description}}\n\nSearch the codebase, trace the issue, and explain what's wrong.",
                    inputMapping: ["bug_description": "context"],
                    outputKey: "analysis"
                ),
                WorkflowStep(
                    id: "s2", order: 1,
                    name: "Implement fix",
                    description: "Write the code fix based on the analysis",
                    capabilityID: nil, skillSlug: "coding-agent",
                    promptTemplate: "Based on this analysis, implement the fix:\n\n{{analysis}}\n\nCreate a new branch, make the changes, and run tests.",
                    inputMapping: ["analysis": "analysis"],
                    outputKey: "fix_summary"
                ),
                WorkflowStep(
                    id: "s3", order: 2,
                    name: "Create PR",
                    description: "Create a GitHub pull request with a clear description",
                    capabilityID: nil, skillSlug: "github",
                    promptTemplate: "Create a pull request for the bug fix.\n\nBug: {{bug_description}}\nFix summary: {{fix_summary}}\n\nWrite a clear PR title and description.",
                    inputMapping: ["bug_description": "context", "fix_summary": "fix_summary"],
                    outputKey: "pr_url"
                ),
            ],
            inputSpec: WorkflowInputSpec(
                references: [
                    ReferenceField(id: "issue", label: "Issue URL or bug report", type: .url, required: false),
                ],
                contextField: "Describe the bug (symptoms, steps to reproduce, expected behavior)",
                projectSelection: true
            ),
            createdFrom: .prebuilt
        )
    }

    // 3. Meeting Notes to Actions
    private static func meetingToActionsWorkflow(_ now: Date) -> WorkflowRecord {
        WorkflowRecord(
            id: "WF-MTGACT01",
            name: "Meeting to Actions",
            description: "Convert meeting transcript into structured action items, create tasks, and notify the team.",
            emoji: "\u{1F4DD}",
            category: .communication,
            createdAt: now,
            steps: [
                WorkflowStep(
                    id: "s1", order: 0,
                    name: "Summarize meeting",
                    description: "Extract key decisions, action items, and owners from the transcript",
                    capabilityID: nil, skillSlug: "summarize",
                    promptTemplate: "Summarize this meeting transcript. Extract:\n1. Key decisions made\n2. Action items with owners\n3. Open questions\n4. Follow-up dates\n\nTranscript:\n{{meeting_notes}}",
                    inputMapping: ["meeting_notes": "context"],
                    outputKey: "summary"
                ),
                WorkflowStep(
                    id: "s2", order: 1,
                    name: "Create tasks",
                    description: "Create tasks in Google Tasks from the extracted action items",
                    capabilityID: nil, skillSlug: "gws-tasks",
                    promptTemplate: "Create Google Tasks for each action item:\n\n{{summary}}",
                    inputMapping: ["summary": "summary"],
                    outputKey: "tasks_created"
                ),
                WorkflowStep(
                    id: "s3", order: 2,
                    name: "Notify team",
                    description: "Post meeting summary to Slack or send via email",
                    capabilityID: nil, skillSlug: "slack",
                    promptTemplate: "Post this meeting summary to the team channel:\n\n{{summary}}\n\nTasks created: {{tasks_created}}",
                    inputMapping: ["summary": "summary", "tasks_created": "tasks_created"],
                    outputKey: nil
                ),
            ],
            inputSpec: WorkflowInputSpec(
                references: [],
                contextField: "Paste the meeting transcript or notes",
                projectSelection: true
            ),
            createdFrom: .prebuilt
        )
    }

    // 4. Research Brief
    private static func researchBriefWorkflow(_ now: Date) -> WorkflowRecord {
        WorkflowRecord(
            id: "WF-RESRCH01",
            name: "Research Brief",
            description: "Deep research on a topic, synthesize findings into a structured document.",
            emoji: "\u{1F50D}",
            category: .research,
            createdAt: now,
            steps: [
                WorkflowStep(
                    id: "s1", order: 0,
                    name: "Deep research",
                    description: "Conduct thorough research on the topic using web search and analysis",
                    capabilityID: nil, skillSlug: "academic-deep-research",
                    promptTemplate: "Research this topic thoroughly:\n\n{{research_topic}}\n\nFind key sources, extract important findings, identify trends and gaps.",
                    inputMapping: ["research_topic": "context"],
                    outputKey: "research_findings"
                ),
                WorkflowStep(
                    id: "s2", order: 1,
                    name: "Synthesize brief",
                    description: "Transform raw research into a structured, readable brief",
                    capabilityID: nil, skillSlug: "summarize",
                    promptTemplate: "Create a structured research brief from these findings:\n\n{{research_findings}}\n\nFormat: Executive summary, key findings, detailed analysis, recommendations, sources.",
                    inputMapping: ["research_findings": "research_findings"],
                    outputKey: "brief"
                ),
                WorkflowStep(
                    id: "s3", order: 2,
                    name: "Create document",
                    description: "Write the research brief to a Google Doc",
                    capabilityID: nil, skillSlug: "gws-docs-write",
                    promptTemplate: "Create a Google Doc with this research brief:\n\n{{brief}}",
                    inputMapping: ["brief": "brief"],
                    outputKey: "doc_url"
                ),
            ],
            inputSpec: WorkflowInputSpec(
                references: [
                    ReferenceField(id: "sources", label: "Starting URLs or papers", type: .url, required: false),
                ],
                contextField: "What topic do you want researched? Include scope, angle, and any specific questions.",
                projectSelection: false
            ),
            createdFrom: .prebuilt
        )
    }

    // 5. Content Repurpose
    private static func contentRepurposeWorkflow(_ now: Date) -> WorkflowRecord {
        WorkflowRecord(
            id: "WF-REPURP01",
            name: "Content Repurpose",
            description: "Take one piece of content and repurpose it across multiple formats and platforms.",
            emoji: "\u{267B}\u{FE0F}",
            category: .content,
            createdAt: now,
            steps: [
                WorkflowStep(
                    id: "s1", order: 0,
                    name: "Analyze source content",
                    description: "Extract key themes, quotes, and insights from the source material",
                    capabilityID: nil, skillSlug: "summarize",
                    promptTemplate: "Analyze this content and extract key themes, memorable quotes, statistics, and core insights:\n\n{{source_content}}",
                    inputMapping: ["source_content": "context"],
                    outputKey: "analysis"
                ),
                WorkflowStep(
                    id: "s2", order: 1,
                    name: "Generate formats",
                    description: "Create tweet thread, LinkedIn post, blog outline, and newsletter snippet",
                    capabilityID: nil, skillSlug: nil,
                    promptTemplate: "From this analysis, generate:\n1. A Twitter/X thread (5-8 tweets)\n2. A LinkedIn post\n3. A blog post outline\n4. A newsletter snippet (3 paragraphs)\n\nAnalysis:\n{{analysis}}",
                    inputMapping: ["analysis": "analysis"],
                    outputKey: "content_pieces"
                ),
                WorkflowStep(
                    id: "s3", order: 2,
                    name: "Save to docs",
                    description: "Save all generated content to a Google Doc for review",
                    capabilityID: nil, skillSlug: "gws-docs-write",
                    promptTemplate: "Create a Google Doc titled 'Content Repurpose Pack' with all these content pieces:\n\n{{content_pieces}}",
                    inputMapping: ["content_pieces": "content_pieces"],
                    outputKey: "doc_url"
                ),
            ],
            inputSpec: WorkflowInputSpec(
                references: [
                    ReferenceField(id: "source_url", label: "Source content URL", type: .url, required: false),
                ],
                contextField: "Paste the source content (article, transcript, notes) to repurpose",
                projectSelection: false
            ),
            createdFrom: .prebuilt
        )
    }

    // 6. Image Format Convert (the PNG→JPG example)
    private static func imageFormatConvertWorkflow(_ now: Date) -> WorkflowRecord {
        WorkflowRecord(
            id: "WF-IMGCNV01",
            name: "Image Format Convert",
            description: "Convert images between formats (PNG, JPG, WebP, HEIC) with optional resizing and compression.",
            emoji: "\u{1F5BC}\u{FE0F}",
            category: .productivity,
            createdAt: now,
            steps: [
                WorkflowStep(
                    id: "s1", order: 0,
                    name: "Convert image",
                    description: "Convert the image to the target format using sips or ImageMagick",
                    capabilityID: nil, skillSlug: nil,
                    promptTemplate: "Convert this image file to the requested format.\nSource: {{source_file}}\nTarget format: {{target_format}}\n\nUse the macOS built-in `sips` command for conversion. If resizing is needed, apply it. Return the path to the converted file.",
                    inputMapping: ["source_file": "references.source", "target_format": "context"],
                    outputKey: "converted_file"
                ),
            ],
            inputSpec: WorkflowInputSpec(
                references: [
                    ReferenceField(id: "source", label: "Source image file", type: .file, required: true),
                ],
                contextField: "Target format (e.g., JPG, PNG, WebP) and any size/quality requirements",
                projectSelection: false
            ),
            createdFrom: .prebuilt
        )
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let workflowStoreDidChange = Notification.Name("workflowStoreDidChange")
}
