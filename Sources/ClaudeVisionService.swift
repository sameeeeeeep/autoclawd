// Sources/ClaudeVisionService.swift
import AppKit
import Foundation

/// Direct Anthropic API call with vision — sends the current screenshot (JPEG, base64)
/// plus OCR text and context to claude-haiku-4-5-20251001 (vision-capable).
///
/// Used on app-switch events where visual context (layout, colours, UI state) gives
/// meaningfully better suggestions than OCR text alone.
///
/// Requires `ANTHROPIC_API_KEY` in SettingsManager (the same key used for Claude Code).
/// If the key is absent, `captureAndGenerate()` throws `.noAPIKey` and the call site
/// falls back to the text-only Haiku path.
final class ClaudeVisionService: @unchecked Sendable {

    static let model          = "claude-haiku-4-5-20251001"
    static let apiEndpoint    = "https://api.anthropic.com/v1/messages"
    static let maxDimension: CGFloat = 1024   // px — keeps image tokens reasonable
    static let jpegQuality: CGFloat  = 0.65

    enum VisionError: Error, LocalizedError {
        case noAPIKey
        case screenshotFailed
        case imageEncodingFailed
        case network(Error)
        case httpError(Int, String)
        case emptyContent

        var errorDescription: String? {
            switch self {
            case .noAPIKey:             return "No Anthropic API key configured"
            case .screenshotFailed:     return "Screenshot capture failed"
            case .imageEncodingFailed:  return "JPEG encoding failed"
            case .network(let e):       return "Network: \(e.localizedDescription)"
            case .httpError(let c, let m): return "HTTP \(c): \(m)"
            case .emptyContent:         return "Empty content in API response"
            }
        }
    }

    // MARK: - Public Entry Point

    /// Captures the current screen and runs vision analysis via the Anthropic API.
    /// Returns raw response text (JSON) for parsing by `SuggestionPipeline`.
    /// Throws `VisionError` — caller should catch and fall back to text Haiku.
    func captureAndGenerate(context: SuggestionContext) async throws -> String {
        let apiKey = SettingsManager.shared.anthropicAPIKey
        guard !apiKey.isEmpty else { throw VisionError.noAPIKey }

        // 1. Capture + encode screenshot
        guard let nsImage = ScreenshotService.captureAndResize(maxDimension: Self.maxDimension) else {
            throw VisionError.screenshotFailed
        }
        guard let b64 = jpegBase64(nsImage) else {
            throw VisionError.imageEncodingFailed
        }

        Log.info(.pipeline, "ClaudeVisionService: screenshot \(nsImage.size.width.rounded())×\(nsImage.size.height.rounded()) encoded")

        // 2. Build request
        let prompt = buildPrompt(context: context)
        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 512,
            "messages": [[
                "role": "user",
                "content": [
                    [
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": b64
                        ]
                    ],
                    [
                        "type": "text",
                        "text": prompt
                    ]
                ]
            ]]
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var req = URLRequest(url: URL(string: Self.apiEndpoint)!)
        req.httpMethod = "POST"
        req.setValue(apiKey,        forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01",  forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = bodyData
        req.timeoutInterval = 30

        // 3. Send
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw VisionError.network(error)
        }

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8)?.prefix(300).description ?? "unknown"
            throw VisionError.httpError(http.statusCode, msg)
        }

        // 4. Extract text from response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentArr = json["content"] as? [[String: Any]],
              let text = contentArr.first?["text"] as? String,
              !text.isEmpty
        else { throw VisionError.emptyContent }

        Log.info(.pipeline, "ClaudeVisionService: response \(text.count) chars")
        return text
    }

    // MARK: - Image Encoding

    private func jpegBase64(_ image: NSImage) -> String? {
        guard let tiff   = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg   = bitmap.representation(using: .jpeg,
                               properties: [.compressionFactor: Self.jpegQuality])
        else { return nil }
        return jpeg.base64EncodedString()
    }

    // MARK: - Prompt

    private func buildPrompt(context: SuggestionContext) -> String {
        var sections: [String] = []

        sections.append("""
        You are an ambient AI agent. The screenshot shows exactly what the user sees right now. \
        Analyse the screenshot AND the supplementary context below, then produce ONE actionable suggestion.
        """)

        sections.append("## Active app\n\(context.app ?? "Unknown")")

        if !context.urls.isEmpty {
            sections.append("## Detected URLs\n" + context.urls.prefix(8).joined(separator: "\n"))
        }

        if !context.screenText.isEmpty {
            // OCR as supplementary — vision is primary signal
            let preview = context.screenText.count > 600
                ? String(context.screenText.prefix(600)) + "…"
                : context.screenText
            sections.append("## OCR text (supplementary)\n\(preview)")
        }

        if !context.clipboard.isEmpty {
            sections.append("## Recent clipboard\n" + context.clipboard.joined(separator: "\n"))
        }

        if !context.transcript.isEmpty {
            sections.append("## Voice transcript\n\(context.transcript)")
        }

        if !context.worldModel.isEmpty {
            sections.append("## Project world model\n\(String(context.worldModel.prefix(800)))")
        }

        sections.append("""
        ## Output — pick exactly ONE:

        HIGH CONFIDENCE (≥ 0.80): clear task or compose opportunity
        1. COMPOSING — user is writing / drafting content:
           → {"type":"compose","title":"Help write this [email/message/doc]","draft":"<draft>","subject":"<subject>","contacts":"<recipient>","confidence":0.85}

        2. TASK — something visible needs action:
           → {"type":"task","title":"<verb-first, max 10 words>","details":"<what and why>","contacts":"<who>","confidence":0.8}

        MEDIUM CONFIDENCE (0.65–0.79): needs clarification before acting
        3. QUESTION:
           → {"type":"question","question":"<one specific question, max 20 words>","options":["<action A, max 8 words>","<action B, max 8 words>","Not relevant"],"confidence":0.72}

        LOW CONFIDENCE / NOTHING:
        4. → {}

        Rules:
        - Base your answer on WHAT IS VISIBLE in the screenshot — be specific.
        - Titles start with a verb: Write, Fix, Reply, Send, Review, Build, etc.
        - Output ONLY valid JSON. No explanation, no markdown fences.
        """)

        return sections.joined(separator: "\n\n")
    }
}
