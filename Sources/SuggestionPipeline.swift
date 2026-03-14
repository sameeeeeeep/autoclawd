// Sources/SuggestionPipeline.swift
import Foundation
import AppKit

/// Unified suggestion pipeline. Runs on every OCR+transcript frame.
/// Replaces the inline CapabilityStore.suggest() call in AppState.
/// Declared @MainActor — Llama await suspends on main actor (acceptable for periodic check).
@MainActor
final class SuggestionPipeline {

    private let ollama = OllamaService()
    private var lastTranscriptHash: Int = 0

    // MARK: - Evaluate

    /// Returns the top suggestion for the current frame, or nil if nothing is relevant.
    func evaluate(
        screenText: String,
        transcript: String,
        app: String?,
        urls: [String],
        isOllamaEnabled: Bool
    ) async -> SuggestionItem? {

        // 1. Capability scoring (synchronous)
        let capMatches = CapabilityStore.shared.suggest(
            screenText: screenText,
            transcript: transcript,
            app: app,
            urls: urls
        )

        // 2. Task extraction (Llama — skip if disabled or transcript unchanged)
        var taskSuggestion: TaskSuggestion?
        let hash = transcript.hashValue
        if isOllamaEnabled, !transcript.isEmpty, hash != lastTranscriptHash {
            lastTranscriptHash = hash
            taskSuggestion = await extractTask(
                transcript: transcript,
                screenText: screenText,
                urls: urls
            )
        }

        // 3. Merge: high-confidence tasks win; else capability; else low-confidence task
        if let task = taskSuggestion, task.confidence >= 0.7 {
            return .task(task)
        }
        if let top = capMatches.first {
            return .capability(top)
        }
        if let task = taskSuggestion {
            return .task(task)
        }
        return nil
    }

    // MARK: - Task Extraction

    private func extractTask(
        transcript: String,
        screenText: String,
        urls: [String]
    ) async -> TaskSuggestion? {
        let prompt = """
        Identify one simple, immediately actionable task from the user's speech and screen.

        Speech: \(transcript)
        Screen (OCR): \(String(screenText.prefix(300)))
        URLs: \(urls.joined(separator: ", "))

        If a clear task exists (e.g. "send email to Josh", "post on LinkedIn", "hire a designer"):
        Output JSON: {"title":"...","intent":"email|message|post|hire|schedule|search|other","confidence":0.0-1.0,"files":[],"contacts":[],"urls":[]}

        If NO clear task: output {}
        Output ONLY valid JSON.
        """
        do {
            let response = try await ollama.generate(prompt: prompt, numPredict: 256)
            return parseTask(from: response, screenText: screenText, fallbackURLs: urls)
        } catch {
            // Silently discard — matches existing pipeline pattern for Llama failures.
            // Capability suggestions still surface; task suggestions are dropped for this frame.
            return nil
        }
    }

    private func parseTask(
        from response: String,
        screenText: String,
        fallbackURLs: [String]
    ) -> TaskSuggestion? {
        // Extract JSON block
        let raw = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = json["title"] as? String, !title.isEmpty,
              let intent = json["intent"] as? String
        else { return nil }

        let confidence = (json["confidence"] as? Double).map { Float($0) } ?? 0.5
        let files     = json["files"]    as? [String] ?? []
        let contacts  = json["contacts"] as? [String] ?? []
        let urls      = json["urls"]     as? [String] ?? fallbackURLs

        let context = TaskContext(files: files, contacts: contacts, urls: urls, rawOCR: screenText)

        var promptParts = ["Task: \(title)"]
        if !files.isEmpty    { promptParts.append("Files: \(files.joined(separator: ", "))") }
        if !contacts.isEmpty { promptParts.append("Contacts: \(contacts.joined(separator: ", "))") }
        if !urls.isEmpty     { promptParts.append("URLs: \(urls.joined(separator: ", "))") }
        promptParts.append("Screen context: \(String(screenText.prefix(200)))")
        promptParts.append("Complete this task. Ask for any missing required information.")

        return TaskSuggestion(
            id: UUID().uuidString,
            title: title,
            intent: intent,
            detectedContext: context,
            executionPrompt: promptParts.joined(separator: "\n"),
            confidence: confidence
        )
    }
}
