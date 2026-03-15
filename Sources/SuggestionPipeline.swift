// Sources/SuggestionPipeline.swift
import Foundation
import AppKit

/// Two-phase suggestion pipeline:
///
///   Phase 1 — `evaluate()` (synchronous, every OCR frame):
///     Pure keyword / URL / app scoring via CapabilityStore. No inference.
///
///   Phase 2 — Haiku inference (async, two trigger points):
///     a. `sessionEndSuggest(context:)` — fires once at session end (10s silence)
///     b. `scheduleScreenSuggestion(...)` — fires on OCR change with 3-min debounce
///        (handles silent screen work where there is no voice session)
///
///   Both paths use Claude Haiku via `claude --print` (OAuth / API key, same as execution).
///   Output confidence determines routing:
///     ≥ 0.80 → `.task` → toast, run immediately
///     0.65–0.79 → `.question` → toast with option buttons (interactive clarification)
///     < 0.65 → nil (suppressed)
@MainActor
final class SuggestionPipeline {

    // MARK: - Phase 1: Capability Cooldown

    private var lastSuggestedCapabilityID: String?
    private var lastSuggestedAt: Date = .distantPast
    private let capabilityCooldown: TimeInterval = 30.0

    // MARK: - Phase 2: Screen-Triggered Haiku Guards

    private let haiku  = ClaudeHaikuService()
    private let vision = ClaudeVisionService()
    private var lastScreenHash: Int = 0
    private var lastScreenHaikuAt: Date = .distantPast
    private let screenHaikuDebounce: TimeInterval = 180.0   // 3 min for passive OCR-change trigger
    private let appSwitchHaikuDebounce: TimeInterval = 60.0 // 60s for explicit app-switch events
    private var lastAppSwitchHaikuAt: Date = .distantPast
    private var isHaikuRunning = false
    private var lastOCRText: String = ""                     // for OCR diff computation
    private let screenHaikuDebounce_passive: TimeInterval = 90.0 // ↓ from 3 min: OCR-change passive trigger

    // MARK: - Phase 2e: Clipboard-Triggered Suggestions (highest intent signal)

    private var lastClipboardSuggestionAt: Date = .distantPast
    private let clipboardDebounce: TimeInterval = 5.0  // very short — user just acted

    // MARK: - Phase 2d: Dwell Detection (user reading/thinking — same content > 20s)

    private var dwellStartedAt: Date = .distantPast
    private var lastDwellHaikuAt: Date = .distantPast
    private let dwellThreshold: TimeInterval    = 20.0   // seconds on same content before triggering
    private let dwellHaikuDebounce: TimeInterval = 300.0 // 5 min between dwell triggers

    // MARK: - Suggestion Deduplication

    private struct RecentSuggestion {
        let title: String
        let shownAt: Date
    }
    private var recentSuggestions: [RecentSuggestion] = []
    private let deduplicationWindow: TimeInterval = 1200.0 // 20 min — don't re-suggest same title

    /// Returns true if this title was already suggested recently (within deduplicationWindow).
    private func isDuplicate(title: String) -> Bool {
        let cutoff = Date().addingTimeInterval(-deduplicationWindow)
        recentSuggestions.removeAll { $0.shownAt < cutoff }  // prune stale entries
        let norm = title.lowercased().trimmingCharacters(in: .whitespaces)
        return recentSuggestions.contains { $0.title.lowercased() == norm }
    }

    private func recordSuggestion(title: String) {
        recentSuggestions.append(RecentSuggestion(title: title, shownAt: Date()))
    }

    // MARK: - OCR Diff Helper

