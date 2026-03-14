import AppKit
import Foundation

// MARK: - Learn Mode Service (FUCBC Architecture)
//
// Collects raw events every 5 seconds — NO Llama, no waiting.
// When the user taps "Build Capability", the full event dump goes straight to
// Claude Code with the FUCBC prompt. Before sending, the events are converted
// into a coherent user journey story ("User navigated to…", "User said…").
// Claude then:
//   1. Reads the story + identifies the repeating use-case pattern
//   2. Breaks it into modular sub-workflows with REAL executable steps
//   3. Writes a SKILL.md to ~/.autoclawd/openclaw-skills/{slug}/SKILL.md
//      — using shell commands / API invocations
//   4. Outputs a JSON capability manifest
// AutoClawd then saves the Capability, refreshes OpenClaw skills, shows grid.

@MainActor
final class LearnModeService: ObservableObject {

    @Published var session: LearnSession?
    @Published var isActive = false

    // Injected from AppState
    var screenAnalyzer: ScreenVisionAnalyzer?
    var onCapabilityBuilt: ((Capability) -> Void)?

    private let runner = ClaudeCodeRunner()
    private let ollama = OllamaService()
    private var eventTimer: Timer?
    private var latestSpeechFragment: String = ""

    // MARK: - Session Lifecycle

    func startSession() {
        guard !isActive else { return }
        isActive = true
        session = LearnSession(startedAt: Date())
        startEventTimer()
        Log.info(.ui, "FUCBC: learn session started")
    }

    func stopSession() {
        isActive = false
        stopEventTimer()
        Log.info(.ui, "FUCBC: learn session stopped")
    }

    // MARK: - Frame Reception (no-op — FUCBC uses rolling OCR, not per-frame)

    func receiveFrame(_ image: CGImage) { _ = image }

    // MARK: - Raw Speech Collection (NO Llama — raw SFSpeech / Groq chunks)

    func addTranscriptChunk(_ chunk: String) {
        guard isActive else { return }
        latestSpeechFragment = chunk
    }

    // MARK: - 5-Second Event Timer

