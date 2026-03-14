// Sources/SuggestionPipeline.swift
import Foundation
import AppKit

/// Unified suggestion pipeline. Runs on every OCR+transcript frame.
///
/// Three parallel paths:
///   1. Capability scoring (sync, keyword/URL/app matching) — always runs
///   2. Context-aware task/compose extraction — fires when screen OR transcript changes
///      Uses llama3.1:8b (local, smarter) for nuanced screen understanding.
///   3. Passive automation detection — fires every 90s from rolling activity buffer
///      Detects repetitive multi-app workflows; surfaces FUCBC-style automations.
///
/// Model split (all local via Ollama):
///   - llama3.2 (3B) → pipeline cleaning/analysis (high-frequency, ~every 30s)
///   - llama3.1:8b   → suggestion extraction (low-frequency, debounced; needs more nuance)
///
/// Guards (prevent Ollama overload):
///   - In-flight lock (`isExtracting`) — only one model call at a time
///   - 5s debounce (`lastExtractionAt`) — absorbs rapid OCR frame changes
///   - 30s capability cooldown (`lastSuggestedCapabilityID`)
///
/// Declared @MainActor — async awaits suspend on main actor (acceptable for periodic checks).
@MainActor
final class SuggestionPipeline {

    // llama3.2 (3B) handles the high-frequency cleaning/analysis pipeline.
    // This pipeline uses llama3.1:8b — still fully local, but substantially smarter
    // for nuanced screen context understanding (compose detection, task extraction).
    // Falls back to llama3.2 if 8b isn't pulled yet (Ollama returns an error which we catch).
    private let ollama = OllamaService(model: "llama3.1:8b")
    private let ollamaFallback = OllamaService()  // llama3.2 (3B) fallback

    // MARK: - Extraction Guards

    // Hash of (transcript + screenText) — fires extraction when EITHER changes.
    private var lastContextHash: Int = 0

    // In-flight lock — one Llama/Groq call at a time; prevents call pile-ups.
    private var isExtracting = false

    // Debounce — minimum 5s between extraction attempts; absorbs rapid OCR frame changes.
    private var lastExtractionAt: Date = .distantPast
    private let extractionDebounce: TimeInterval = 5.0

    // Deduplication: don't re-surface the same capability within cooldown window.
    private var lastSuggestedCapabilityID: String?
    private var lastSuggestedAt: Date = .distantPast
    private let capabilityCooldown: TimeInterval = 30.0

    // MARK: - Activity Buffer (passive automation detection)

    private struct ActivityFrame {
        let timestamp: Date
        let app: String
        let windowTitle: String
        let ocrSnippet: String  // first 200 chars — enough for pattern matching
    }

    private var activityBuffer: [ActivityFrame] = []
    private let activityBufferMax = 120           // ~10 min at 5s OCR interval
    private var lastAutomationCheckAt: Date = .distantPast
    private let automationCheckInterval: TimeInterval = 90.0

    // MARK: - Evaluate