    /// Returns only the lines that are NEW in `current` vs `previous`.
    /// If more than 60 % of lines changed (big navigation), returns full `current`.
    private func diffContent(previous: String, current: String) -> String {
        let prevSet  = Set(previous.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        let currLines = current.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let newLines  = currLines.filter { !prevSet.contains($0) }
        // If the majority of content is new it's a page/app change — send full text
        let changeFraction = Double(newLines.count) / Double(max(currLines.count, 1))
        if changeFraction > 0.6 { return current }
        return newLines.joined(separator: "\n")
    }

    // MARK: - Phase 1: Synchronous Evaluate

    func evaluate(
        screenText: String,
        transcript: String,
        app: String?,
        urls: [String]
    ) -> SuggestionItem? {
        let capMatches = CapabilityStore.shared.suggest(
            screenText: screenText,
            transcript: transcript,
            app: app,
            urls: urls
        )
        guard let top = capMatches.first else { return nil }

        let id      = top.capability.id
        let elapsed = Date().timeIntervalSince(lastSuggestedAt)
        if id == lastSuggestedCapabilityID, elapsed < capabilityCooldown { return nil }
        lastSuggestedCapabilityID = id
        lastSuggestedAt = Date()
        return .capability(top)
    }

    // MARK: - Phase 2a: Session-End Haiku Pass

    /// One Haiku call fired at session end (voice session → 10s silence).
    /// Returns `.task` (high confidence), `.question` (medium), or nil.
    func sessionEndSuggest(context: SuggestionContext) async -> SuggestionItem? {
        guard !context.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return await runHaiku(context: context)
    }

    // MARK: - Phase 2b: Screen-Triggered Haiku (silent screen work)

    /// Non-blocking. Fires a Haiku Task if OCR changed AND 3-min debounce allows.
    /// `onResult` called on @MainActor with the suggestion item.
    func scheduleScreenSuggestion(
        screenText: String,
        transcript: String,
        app: String?,
        urls: [String],
        clipboard: [String],
        worldModel: String,
        onResult: @escaping @MainActor (SuggestionItem) -> Void
    ) {
        let hash    = screenText.hashValue
        let elapsed = Date().timeIntervalSince(lastScreenHaikuAt)

        // Dwell detection: same OCR for > dwellThreshold AND dwell debounce elapsed → fire
        let dwellElapsed = Date().timeIntervalSince(lastDwellHaikuAt)
        if hash == lastScreenHash, !isHaikuRunning, !screenText.isEmpty,
           Date().timeIntervalSince(dwellStartedAt) >= dwellThreshold,
           dwellElapsed >= dwellHaikuDebounce {
            // User has been on the same content — treat like a screen trigger
            lastDwellHaikuAt = Date()
            lastScreenHaikuAt = Date()
            isHaikuRunning = true
            let diffText = screenText // same content — no diff needed for dwell
            let ctx = SuggestionContext(transcript: transcript, screenText: diffText, app: app,
                                        urls: urls, clipboard: clipboard, worldModel: worldModel)
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let item = await self.runHaiku(context: ctx) { onResult(item) }
                self.isHaikuRunning = false
            }
            return
        }

        guard !isHaikuRunning,
              elapsed >= screenHaikuDebounce_passive,
              hash != lastScreenHash,
              !screenText.isEmpty
        else {
            // Reset dwell timer on content change
            if hash != lastScreenHash { dwellStartedAt = Date() }
            return
        }

        // Compute diff — pass only new lines as the primary signal
        let diffText = diffContent(previous: lastOCRText, current: screenText)
        lastOCRText       = screenText
        lastScreenHash    = hash
        lastScreenHaikuAt = Date()
        dwellStartedAt    = Date()
        isHaikuRunning    = true

        let ctx = SuggestionContext(
            transcript: transcript,
            screenText: diffText.isEmpty ? screenText : diffText,
            app:        app,
            urls:       urls,
            clipboard:  clipboard,
            worldModel: worldModel
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            if let item = await self.runHaiku(context: ctx) {
                onResult(item)
            }
            self.isHaikuRunning = false
        }
    }

    // MARK: - Phase 2c: App-Switch Haiku (high-signal event, 60s debounce)

    /// Called after `captureOnAppSwitch()` resolves. 60s debounce — much shorter than the
    /// 3-min passive screen trigger since an app switch is an intentional context change.
    func scheduleAppSwitchSuggestion(
        screenText: String,
        transcript: String,
        app: String?,
        urls: [String],
        clipboard: [String],
        worldModel: String,
        onResult: @escaping @MainActor (SuggestionItem) -> Void
    ) {
        let elapsed = Date().timeIntervalSince(lastAppSwitchHaikuAt)
        guard !isHaikuRunning,
              elapsed >= appSwitchHaikuDebounce,
              !screenText.isEmpty
        else { return }

        lastAppSwitchHaikuAt = Date()
        isHaikuRunning = true

        let ctx = SuggestionContext(
            transcript: transcript,
            screenText: screenText,
            app:        app,
            urls:       urls,
            clipboard:  clipboard,
            worldModel: worldModel
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            if let item = await self.runVisionOrHaiku(context: ctx) {
                onResult(item)
            }
            self.isHaikuRunning = false
        }
    }

    // MARK: - Phase 2e: Clipboard-Triggered Suggestion (user explicitly copied something)