    private func startEventTimer() {
        eventTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.recordEvent() }
        }
    }

    private func stopEventTimer() {
        eventTimer?.invalidate()
        eventTimer = nil
    }

    private func recordEvent() async {
        guard var sess = session else { return }

        let app         = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"

        // Never record AutoClawd itself — user looking at the pill/panel during a session
        // would create meaningless "AutoClawd" nodes that pollute the FUCBC story.
        guard app != "AutoClawd" else { return }

        let windowTitle = Self.accessibilityWindowTitle()
        let ocr         = screenAnalyzer?.recentContext() ?? ""
        let urlsFromOCR = Self.extractURLs(from: ocr)
        let url         = urlsFromOCR.first
        let speech      = latestSpeechFragment
        latestSpeechFragment = ""  // consume

        // Nodes are differentiated by app + window title (not URL, which was always nil).
        // Window title changes as user navigates pages within the same app (e.g. browser tabs).
        let nodeKey = "\(app)|\(windowTitle ?? "")"

        if let lastIndex = sess.nodes.indices.last {
            let lastKey = "\(sess.nodes[lastIndex].app)|\(sess.nodes[lastIndex].windowTitle ?? "")"
            if lastKey == nodeKey {
                // Same context — update in place if OCR changed meaningfully
                let lastOCR = sess.nodes[lastIndex].ocrSnapshots.last ?? ""
                let overlap = ocrOverlap(ocr, lastOCR)
                if overlap < 0.5, !ocr.isEmpty {
                    sess.nodes[lastIndex].ocrSnapshots.append(ocr)
                    sess.nodes[lastIndex].lastUpdated = Date()
                }
                if !speech.isEmpty {
                    sess.nodes[lastIndex].speechSnippets.append(speech)
                }
                // Backfill URL if we just found one and node didn't have one yet
                if url != nil, sess.nodes[lastIndex].url == nil {
                    sess.nodes[lastIndex].url = url
                }
            } else {
                // New context — create a new node
                let node = CanvasNode(
                    id: UUID().uuidString,
                    app: app,
                    url: url,
                    windowTitle: windowTitle,
                    ocrSnapshots: ocr.isEmpty ? [] : [ocr],
                    speechSnippets: speech.isEmpty ? [] : [speech],
                    workSummary: nil,
                    capturedAt: Date(),
                    lastUpdated: Date()
                )
                sess.nodes.append(node)
                Log.info(.ui, "LearnMode: new node — \(app) | \(windowTitle ?? url ?? "(no context)")")
            }
        } else {
            // First node
            let node = CanvasNode(
                id: UUID().uuidString,
                app: app,
                url: url,
                windowTitle: windowTitle,
                ocrSnapshots: ocr.isEmpty ? [] : [ocr],
                speechSnippets: speech.isEmpty ? [] : [speech],
                workSummary: nil,
                capturedAt: Date(),
                lastUpdated: Date()
            )
            sess.nodes.append(node)
            Log.info(.ui, "LearnMode: first node — \(app) | \(windowTitle ?? url ?? "(no context)")")
        }

        session = sess
    }

    // MARK: - Accessibility Window Title

    /// Returns the title of the frontmost window via the macOS Accessibility API.
    /// Called on @MainActor (timer fires on main thread). Returns nil if permission denied.
    private static func accessibilityWindowTitle() -> String? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let axApp = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let window = windowRef
        else { return nil }
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &titleRef) == .success
        else { return nil }
        return titleRef as? String
    }

    // MARK: - URL Extraction from OCR Text

    /// Extracts http/https URLs from raw OCR text using NSDataDetector.
    private static func extractURLs(from text: String) -> [String] {
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap { $0.url?.absoluteString }
    }

    // MARK: - Node Summarisation (Llama pass)

    /// Runs a Llama pass on each node to generate a one-sentence work summary.
    /// Mutations to session.nodes happen on @MainActor after the async group completes.
    private func summariseNodes() async {
        guard var sess = session else { return }
        let nodes = sess.nodes

        // Separate nodes: those needing Llama vs those getting a default (too little OCR).
        // Fallback defaults are collected first; Llama results are appended after the group.
        var summaries: [(id: String, summary: String)] = []

        let nodesToSummarise = nodes.filter { $0.workSummary == nil }
        for node in nodesToSummarise {
            let combinedOCR = node.ocrSnapshots.joined(separator: " | ")
            if combinedOCR.count < 20 {
                summaries.append((node.id, "Opened \(node.app)"))  // default, no Llama needed
            }
        }
        let llamaNodes = nodesToSummarise.filter { $0.ocrSnapshots.joined(separator: " | ").count >= 20 }

        // Run Llama calls in parallel; each task returns (id, summary) — no direct struct mutation.
        // All mutations to sess.nodes happen after the group on @MainActor (avoids stale-copy trap).
        await withTaskGroup(of: (String, String).self) { group in
            for node in llamaNodes {
                let combinedOCR = node.ocrSnapshots.joined(separator: " | ")
                let appName = node.app
                let urlStr = node.url.map { " (\($0))" } ?? ""
                let speech = node.speechSnippets.joined(separator: " · ")
                let fallback = "Worked in \(appName)"
                // Capture ollama reference — do NOT use self inside the task body
                let ollamaRef = ollama
                group.addTask {
                    let prompt = """
                    In one sentence, what was the user doing in \(appName)\(urlStr)?
                    OCR: \(String(combinedOCR.prefix(400)))
                    Speech: \(speech)
                    One sentence only.
                    """
                    do {
                        let result = try await ollamaRef.generate(prompt: prompt, numPredict: 64)
                        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
                        return (node.id, trimmed.isEmpty ? fallback : trimmed)
                    } catch {
                        return (node.id, fallback)
                    }
                }
            }
            for await pair in group {
                summaries.append(pair)
            }
        }

        // Apply all summaries back on @MainActor (never mutate inside task body — stale copy trap)
        for (id, summary) in summaries {
            if let idx = sess.nodes.firstIndex(where: { $0.id == id }) {
                sess.nodes[idx].workSummary = summary
            }
        }
        session = sess
    }

    // MARK: - Build Capability (FUCBC)

    func buildCapability() async {
        guard let currentSession = session, currentSession.phase == .collecting else { return }
        guard currentSession.hasEnoughContext else {
            session?.phase = .failed("Need at least 15 seconds of observation first")
            return
        }

        session?.phase = .building
        session?.buildOutput = ""

        let snapshot = await screenAnalyzer?.captureNow()
        let openClawDir = openClawDirectory()
        try? FileManager.default.createDirectory(atPath: openClawDir, withIntermediateDirectories: true)

        let project = Project(
            id: "fucbc-capabilities",
            name: "AutoClawd Capabilities",
            localPath: openClawDir,
            createdAt: Date(),
            tags: [],
            linkedProjectIDs: []
        )

        // Summarise each node before assembling the journey narrative
        await summariseNodes()

        // Build story FIRST, then send to Claude
        let story = buildUserJourney()
        let prompt = buildFUCBCPrompt(story: story, snapshot: snapshot, openClawDir: openClawDir)

        var fullOutput = ""
        let stream = runner.run(prompt, in: project, dangerouslySkipPermissions: true)
        do {
            for try await line in stream {
                fullOutput += line + "\n"
                self.session?.buildOutput = fullOutput
            }
        } catch {
            self.session?.phase = .failed(error.localizedDescription)
            return
        }

        let capability = parseCapability(from: fullOutput)
        let capID = capability.id
        CapabilityStore.shared.save(capability)
        onCapabilityBuilt?(capability)

        let similar = CapabilityStore.shared.suggest(
            screenText: snapshot?.extractedText ?? "",
            transcript: currentSession.nodes.flatMap { $0.speechSnippets }.joined(separator: " "),
            app: snapshot?.appName,
            urls: snapshot?.detectedURLs ?? []
        ).filter { $0.capability.id != capID }

        session?.builtCapability = capability
        session?.suggestedCapabilities = Array(similar.prefix(5).map { $0.capability })
        session?.phase = .done(capID)
        Log.info(.ui, "FUCBC: built '\(capability.name)' slug=\(capability.slug) suggested=\(similar.prefix(5).map { $0.capability.slug })")
    }

    // MARK: - Suggest Capabilities

    func suggestCapabilities(screenText: String = "", app: String? = nil, urls: [String] = []) -> [SuggestionMatch] {
        CapabilityStore.shared.suggest(screenText: screenText, app: app, urls: urls)
    }

    // MARK: - Journey Assembly
    //
    // Assembles a timestamped narrative from CanvasNode.workSummary values.
    // Each node's workSummary is produced by the Llama summariseNodes() pass.

    private func buildUserJourney() -> String {
        guard let sess = session else { return "" }
        var lines: [String] = []
        for (_, node) in sess.nodes.enumerated() {
            let elapsed = Int(node.capturedAt.timeIntervalSince(sess.startedAt))
            let summary = node.workSummary ?? "Opened \(node.app)"
            lines.append("T+\(elapsed)s → \(summary) [\(node.displayTitle)]")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - FUCBC Prompt Builder (with story + executable instructions)

    private func buildFUCBCPrompt(story: String, snapshot: ScreenSnapshot?, openClawDir: String) -> String {
        let nodeCount = session?.nodes.count ?? 0

        return """
        # FUCBC: Find Use-Case, Build Capability

        You are AutoClawd's intelligence engine. I observed a user's screen + voice across \(nodeCount) activity node(s).
        Below is a coherent story of what they did.

        ## Your Job
        1. Read the user journey story. Identify the ONE repeating use-case worth automating.
        2. Design a modular, EXECUTABLE capability with sub-workflows.
        3. Write a complete SKILL.md with REAL executable steps — not descriptions.
           - Use shell commands (curl, python3, osascript, ffmpeg, yt-dlp, etc.)
           - Each step must be something Claude Code can literally execute
        4. Output the JSON manifest at the end.

        ## Execution Environment
        - macOS, bash/zsh available
        - Claude Code SDK with tool use (Bash, Read, Write, WebSearch, etc.)
        - Python 3, curl, osascript available
        - AutoClawd can paste results to frontmost app via clipboard

        ## Social Media / Multi-Platform Example
        If the use-case involves posting to multiple platforms simultaneously:
        ```bash
        # Post to Twitter/X via API
        curl -X POST "https://api.twitter.com/2/tweets" \\
          -H "Authorization: Bearer $TWITTER_BEARER_TOKEN" \\
          -d '{"text": "CONTENT_HERE"}'

        # Post to Reddit
        curl -X POST "https://oauth.reddit.com/api/submit" \\
          -H "Authorization: bearer $REDDIT_ACCESS_TOKEN" \\
          -d "kind=self&sr=SUBREDDIT&title=TITLE&text=CONTENT"

        # Threads/Instagram via Graph API
        ```
        For Threads, Instagram: use the Meta Graph API.

        ---

        \(story)

        ---

        ## SKILL.md to Write
        Write this file: \(openClawDir)/{slug}/SKILL.md

        Use EXACTLY this format:
        ```
        ---
        name: {slug}
        description: "{one line description}"
        metadata: {"openclaw": {"emoji": "{emoji}", "requires": {"bins": [{comma-separated tool names as JSON strings}]}, "category": "{category}"}}
        category: {category}
        ---
        # {Capability Name}

        ## When to Run
        {Specific trigger conditions. E.g.: "When user copies a YouTube URL and is on Threads app"}

        ## Steps

        ### 1. Extract Content
        {Concrete extraction step with shell command or tool call}

        ### 2. Process / Format
        {Processing step with actual code}

        ### 3. Execute (for each platform)
        {Real API calls or shell invocations, with placeholder env vars}

        ### 4. Notify
        {How to report result to user — paste to clipboard, show notification, etc.}

        ## Example
        {Concrete example from the observed session — what would happen if this ran right now}
        ```

        ## JSON Manifest (output last, no trailing content after this block)

        IMPORTANT: Always output at least 2 subWorkflows. Every subWorkflow must have a non-empty "name" AND a non-empty "invocation" (a shell command or skill slug). Never output a subWorkflow with blank fields.

        ```json
        {
          "name": "<Friendly name, max 50 chars>",
          "description": "<1-2 sentence description>",
          "emoji": "<single emoji>",
          "category": "<research|automation|communication|development|discovery|organization>",
          "slug": "<kebab-case-slug>",
          "triggerApps": ["<exact app names>"],
          "triggerURLPatterns": ["<URL substrings>"],
          "triggerKeywords": ["<speech/screen keywords>"],
          "triggerOCRPatterns": ["<exact screen text phrases>"],
          "subWorkflows": [
            {"name": "detect_trigger", "description": "<how/when to trigger>", "invocation": "osascript -e 'tell application \"System Events\" to get frontmost application'"},
            {"name": "extract_content", "description": "<what to extract>", "invocation": "<shell cmd or skill slug>"},
            {"name": "execute", "description": "<main action>", "invocation": "<shell cmd or skill slug>"},
            {"name": "notify", "description": "<how to tell user>", "invocation": "osascript -e 'display notification \"Done\" with title \"AutoClawd\"'"}
          ]
        }
        ```
        """
    }

    // MARK: - Capability Parsing

    private func parseCapability(from output: String) -> Capability {
        if let jsonStr = extractJSONBlock(from: output),
           let data = jsonStr.data(using: .utf8),
           let manifest = try? JSONDecoder().decode(CapabilityManifest.self, from: data) {

            let category = CapabilityCategory(rawValue: manifest.category) ?? .automation
            let subWorkflows = manifest.subWorkflows.map {
                SubWorkflow(id: UUID().uuidString, name: $0.name, description: $0.description, invocation: $0.invocation)
            }
            let triggers = CapabilityTriggers(
                apps: manifest.triggerApps,
                urlPatterns: manifest.triggerURLPatterns,
                keywords: manifest.triggerKeywords,
                ocrPatterns: manifest.triggerOCRPatterns
            )
            let skillPath = openClawDirectory() + "/\(manifest.slug)/SKILL.md"
            return Capability(
                id: UUID().uuidString,
                name: manifest.name,
                description: manifest.description,
                emoji: manifest.emoji,
                category: category,
                createdAt: Date(),
                triggers: triggers,
                subWorkflows: subWorkflows,
                skillMDPath: FileManager.default.fileExists(atPath: skillPath) ? skillPath : nil,
                slug: manifest.slug
            )
        }

        return Capability(
            id: UUID().uuidString,
            name: "New Capability",
            description: "Automation built from observed session.",
            emoji: "⚡",
            category: .automation,
            createdAt: Date(),
            triggers: CapabilityTriggers(apps: [], urlPatterns: [], keywords: [], ocrPatterns: []),
            subWorkflows: [],
            skillMDPath: nil,
            slug: "new-capability-\(Int(Date().timeIntervalSince1970))"
        )
    }

    // MARK: - Utilities

    private func openClawDirectory() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".autoclawd/openclaw-skills")
            .path
    }

    private func extractJSONBlock(from text: String) -> String? {
        // Try ```json ... ``` first
        if let start = text.range(of: "```json\n"),
           let end = text.range(of: "\n```", range: start.upperBound..<text.endIndex) {
            return String(text[start.upperBound..<end.lowerBound])
        }
        // Fallback: find outermost { }
        if let start = text.range(of: "{"),
           let end = text.range(of: "}", options: .backwards) {
            return String(text[start.lowerBound...end.upperBound])
        }
        return nil
    }

    // MARK: - OCR Deduplication

    /// Returns the character-level overlap ratio between two strings (0.0–1.0).
    /// Uses character counts (with duplicates), not unique-character sets, so that
    /// two different screens sharing a common alphabet don't falsely score as identical.
    /// Formula: common / max(a.count, b.count) where common = characters in the shorter
    /// string that also appear in the longer (approximated by counting shared chars).
    private func ocrOverlap(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        // Build frequency maps and count matching characters
        var freqA = [Character: Int]()
        for ch in a { freqA[ch, default: 0] += 1 }
        var common = 0
        var freqB = [Character: Int]()
        for ch in b {
            freqB[ch, default: 0] += 1
            if let countA = freqA[ch], (freqB[ch] ?? 0) <= countA { common += 1 }
        }
        return Double(common) / Double(max(a.count, b.count))
    }
}