    /// Returns the top suggestion for the current frame, or nil if nothing is relevant.
    func evaluate(
        screenText: String,
        transcript: String,
        app: String?,
        urls: [String],
        isOllamaEnabled: Bool
    ) async -> SuggestionItem? {

        let appName = app ?? "Unknown"

        // 0. Buffer this frame for passive automation detection
        bufferActivity(app: appName, ocrSnippet: screenText)

        // 1. Capability scoring (synchronous — always runs)
        let capMatches = CapabilityStore.shared.suggest(
            screenText: screenText,
            transcript: transcript,
            app: app,
            urls: urls
        )

        // 2. Context-aware task/compose extraction.
        // Guards: in-flight lock + 5s debounce + hash change.
        var taskSuggestion: TaskSuggestion?
        let contextHash = (transcript + screenText).hashValue
        let debounceOk  = Date().timeIntervalSince(lastExtractionAt) >= extractionDebounce

        if isOllamaEnabled, !screenText.isEmpty,
           contextHash != lastContextHash,
           !isExtracting, debounceOk {
            lastContextHash  = contextHash
            lastExtractionAt = Date()
            isExtracting     = true
            taskSuggestion   = await extractTask(
                transcript: transcript,
                screenText: screenText,
                app: app,
                urls: urls
            )
            isExtracting = false
        }

        // 3. Passive automation detection (every 90s, only when path 2 is idle).
        if isOllamaEnabled,
           Date().timeIntervalSince(lastAutomationCheckAt) >= automationCheckInterval,
           !isExtracting, taskSuggestion == nil {
            lastAutomationCheckAt = Date()
            isExtracting = true
            if let autoSuggestion = await detectAutomation() {
                taskSuggestion = autoSuggestion
            }
            isExtracting = false
        }

        // 4. Merge: high-confidence tasks win; else capability (with cooldown); else low-confidence task
        if let task = taskSuggestion, task.confidence >= 0.7 {
            return .task(task)
        }
        if let top = capMatches.first {
            let id      = top.capability.id
            let elapsed = Date().timeIntervalSince(lastSuggestedAt)
            if id == lastSuggestedCapabilityID, elapsed < capabilityCooldown {
                // Same capability shown recently — suppress until cooldown expires
            } else {
                lastSuggestedCapabilityID = id
                lastSuggestedAt = Date()
                return .capability(top)
            }
        }
        if let task = taskSuggestion {
            return .task(task)
        }
        return nil
    }

    // MARK: - Activity Buffer

    private func bufferActivity(app: String, ocrSnippet: String) {
        let windowTitle = Self.accessibilityWindowTitle() ?? ""
        let frame = ActivityFrame(
            timestamp:   Date(),
            app:         app,
            windowTitle: windowTitle,
            ocrSnippet:  String(ocrSnippet.prefix(200))
                .replacingOccurrences(of: "\n", with: " ")
        )
        activityBuffer.append(frame)
        if activityBuffer.count > activityBufferMax {
            activityBuffer.removeFirst(activityBuffer.count - activityBufferMax)
        }
    }

    // MARK: - Context-Aware Task Extraction

    /// Screen-aware extraction. Understands two situations:
    ///   - COMPOSING: user is actively writing something → offer compose assistance
    ///   - TASK IN CONTENT: visible text contains a request/action item → extract and run it
    ///
    /// Uses llama3.1:8b locally (smarter than 3B); falls back to llama3.2 if not pulled.
    private func extractTask(
        transcript: String,
        screenText: String,
        app: String?,
        urls: [String]
    ) async -> TaskSuggestion? {
        let appName      = app ?? "Unknown"
        let screenSample = String(screenText.prefix(1500))
        let urlList      = urls.prefix(5).joined(separator: ", ")

        let prompt = """
        You are an ambient AI agent that can see the user's screen. Analyze what is visible and extract one actionable suggestion.

        App: \(appName)
        Screen (OCR):
        \(screenSample)
        Speech (if any): \(transcript.isEmpty ? "(silent)" : transcript)
        URLs: \(urlList.isEmpty ? "none" : urlList)

        Detect ONE of these situations:

        1. COMPOSING — user is actively writing an email draft, message, or document in progress:
           Indicators: "To:", "Subject:", "Cc:", partial draft text in a compose window, unfinished message in an input box.
           → {"type":"compose","title":"Help write this [email/message]","draft":"<the visible draft text, verbatim>","subject":"<subject line if present>","contacts":"<recipient name if visible>","confidence":0.85}

        2. TASK IN CONTENT — visible text contains work to be done (a request, TODO, action item):
           Indicators: someone asking the user to do something ("can you fix", "please send", "we need"), task lists, bug reports, work messages in WhatsApp/Slack/email.
           → {"type":"task","title":"<verb-first action, max 10 words>","details":"<what needs doing and any relevant context>","contacts":"<who sent/requested it if visible>","confidence":0.8}

        3. NOTHING ACTIONABLE — user is browsing, reading news, watching a video, no clear next action:
           → {}

        Rules:
        - Only output if confidence > 0.65
        - Use actual text visible on screen — do not invent content
        - Title must start with an action verb: Write, Fix, Reply, Send, Complete, Review, etc.
        - Output ONLY valid JSON. No explanation, no markdown fences.
        """

        do {
            // Try llama3.1:8b first (smarter, still fully local).
            // Falls back to llama3.2 (3B) if 8b isn't available.
            let response: String
            do {
                response = try await ollama.generate(prompt: prompt, numPredict: 320)
            } catch {
                response = try await ollamaFallback.generate(prompt: prompt, numPredict: 320)
            }
            return parseTask(from: response, app: appName, screenText: screenText, fallbackURLs: urls)
        } catch {
            // Silently discard — capability suggestions still surface even if extraction fails.
            return nil
        }
    }

