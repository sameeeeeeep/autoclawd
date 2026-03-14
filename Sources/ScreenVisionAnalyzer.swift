import CoreGraphics
import Foundation
import Vision

#if canImport(AppKit)
import AppKit
#endif

// MARK: - ScreenSnapshot

/// Rich snapshot of what was on screen at a point in time.
/// The image is saved to ContextCaptureStore so it auto-attaches to tasks.
/// The text and metadata go directly into Claude Code task prompts — bypassing Llama.
struct ScreenSnapshot {
    let capturedAt: Date
    let appName: String?          // e.g. "Xcode"
    let windowTitle: String?      // e.g. "ContentView.swift — autoclawd"
    let extractedText: String     // full-window OCR result
    var croppedText: String?      // OCR of user-selected region (nil = no selection)
    let detectedURLs: [String]    // from QR / barcodes
    let hasDialog: Bool           // prominent dialog/modal detected
    let savedImagePath: String?   // path in ContextCaptureStore — becomes task attachment

    /// Lightweight string safe for Llama (no bulk OCR).
    /// When user made a selection, the cropped OCR is small enough to include too.
    func metadataContext() -> String {
        var parts: [String] = []
        if let app = appName    { parts.append("App: \(app)") }
        if let title = windowTitle { parts.append("Window: \(title)") }
        if hasDialog              { parts.append("Modal/dialog visible") }
        if !detectedURLs.isEmpty  { parts.append("QR/URLs: \(detectedURLs.joined(separator: ", "))") }

        var result = parts.joined(separator: " | ")
        // Cropped text is small — safe to include for Llama
        if let cropped = croppedText, !cropped.isEmpty {
            let truncated = cropped.count > 800 ? String(cropped.prefix(800)) + "…" : cropped
            result += result.isEmpty ? "" : "\n"
            result += "Selected region text:\n\(truncated)"
        }
        return result
    }

    /// Full context for Claude Code task prompts — rich, not Llama-filtered.
    /// Uses cropped text if a selection was made, otherwise falls back to full OCR.
    func executionContext() -> String {
        let text = croppedText ?? extractedText
        guard !text.isEmpty else { return metadataContext() }
        var parts: [String] = []
        if let app = appName    { parts.append("App: \(app)") }
        if let title = windowTitle { parts.append("Window: \(title)") }
        if hasDialog              { parts.append("Dialog visible") }
        if !detectedURLs.isEmpty  { parts.append("URLs: \(detectedURLs.joined(separator: ", "))") }

        let header = parts.isEmpty ? "" : parts.joined(separator: " | ") + "\n"
        let truncated = text.count > 3000 ? String(text.prefix(3000)) + "\n[…truncated]" : text
        return "SCREEN CONTEXT (\(croppedText != nil ? "selected region" : "full window"), \(formattedTime())):\n\(header)Visible text:\n\(truncated)"
    }

    private func formattedTime() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: capturedAt)
    }
}

// MARK: - ScreenVisionAnalyzer

/// Two modes:
/// 1. **Background** — `processFrame(_:)` runs OCR every 10s on system audio screen frames.
///    Used for passive context injection at session end.
/// 2. **On-demand** — `captureNow()` grabs the frontmost window immediately, runs rich Vision
///    (OCR + barcode + rectangle detection), saves screenshot as a ContextCaptureStore entry
///    (so it auto-attaches to tasks), and returns a ScreenSnapshot for prompt injection.
///
/// The screen context (OCR text) flows directly into Claude Code prompts — it never goes
/// through Llama. Llama only sees the voice transcript; Claude gets both.
final class ScreenVisionAnalyzer: @unchecked Sendable {

    // MARK: - Configuration

    /// How often passive background OCR runs when in **ambient** mode (seconds).
    /// Reduced from 10s to 30s — app-switch events cover active usage.
    var ocrInterval: TimeInterval = 30.0
    /// How many background OCR samples to keep.
    var maxSamples: Int = 6

