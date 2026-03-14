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
        guard isActive, session?.phase == .collecting else { return }
        let ocrText = screenAnalyzer?.recentContext() ?? ""
        let app = NSWorkspace.shared.frontmostApplication
        let event = LearnEvent(
            timestamp: Date(),
            appName: app?.localizedName,
            windowTitle: nil,
            ocrSnippet: String(ocrText.prefix(400)),
            detectedURLs: [],
            speechSnippet: latestSpeechFragment
        )
        session?.events.append(event)
        latestSpeechFragment = ""
        Log.info(.ui, "FUCBC: event #\(session?.events.count ?? 0) — \(app?.localizedName ?? "-")")
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

        // Build story FIRST, then send to Claude
        let story = buildUserJourney(from: currentSession.events, snapshot: snapshot)
        let prompt = buildFUCBCPrompt(story: story, events: currentSession.events, snapshot: snapshot, openClawDir: openClawDir)

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
            transcript: currentSession.events.compactMap { $0.speechSnippet.isEmpty ? nil : $0.speechSnippet }.joined(separator: " "),
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

    // =========================================================================
    // MARK: - Story Builder
    //
    // Transforms raw LearnEvents into a coherent human-readable user journey.
    // This is what Claude READS to understand what the user was doing.
    //
    // Output looks like:
    //   T+0s  → User opened Threads
    //   T+5s  → User scrolled feed · Screen: "New Llama 3.3 from Meta — free weights"
    //   T+10s → User navigated to youtube.com · Screen: video about Llama 3.3
    //           User said: "oh I should try this one"
    //   T+15s → User switched to Safari, navigated to huggingface.co
    //           Screen: model cards, GGUF download buttons visible
    //   T+20s → User downloaded "llama-3.3-70b-instruct.Q4_K_M.gguf" (4.8 GB)
    // =========================================================================

    func buildUserJourney(from events: [LearnEvent], snapshot: ScreenSnapshot?) -> String {
        guard !events.isEmpty else { return "No events recorded." }

        var lines: [String] = []
        lines.append("## User Journey (observed \(events.count * 5)s)")
        lines.append("")

        var prevApp: String? = nil
        let sessionStart = events.first!.timestamp

        for (i, event) in events.enumerated() {
            let elapsed = Int(event.timestamp.timeIntervalSince(sessionStart))
            let prefix = "T+\(elapsed)s"

            var actions: [String] = []

            // ── App transition ──
            if let app = event.appName {
                if prevApp == nil || prevApp != app {
                    if prevApp == nil {
                        actions.append("User opened \(app)")
                    } else {
                        actions.append("User switched to \(app)")
                    }
                    prevApp = app
                }
            }

            // ── URL navigation ──
            for url in event.detectedURLs.prefix(2) {
                let domain = urlDomain(url)
                let action = navigationVerb(for: domain, ocr: event.ocrSnippet)
                actions.append("User \(action) \(domain)")
            }

            // ── OCR-based action inference ──
            let ocrActions = inferActionsFromOCR(event.ocrSnippet, prevEvent: i > 0 ? events[i-1] : nil)
            actions.append(contentsOf: ocrActions)

            // ── Speech ──
            if !event.speechSnippet.isEmpty {
                actions.append("User said: \"\(event.speechSnippet)\"")
            }

            // ── Screen content (condensed) ──
            let screenLabel = condenseOCR(event.ocrSnippet)
            let screenNote = screenLabel.isEmpty ? "" : "· Screen: \"\(screenLabel)\""

            if !actions.isEmpty {
                let actionText = actions.joined(separator: " · ")
                lines.append("\(prefix)  → \(actionText) \(screenNote)".trimmingCharacters(in: .whitespaces))
            } else if !screenNote.isEmpty {
                lines.append("\(prefix)  · \(screenNote)")
            }
        }

        // ── Final state ──
        if let snap = snapshot {
            lines.append("")
            lines.append("## Final State (at build time)")
            if let app = snap.appName { lines.append("App: \(app)") }
            if !snap.detectedURLs.isEmpty { lines.append("URLs open: \(snap.detectedURLs.prefix(3).joined(separator: ", "))") }
            if !snap.extractedText.isEmpty {
                let condensed = snap.extractedText.count > 800
                    ? String(snap.extractedText.prefix(800)) + "\n[…]"
                    : snap.extractedText
                lines.append("Screen content:\n\(condensed)")
            }
        }

        return lines.joined(separator: "\n")
    }

    // ── Navigation verb based on context ──
    private func navigationVerb(for domain: String, ocr: String) -> String {
        let lowerOCR = ocr.lowercased()
        if lowerOCR.contains("search") || domain.contains("google") || domain.contains("bing") { return "searched on" }
        if lowerOCR.contains("download") || lowerOCR.contains(".gguf") || lowerOCR.contains(".zip") { return "downloaded from" }
        if lowerOCR.contains("reddit") || domain.contains("reddit") { return "explored Reddit at" }
        return "navigated to"
    }

    // ── Infer actions from OCR text changes ──
    private func inferActionsFromOCR(_ ocr: String, prevEvent: LearnEvent?) -> [String] {
        var actions: [String] = []
        let lower = ocr.lowercased()

        // Download detection
        if lower.contains(".gguf") || lower.contains(".safetensors") || lower.contains(".zip") || lower.contains("downloading") {
            if let filename = extractFilename(from: ocr) {
                actions.append("User downloaded \"\(filename)\"")
            } else {
                actions.append("User initiated a download")
            }
        }
        // Search detection
        if lower.contains("search results") || lower.contains("results for") {
            if let query = extractSearchQuery(from: ocr) {
                actions.append("User searched for \"\(query)\"")
            }
        }
        // Video detection
        if lower.contains("watch") || lower.contains("video") || lower.contains("youtube.com/watch") {
            actions.append("User watched a video")
        }
        // Post/compose detection
        if lower.contains("what's on your mind") || lower.contains("compose") || lower.contains("new post") || lower.contains("tweet") {
            actions.append("User opened post composer")
        }
        // Form/input detection (typing)
        if let prev = prevEvent, abs(ocr.count - prev.ocrSnippet.count) > 20 && lower.contains("typing") {
            actions.append("User typed content")
        }

        return actions
    }

    private func extractFilename(from ocr: String) -> String? {
        let pattern = #"[\w\-\.]+\.(gguf|safetensors|zip|tar|gz|pdf|mp4|mov)"#
        if let range = ocr.range(of: pattern, options: .regularExpression) {
            return String(ocr[range])
        }
        return nil
    }

    private func extractSearchQuery(from ocr: String) -> String? {
        // Look for quoted strings or text after "results for"
        if let range = ocr.range(of: "results for \"", options: .caseInsensitive) {
            let after = ocr[range.upperBound...]
            if let end = after.firstIndex(of: "\"") {
                return String(after[..<end])
            }
        }
        return nil
    }

    private func condenseOCR(_ ocr: String) -> String {
        // Extract the most meaningful line from OCR (first non-trivial line)
        let lines = ocr.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 12 && $0.count < 80 }
        return lines.first.map { String($0.prefix(70)) } ?? ""
    }

    private func urlDomain(_ url: String) -> String {
        URL(string: url)?.host ?? url
    }

    // =========================================================================
    // MARK: - FUCBC Prompt Builder (with story + executable instructions)
    // =========================================================================

    private func buildFUCBCPrompt(story: String, events: [LearnEvent], snapshot: ScreenSnapshot?, openClawDir: String) -> String {

        return """
        # FUCBC: Find Use-Case, Build Capability

        You are AutoClawd's intelligence engine. I observed a user's screen + voice for \(events.count * 5) seconds.
        Below is a coherent story of what they did, followed by raw event data for reference.

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

        ## Raw Events (reference only — the story above is the truth)
        \(events.map { $0.eventLine() }.joined(separator: "\n"))

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
            {"name": "detect_trigger", "description": "<how/when to trigger>", "invocation": null},
            {"name": "extract_content", "description": "<what to extract>", "invocation": "<shell cmd or null>"},
            {"name": "execute", "description": "<main action>", "invocation": "<shell cmd or null>"},
            {"name": "notify", "description": "<how to tell user>", "invocation": null}
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
}