    // MARK: - Passive Automation Detection

    /// Analyses the rolling activity buffer (~2 min window) for repetitive multi-app workflows.
    /// Fires every 90s. Returns a `TaskSuggestion` with intent="automation" if a pattern is found.
    private func detectAutomation() async -> TaskSuggestion? {
        // Need at least 6 frames (~30s) to detect a pattern
        guard activityBuffer.count >= 6 else { return nil }

        // Build compact narrative of unique recent steps (last 24 frames ≈ 2 min)
        let recentFrames = activityBuffer.suffix(24)
        guard let firstTime = recentFrames.first?.timestamp else { return nil }

        var seenKeys: [String] = []
        var narrativeLines: [String] = []
        for frame in recentFrames {
            let key = "\(frame.app)|\(frame.windowTitle)"
            guard !seenKeys.contains(key) else { continue }
            seenKeys.append(key)
            let elapsed  = Int(frame.timestamp.timeIntervalSince(firstTime))
            let appLabel = frame.windowTitle.isEmpty ? frame.app : "\(frame.app) — \(frame.windowTitle)"
            narrativeLines.append("T+\(elapsed)s [\(appLabel)] \(frame.ocrSnippet.prefix(80))")
        }

        // Need at least 3 distinct steps across 2+ apps to be interesting
        let distinctApps = Set(recentFrames.map { $0.app })
        guard narrativeLines.count >= 3, distinctApps.count >= 2 else { return nil }

        let narrative  = narrativeLines.joined(separator: "\n")
        let appsInvolved = distinctApps.prefix(5).joined(separator: ", ")

        let prompt = """
        You are an automation analyst observing a user's workflow. Detect if there is a REPETITIVE MULTI-STEP WORKFLOW that could be automated.

        Recent activity (last ~2 minutes):
        \(narrative)

        If you see a clear repeatable workflow spanning 2+ apps or 3+ manual steps the user performs regularly:
        → {"type":"automation","title":"<verb-first, max 10 words>","details":"<what the workflow does and why automating it saves time>","confidence":0.75}

        If this is just normal browsing / one-off activity with no repeatable pattern:
        → {}

        Rules:
        - Only suggest if confidence > 0.70 AND the pattern is genuinely repetitive
        - Title must start with: Automate, Build, Create, or Set up
        - Output ONLY valid JSON. No explanation.
        """

        do {
            let response: String
            do {
                response = try await ollama.generate(prompt: prompt, numPredict: 200)
            } catch {
                response = try await ollamaFallback.generate(prompt: prompt, numPredict: 200)
            }

            // Parse JSON — automation intent maps to a task suggestion with executionPrompt for FUCBC
            var raw = response.trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.hasPrefix("```") {
                let lines = raw.components(separatedBy: "\n")
                raw = lines.dropFirst().dropLast().joined(separator: "\n")
            }
            guard let data  = raw.data(using: .utf8),
                  let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type  = json["type"]  as? String, type == "automation",
                  let title = json["title"] as? String, !title.isEmpty
            else { return nil }

            let confidence = (json["confidence"] as? Double).map { Float($0) } ?? 0.5
            guard confidence > 0.70 else { return nil }

            let details = json["details"] as? String ?? ""

            let executionPrompt = """
            Automation opportunity detected from screen activity.

            Workflow: \(title)
            \(details.isEmpty ? "" : "Details: \(details)\n")
            Apps involved: \(appsInvolved)

            Recent activity:
            \(narrative)

            Build a FUCBC capability (SKILL.md) that automates this workflow. Steps:
            1. Identify the exact repeated manual steps
            2. Automate each step using available tools (shell commands, APIs, Claude)
            3. Chain them into a single command the user can run next time

            Start by describing what you'll automate, then write the SKILL.md.
            """

            let context = TaskContext(
                files: [], contacts: [], urls: [], rawOCR: narrative
            )
            return TaskSuggestion(
                id:               UUID().uuidString,
                title:            title,
                intent:           "automation",
                detectedContext:  context,
                executionPrompt:  executionPrompt,
                confidence:       confidence
            )
        } catch {
            return nil
        }
    }