    // MARK: - Learn Mode

    /// When true (Learn Mode active), OCR runs at `learnModeOCRInterval` instead of `ocrInterval`.
    var isLearnMode: Bool = false {
        didSet {
            Log.info(.camera, "ScreenVisionAnalyzer: isLearnMode → \(isLearnMode) (interval: \(isLearnMode ? learnModeOCRInterval : ocrInterval)s)")
        }
    }
    /// OCR capture interval during Learn Mode — higher resolution for workflow capture.
    var learnModeOCRInterval: TimeInterval = 2.0

    // MARK: - Ambient OCR Budget

    /// Max OCR calls per hour in ambient mode. Resets every 60 minutes.
    var maxOCRCallsPerHour: Int = 60
    private var ocrCallsThisHour: Int = 0
    private var ocrHourWindowStart: Date = Date()

    // MARK: - Background OCR State

    private let lock = NSLock()
    private var lastOCRTime: Date = .distantPast
    private var textSamples: [String] = []
    private var isRunning = false

    // MARK: - Budget Check

    private func canRunOCR() -> Bool {
        lock.withLock {
            let now = Date()
            if now.timeIntervalSince(ocrHourWindowStart) >= 3600 {
                ocrCallsThisHour = 0
                ocrHourWindowStart = now
            }
            return ocrCallsThisHour < maxOCRCallsPerHour
        }
    }

    private func recordOCRCall() {
        lock.withLock { ocrCallsThisHour += 1 }
    }

    // MARK: - Session Lifecycle

    func resetForNewSession() {
        lock.withLock {
            textSamples.removeAll()
            lastOCRTime = .distantPast
        }
    }

    // MARK: - Background Frame Processing

