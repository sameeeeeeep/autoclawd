// Sources/SuggestionPipeline.swift
import Foundation
import AppKit

/// Unified suggestion pipeline. Runs on every OCR+transcript frame.
/// Two parallel paths:
///   1. Capability scoring (sync, keyword/URL/app matching) — always runs
///   2. Context-aware task extraction (Llama, async) — fires when screen OR transcript changes
///
/// Task extraction understands two screen situations:
///   - COMPOSING: user is writing an email/message/doc → offer to help write it better
///   - TASK IN CONTENT: visible text (WhatsApp message, email, page) contains work → extract + run it
///
/// Declared @MainActor — Llama await suspends on main actor (acceptable for periodic check).
@MainActor
final class SuggestionPipeline {

    private let ollama = OllamaService()

    // Hash of (transcript + screenText) — fires extraction when EITHER changes, not just speech.
    // This catches compose scenarios (email drafts, WhatsApp typing) even when the user is silent.
    private var lastContextHash: Int = 0

    // Deduplication: don't re-surface the same capability within cooldown window.
    private var lastSuggestedCapabilityID: String?
    private var lastSuggestedAt: Date = .distantPast
    private let capabilityCooldown: TimeInterval = 30.0

    // MARK: - Evaluate

    /// Returns the top suggestion for the current frame, or nil if nothing is relevant.
    func evaluate(
        screenText: String,
        transcript: String,
        app: String?,
        urls: [String],
        isOllamaEnabled: Bool
    ) async -> SuggestionItem? {

        // 1. Capability scoring (synchronous — always runs)
        let capMatches = CapabilityStore.shared.suggest(
            screenText: screenText,
            transcript: transcript,
            app: app,
            urls: urls
        )

        // 2. Context-aware task/compose extraction via Llama.
        // Fires when screen content OR transcript changes — not just speech.
        // This catches: email drafts being typed, WhatsApp messages with work requests, etc.
        var taskSuggestion: TaskSuggestion?
        let contextHash = (transcript + screenText).hashValue
        if isOllamaEnabled, !screenText.isEmpty, contextHash != lastContextHash {
            lastContextHash = contextHash
            taskSuggestion = await extractTask(
                transcript: transcript,
                screenText: screenText,
                app: app,
                urls: urls
            )
        }

        // 3. Merge: high-confidence tasks win; else capability (with cooldown); else low-confidence task
        if let task = taskSuggestion, task.confidence >= 0.7 {
            return .task(task)
        }
        if let top = capMatches.first {
            let id = top.capability.id
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

    // MARK: - Context-Aware Task Extraction

    /// Screen-aware Llama extraction. Understands two situations:
    ///   - COMPOSING: user is actively writing something → offer compose assistance
    ///   - TASK IN CONTENT: visible text contains a request/action item → extract and execute it
    private func extractTask(
        transcript: String,
        screenText: String,
        app: String?,
        urls: [String]
    ) async -> TaskSuggestion? {
        let appName    = app ?? "Unknown"
        // 1500 chars — enough to capture a full email body or WhatsApp thread (was 300)
        let screenSample = String(screenText.prefix(1500))
        let urlList    = urls.prefix(5).joined(separator: ", ")

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
            let response = try await ollama.generate(prompt: prompt, numPredict: 320)
            return parseTask(from: response, app: appName, screenText: screenText, fallbackURLs: urls)
        } catch {
            // Silently discard — capability suggestions still surface even if Llama fails.
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
        // Strip markdown fences if Llama wraps the output
        var raw = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("```") {
            let lines = raw.components(separatedBy: "\n")
            raw = lines.dropFirst().dropLast().joined(separator: "\n")
        }

        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
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
            if !subject.isEmpty { parts.append("Subject: \(subject)") }
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
            if !details.isEmpty   { parts.append("Context: \(details)"); parts.append("") }
            if !contacts.isEmpty  { parts.append("Requested by / involves: \(contacts.joined(separator: ", "))"); parts.append("") }
            if !fallbackURLs.isEmpty { parts.append("Relevant URLs: \(fallbackURLs.joined(separator: ", "))"); parts.append("") }
            parts.append("Screen context:")
            parts.append(String(screenText.prefix(600)))
            parts.append("")
            parts.append("Complete this task. If anything is ambiguous, ask one clarifying question before proceeding.")
            executionPrompt = parts.joined(separator: "\n")
        }

        return TaskSuggestion(
            id: UUID().uuidString,
            title: title,
            intent: intent,
            detectedContext: context,
            executionPrompt: executionPrompt,
            confidence: confidence
        )
    }
}