    /// Fired immediately when the user copies text or a URL.
    /// This is the highest-intent signal — user said "I care about this content."
    /// Short debounce (5s) and lower confidence floor (0.5) vs ambient triggers.
    /// `contentType`: "text" | "url". `copiedContent`: full clipboard string.
    func scheduleClipboardSuggestion(
        contentType: String,
        copiedContent: String,
        screenText: String,
        transcript: String,
        app: String?,
        urls: [String],
        worldModel: String,
        onResult: @escaping @MainActor (SuggestionItem) -> Void
    ) {
        let elapsed = Date().timeIntervalSince(lastClipboardSuggestionAt)
        guard !isHaikuRunning,
              elapsed >= clipboardDebounce,
              !copiedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        lastClipboardSuggestionAt = Date()
        isHaikuRunning = true

        let ctx = SuggestionContext(
            transcript: transcript,
            screenText: screenText,
            app:        app,
            urls:       urls,
            clipboard:  [copiedContent],   // copied content IS the primary signal
            worldModel: worldModel
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            if let item = await self.runClipboardHaiku(contentType: contentType,
                                                        copiedContent: copiedContent,
                                                        context: ctx) {
                onResult(item)
            }
            self.isHaikuRunning = false
        }
    }

    /// Clipboard-focused Haiku prompt — different from the screen/ambient prompt.
    /// Tells Haiku exactly what the user copied and asks what to do with it.
    private func runClipboardHaiku(contentType: String, copiedContent: String, context: SuggestionContext) async -> SuggestionItem? {
        let prompt = buildClipboardPrompt(contentType: contentType, copiedContent: copiedContent, context: context)
        do {
            let response = try await haiku.generate(prompt: prompt)
            Log.info(.pipeline, "Clipboard Haiku response (\(response.count) chars)")
            return deduplicateClipboard(parseResponse(from: response, context: context))
        } catch {
            Log.warn(.pipeline, "Clipboard Haiku failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Like `deduplicate` but with a shorter window for clipboard — 5 min instead of 20 min.
    /// Clipboard content changes fast; we don't want to block a new copy of different text.
    private func deduplicateClipboard(_ item: SuggestionItem?) -> SuggestionItem? {
        guard let item else { return nil }
        let title: String
        switch item {
        case .capability(let m):  title = m.capability.name
        case .task(let t):        title = t.title
        case .question(let q):    title = q.question
        }
        // Short window: only suppress if IDENTICAL title appeared in last 5 min
        let cutoff = Date().addingTimeInterval(-300)
        let recentDupe = recentSuggestions.filter { $0.shownAt >= cutoff }
            .contains { $0.title.lowercased() == title.lowercased() }
        if recentDupe {
            Log.info(.pipeline, "Suppressing duplicate clipboard suggestion: \"\(title)\"")
            return nil
        }
        recordSuggestion(title: title)
        return item
    }

    private func buildClipboardPrompt(contentType: String, copiedContent: String, context: SuggestionContext) -> String {
        var sections: [String] = []

        let contentLabel = contentType == "url" ? "URL" : "text"
        sections.append("""
        The user just copied the following \(contentLabel) to their clipboard. \
        This is the primary signal — they explicitly selected this content. \
        Determine the single most useful action AutoClawd could take with it.
        """)

        // Copied content front and center
        let preview = copiedContent.count > 1500 ? String(copiedContent.prefix(1500)) + "\n…[truncated]" : copiedContent
        sections.append("## Copied \(contentLabel)\n\(preview)")

        sections.append("## Active app\n\(context.app ?? "Unknown")")

        if !context.urls.isEmpty {
            sections.append("## Other visible URLs\n" + context.urls.prefix(5).joined(separator: "\n"))
        }

        if !context.screenText.isEmpty {
            let screen = context.screenText.count > 400
                ? String(context.screenText.prefix(400)) + "…"
                : context.screenText
            sections.append("## Screen context\n\(screen)")
        }

        if !context.transcript.isEmpty {
            sections.append("## Recent voice\n\(context.transcript)")
        }

        if !context.worldModel.isEmpty {
            sections.append("## World model\n\(String(context.worldModel.prefix(600)))")
        }

        sections.append("""
        ## Output — pick exactly ONE:

        HIGH CONFIDENCE (≥ 0.50 for clipboard — user explicitly copied this):
        1. COMPOSING — user copied content to use in something they're writing:
           → {"type":"compose","title":"<verb-first, max 10 words>","draft":"<draft>","subject":"","contacts":"","confidence":0.8}

        2. TASK — clear action to take with the copied content:
           → {"type":"task","title":"<verb-first, max 10 words>","details":"<what and why>","contacts":"","confidence":0.8}

        NEEDS CLARIFICATION (0.40–0.69):
        3. QUESTION:
           → {"type":"question","question":"<what do you want to do with this?>","options":["<action A>","<action B>","Not relevant"],"confidence":0.55}

        NOTHING ACTIONABLE:
        4. → {}

        Rules:
        - Clipboard content is the PRIMARY signal. Base your suggestion on it.
        - Title must start with a verb: Write, Reply, Summarise, Send, Search, Translate, etc.
        - Output ONLY valid JSON. No explanation, no markdown fences.
        """)

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Vision-First Runner (app-switch path)

    /// Tries vision (screenshot → Anthropic API) first; falls back to text Haiku on any error.
    /// Vision is only used on app-switch where the visual context delta is highest signal.
    private func runVisionOrHaiku(context: SuggestionContext) async -> SuggestionItem? {
        let item: SuggestionItem?
        do {
            let raw = try await vision.captureAndGenerate(context: context)
            item = parseResponse(from: raw, context: context)
        } catch ClaudeVisionService.VisionError.noAPIKey {
            Log.info(.pipeline, "Vision: no API key, falling back to text Haiku")
            item = await runHaiku(context: context)
        } catch {
            Log.warn(.pipeline, "Vision failed (\(error.localizedDescription)), falling back to text Haiku")
            item = await runHaiku(context: context)
        }
        return deduplicate(item)
    }

    // MARK: - Shared Haiku Runner

    private func runHaiku(context: SuggestionContext) async -> SuggestionItem? {
        let prompt = buildPrompt(context: context)
        do {
            let response = try await haiku.generate(prompt: prompt)
            Log.info(.pipeline, "Haiku response (\(response.count) chars)")
            let item = parseResponse(from: response, context: context)
            return deduplicate(item)
        } catch {
            Log.warn(.pipeline, "Haiku inference failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Deduplication

    /// Suppresses items whose title was already shown within `deduplicationWindow`.
    /// Records new unique titles for future deduplication.
    private func deduplicate(_ item: SuggestionItem?) -> SuggestionItem? {
        guard let item else { return nil }
        let title: String
        switch item {
        case .capability(let m):  title = m.capability.name
        case .task(let t):        title = t.title
        case .question(let q):    title = q.question
        }
        if isDuplicate(title: title) {
            Log.info(.pipeline, "Suppressing duplicate suggestion: \"\(title)\"")
            return nil
        }
        recordSuggestion(title: title)
        return item
    }

    // MARK: - Prompt

    private func buildPrompt(context: SuggestionContext) -> String {
        var sections: [String] = []

        sections.append("""
        You are an ambient AI agent that can see the user's screen and hear their conversation. \
        Analyze everything below and produce ONE actionable suggestion or clarifying question.
        """)

        sections.append("## App\n\(context.app ?? "Unknown")")

        if !context.urls.isEmpty {
            sections.append("## URLs visible\n" + context.urls.prefix(8).joined(separator: "\n"))
        }

        if !context.screenText.isEmpty {
            // Full OCR — Haiku has 200k context, no need to truncate
            sections.append("## Screen (full OCR)\n\(context.screenText)")
        }

        if !context.clipboard.isEmpty {
            sections.append("## Recent clipboard\n" + context.clipboard.joined(separator: "\n"))
        }

        if !context.transcript.isEmpty {
            sections.append("## Voice transcript (this session)\n\(context.transcript)")
        }

        if !context.worldModel.isEmpty {
            sections.append("## Project world model\n\(String(context.worldModel.prefix(1500)))")
        }

        sections.append("""
        ## Output format — pick exactly ONE:

        HIGH CONFIDENCE (≥ 0.80): clear task or compose opportunity
        1. COMPOSING — user is writing / discussed writing an email, message, or document:
           → {"type":"compose","title":"Help write this [email/message/doc]","draft":"<draft or intent>","subject":"<subject if present>","contacts":"<recipient if visible>","confidence":0.85}

        2. TASK — visible content or transcript contains work to be done (request, bug, TODO, follow-up):
           → {"type":"task","title":"<verb-first, max 10 words>","details":"<what and why>","contacts":"<who requested>","confidence":0.8}

        MEDIUM CONFIDENCE (0.65–0.79): interesting context but one clarification needed
        3. QUESTION — you see something relevant but need one answer to act:
           → {"type":"question","question":"<one specific question, max 20 words>","options":["<action A, max 8 words>","<action B, max 8 words>","Not relevant"],"confidence":0.72}

        LOW CONFIDENCE / NOTHING:
        4. → {}

        Rules:
        - Be specific — use actual names, subjects, URLs from the context. Never invent content.
        - TASK/COMPOSE titles must start with a verb: Write, Fix, Reply, Send, Review, Build, etc.
        - QUESTION options must be concrete actions, not abstract ("Not relevant" always last).
        - Output ONLY valid JSON. No explanation, no markdown fences.
        """)

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Response Parsing

    func parseResponse(from response: String, context: SuggestionContext) -> SuggestionItem? {
        var raw = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("```") {
            let lines = raw.components(separatedBy: "\n")
            raw = lines.dropFirst().dropLast().joined(separator: "\n")
        }
        // Strip any leading prose before the JSON object
        if let jsonStart = raw.firstIndex(of: "{") {
            raw = String(raw[jsonStart...])
        }

        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String, !type.isEmpty
        else { return nil }

        let confidence = (json["confidence"] as? Double).map { Float($0) } ?? 0.5
        guard confidence > 0.65 else { return nil }

        switch type {

        case "question":
            guard let questionText = json["question"] as? String, !questionText.isEmpty else { return nil }
            let options = (json["options"] as? [String]) ?? ["Yes, do it", "Not relevant"]
            let q = SuggestionQuestion(
                id:        UUID().uuidString,
                question:  questionText,
                options:   options,
                context:   context,
                createdAt: Date()
            )
            return .question(q)

        case "compose":
            guard let title = json["title"] as? String, !title.isEmpty else { return nil }
            guard confidence >= 0.80 else {
                // Medium-confidence compose → ask instead of guessing
                let q = SuggestionQuestion(
                    id:        UUID().uuidString,
                    question:  "Should I help you write this?",
                    options:   ["Yes, improve the draft", "Not relevant"],
                    context:   context,
                    createdAt: Date()
                )
                return .question(q)
            }
            let draft   = json["draft"]   as? String ?? ""
            let subject = json["subject"] as? String ?? ""
            let contact = json["contacts"] as? String ?? ""
            let taskCtx = TaskContext(files: [], contacts: contact.isEmpty ? [] : [contact], urls: context.urls, rawOCR: context.screenText)
            var parts   = ["The user is composing content in \(context.app ?? "an app") and needs help."]
            if !subject.isEmpty { parts.append("Subject: \(subject)") }
            if !contact.isEmpty { parts.append("To: \(contact)") }
            parts += ["", "Draft / intent:", draft.isEmpty ? "(see transcript below)" : draft]
            if draft.isEmpty { parts += ["", "Transcript:", context.transcript] }
            parts += ["", "Rewrite to be clear, professional, and effective. Output the improved version only."]
            let task = TaskSuggestion(id: UUID().uuidString, title: title, intent: "compose", detectedContext: taskCtx, executionPrompt: parts.joined(separator: "\n"), confidence: confidence)
            return .task(task)

        default: // "task"
            guard let title = json["title"] as? String, !title.isEmpty else { return nil }
            guard confidence >= 0.80 else {
                let q = SuggestionQuestion(
                    id:        UUID().uuidString,
                    question:  "I noticed: \"\(title)\". Should I help?",
                    options:   ["Yes, let's do it", "Not relevant"],
                    context:   context,
                    createdAt: Date()
                )
                return .question(q)
            }
            let details = json["details"]  as? String ?? ""
            let contact = json["contacts"] as? String ?? ""
            let taskCtx = TaskContext(files: [], contacts: contact.isEmpty ? [] : [contact], urls: context.urls, rawOCR: context.screenText)
            var parts: [String] = ["Task from screen/conversation in \(context.app ?? "unknown"):", title, ""]
            if !details.isEmpty { parts += ["Context: \(details)", ""] }
            if !contact.isEmpty { parts += ["Requested by: \(contact)", ""] }
            if !context.urls.isEmpty { parts += ["Relevant URLs: \(context.urls.joined(separator: ", "))", ""] }
            parts += ["Conversation:", context.transcript, "", "Complete this task. Ask one clarifying question if anything is ambiguous."]
            let task = TaskSuggestion(id: UUID().uuidString, title: title, intent: "task", detectedContext: taskCtx, executionPrompt: parts.joined(separator: "\n"), confidence: confidence)
            return .task(task)
        }
    }
}