    /// Call from `SystemAudioCapturer.onFrame`. Throttled internally — safe at 1fps.
    func processFrame(_ image: CGImage) {
        let shouldRun: Bool = lock.withLock {
            guard !isRunning,
                  Date().timeIntervalSince(lastOCRTime) >= ocrInterval
            else { return false }
            isRunning = true
            lastOCRTime = Date()
            return true
        }
        guard shouldRun else { return }

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let text = self.runOCR(on: image)
            self.lock.withLock {
                self.isRunning = false
                if !text.isEmpty {
                    self.textSamples.append(text)
                    if self.textSamples.count > self.maxSamples {
                        self.textSamples.removeFirst()
                    }
                }
            }
        }
    }

    /// Returns deduplicated rolling buffer text for session-end LLM injection.
    func recentContext() -> String? {
        let samples = lock.withLock { textSamples }
        guard !samples.isEmpty else { return nil }
        var seen: Set<String> = []
        let unique = samples.filter { seen.insert($0).inserted }
        let joined = unique.joined(separator: "\n---\n")
        return joined.isEmpty ? nil : joined
    }

    // MARK: - App-Switch Capture

    /// Called when the frontmost app changes (ambient mode only).
    /// Lightweight OCR only — no barcode or rectangle detection.
    /// Respects the hourly OCR budget. Appends to rolling `textSamples` buffer.
    func captureOnAppSwitch() async {
        guard canRunOCR() else {
            Log.info(.camera, "ScreenVisionAnalyzer: app-switch OCR skipped (hourly budget reached)")
            return
        }

        let shouldRun: Bool = lock.withLock {
            guard !isRunning else { return false }
            isRunning = true
            lastOCRTime = Date()
            return true
        }
        guard shouldRun else { return }

        let (_, windowID, _) = await MainActor.run {
            let app = NSWorkspace.shared.frontmostApplication
            let info = Self.frontmostWindowInfo(appPID: app?.processIdentifier)
            return (app?.localizedName, info?.windowID ?? kCGNullWindowID, info?.title)
        }

        guard let cgImage = Self.captureWindow(windowID: windowID) else {
            lock.withLock { isRunning = false }
            return
        }

        let text = runOCR(on: cgImage)
        recordOCRCall()

        lock.withLock {
            isRunning = false
            if !text.isEmpty {
                textSamples.append(text)
                if textSamples.count > maxSamples { textSamples.removeFirst() }
            }
        }

        Log.info(.camera, "ScreenVisionAnalyzer: app-switch OCR \(text.count) chars")
    }

    // MARK: - On-Demand Capture

    /// Captures the frontmost window immediately. Runs full Vision suite.
    /// Saves a screenshot to ContextCaptureStore (auto-attaches to next task).
    /// Returns a ScreenSnapshot with OCR text and metadata for direct Claude injection.
    func captureNow() async -> ScreenSnapshot? {
        let (appName, windowID, windowTitle) = await MainActor.run {
            let app = NSWorkspace.shared.frontmostApplication
            let info = Self.frontmostWindowInfo(appPID: app?.processIdentifier)
            return (app?.localizedName, info?.windowID ?? kCGNullWindowID, info?.title)
        }

        // Capture the window (or full screen if no specific window found)
        guard let cgImage = Self.captureWindow(windowID: windowID) else {
            Log.warn(.camera, "ScreenVisionAnalyzer: failed to capture window")
            return nil
        }

        // Run rich Vision suite off the calling thread
        let (text, urls, hasDialog) = runRichVision(on: cgImage)

        // Save image to ContextCaptureStore so it auto-attaches to tasks
        let imagePath = saveCapture(cgImage, appName: appName, windowTitle: windowTitle)

        let snapshot = ScreenSnapshot(
            capturedAt: Date(),
            appName: appName,
            windowTitle: windowTitle,
            extractedText: text,
            croppedText: nil,
            detectedURLs: urls,
            hasDialog: hasDialog,
            savedImagePath: imagePath
        )

        Log.info(.camera, "ScreenVisionAnalyzer: captured '\(appName ?? "unknown")' " +
                 "\(text.count) chars OCR, \(urls.count) URLs, dialog=\(hasDialog)")
        return snapshot
    }

    /// Apply a user selection rect (normalized 0-1) to an existing snapshot.
    /// Crops the saved image, runs OCR on just that region, saves the crop.
    /// Returns a new snapshot with `croppedText` set.
    func applySelection(normalizedRect: CGRect, to snapshot: ScreenSnapshot) async -> ScreenSnapshot {
        guard let path = snapshot.savedImagePath,
              let dataProvider = CGDataProvider(url: URL(fileURLWithPath: path) as CFURL),
              let fullImage = CGImage(
                pngDataProviderSource: dataProvider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent
              )
        else { return snapshot }

        // Convert normalised rect → pixel rect (flip Y: CGImage origin is top-left)
        let w = CGFloat(fullImage.width)
        let h = CGFloat(fullImage.height)
        let pixelRect = CGRect(
            x:       normalizedRect.minX * w,
            y:       normalizedRect.minY * h,
            width:   normalizedRect.width  * w,
            height:  normalizedRect.height * h
        )

        guard let cropped = fullImage.cropping(to: pixelRect) else { return snapshot }

        // Save cropped image — replaces the full-window capture as the task attachment
        let croppedPath = saveCapture(cropped, appName: snapshot.appName, windowTitle: snapshot.windowTitle)

        // OCR on cropped region only
        let croppedOCR = runOCR(on: cropped)
        Log.info(.camera, "ScreenVisionAnalyzer: cropped region OCR \(croppedOCR.count) chars")

        return ScreenSnapshot(
            capturedAt: snapshot.capturedAt,
            appName: snapshot.appName,
            windowTitle: snapshot.windowTitle,
            extractedText: snapshot.extractedText,
            croppedText: croppedOCR.isEmpty ? nil : croppedOCR,
            detectedURLs: snapshot.detectedURLs,
            hasDialog: snapshot.hasDialog,
            savedImagePath: croppedPath ?? snapshot.savedImagePath
        )
    }

    // MARK: - Vision: OCR only (background)

    private func runOCR(on image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return "" }

        let text = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !text.isEmpty {
            Log.info(.camera, "ScreenVisionAnalyzer: background OCR \(text.count) chars")
        }
        return text
    }

    // MARK: - Vision: Full suite (on-demand)

    /// Runs OCR + barcode detection + rectangle detection in one handler pass.
    private func runRichVision(on image: CGImage) -> (text: String, urls: [String], hasDialog: Bool) {
        let ocrReq = VNRecognizeTextRequest()
        ocrReq.recognitionLevel = .accurate
        ocrReq.usesLanguageCorrection = true

        let barcodeReq = VNDetectBarcodesRequest()

        let rectReq = VNDetectRectanglesRequest()
        rectReq.minimumAspectRatio = 0.2
        rectReq.maximumAspectRatio = 5.0
        rectReq.minimumSize = 0.15        // at least 15% of image dimension
        rectReq.minimumConfidence = 0.8

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([ocrReq, barcodeReq, rectReq])

        // OCR text
        let text = (ocrReq.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // URLs from barcodes / QR codes
        let urls: [String] = (barcodeReq.results ?? [])
            .compactMap { obs -> String? in
                guard let payload = obs.payloadStringValue else { return nil }
                return payload
            }

        // Dialog detection: look for a single large rectangle covering most of the image.
        // Modal dialogs typically show as one prominent rect.
        let hasDialog: Bool = {
            guard let rects = rectReq.results, !rects.isEmpty else { return false }
            // A dialog typically covers 15–70% of screen area
            return rects.contains { $0.confidence > 0.85 && $0.boundingBox.width < 0.9 }
        }()

        return (text, urls, hasDialog)
    }

    // MARK: - Screenshot Capture

    /// Captures the frontmost window image. Falls back to full screen if windowID is kCGNullWindowID.
    private static func captureWindow(windowID: CGWindowID) -> CGImage? {
        if windowID != kCGNullWindowID {
            // Capture just the target window at full resolution
            if let img = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                windowID,
                [.bestResolution, .boundsIgnoreFraming]
            ) {
                return img
            }
        }
        // Fallback: full screen
        let bounds = CGDisplayBounds(CGMainDisplayID())
        return CGWindowListCreateImage(bounds, .optionOnScreenOnly, kCGNullWindowID, .bestResolution)
    }

    // MARK: - Window Metadata

    private struct WindowInfo {
        let windowID: CGWindowID
        let title: String?
    }

    private static func frontmostWindowInfo(appPID: pid_t?) -> WindowInfo? {
        guard let pid = appPID else { return nil }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return nil }

        // Find first window belonging to the frontmost app
        for entry in list {
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid,
                  let windowID = entry[kCGWindowNumber as String] as? CGWindowID
            else { continue }

            let title = entry[kCGWindowName as String] as? String
            return WindowInfo(windowID: windowID, title: title)
        }
        return nil
    }

    // MARK: - Save to ContextCaptureStore

    /// Converts CGImage to PNG data, registers with ContextCaptureStore (auto-attaches to tasks).
    /// Returns the saved file path.
    @discardableResult
    private func saveCapture(_ image: CGImage, appName: String?, windowTitle: String?) -> String? {
        // Convert CGImage → PNG Data
        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(mutableData, "public.png" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        let pngData = mutableData as Data

        // Register via ContextCaptureStore — it handles the file write and tracking
        guard let capture = ContextCaptureStore.shared.registerImageData(
            pngData, type: .screenshot, sessionID: nil
        ) else { return nil }

        Log.info(.camera, "ScreenVisionAnalyzer: saved capture \(pngData.count / 1024)KB " +
                 "app='\(appName ?? "-")' window='\(windowTitle ?? "-")'")
        return capture.filePath
    }
}