    // MARK: - Task Parsing

    private func parseTask(
        from response: String,
        app: String,
        screenText: String,
        fallbackURLs: [String]
    ) -> TaskSuggestion? {
        // Strip markdown fences if model wraps the output
        var raw = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("```") {
            let lines = raw.components(separatedBy: "\n")
            raw = lines.dropFirst().dropLast().joined(separator: "\n")
        }

        guard let data  = raw.data(using: .utf8),
              let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type  = json["type"]  as? String, !type.isEmpty,
              let title = json["title"] as? String, !title.isEmpty
        else { return nil }

        let confidence = (json["confidence"] as? Double).map { Float($0) } ?? 0.5
        guard confidence > 0.65 else { return nil }

        let contactStr = json["contacts"] as? String ?? ""
        let contacts   = contactStr.isEmpty ? [] : [contactStr]
        let context    = TaskContext(files: [], contacts: contacts, urls: fallbackURLs, rawOCR: screenText)

        let intent: String
        let executionPrompt: String

        switch type {

        case "compose":
            // User is actively writing — help them write it better
            intent = "compose"
            let draft   = json["draft"]   as? String ?? ""
            let subject = json["subject"] as? String ?? ""

            var parts: [String] = [
                "The user is composing content in \(app) and needs help improving it."
            ]
            if !subject.isEmpty    { parts.append("Subject: \(subject)") }
            if !contactStr.isEmpty { parts.append("To: \(contactStr)") }
            parts.append("")
            parts.append("Current draft:")
            parts.append(draft.isEmpty ? "(see screen context below)" : draft)
            if draft.isEmpty {
                parts.append("")
                parts.append("Screen context:")
                parts.append(String(screenText.prefix(800)))
            }
            parts.append("")
            parts.append("Rewrite this to be clear, professional, and effective. Output the improved version only — ready to be pasted back. Do not add commentary or explanation.")
            executionPrompt = parts.joined(separator: "\n")

        default:
            // type == "task" — visible content contains work to do
            intent = "task"
            let details = json["details"] as? String ?? ""

            var parts: [String] = [
                "Task detected from screen content in \(app):",
                title,
                ""
            ]
            if !details.isEmpty      { parts.append("Context: \(details)"); parts.append("") }
            if !contacts.isEmpty     { parts.append("Requested by / involves: \(contacts.joined(separator: ", "))"); parts.append("") }
            if !fallbackURLs.isEmpty { parts.append("Relevant URLs: \(fallbackURLs.joined(separator: ", "))"); parts.append("") }
            parts.append("Screen context:")
            parts.append(String(screenText.prefix(600)))
            parts.append("")
            parts.append("Complete this task. If anything is ambiguous, ask one clarifying question before proceeding.")
            executionPrompt = parts.joined(separator: "\n")
        }

        return TaskSuggestion(
            id:              UUID().uuidString,
            title:           title,
            intent:          intent,
            detectedContext: context,
            executionPrompt: executionPrompt,
            confidence:      confidence
        )
    }

    // MARK: - AX Window Title Helper

    private static func accessibilityWindowTitle() -> String? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let axApp = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let window = windowRef else { return nil }
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &titleRef) == .success
        else { return nil }
        return titleRef as? String
    }
}
