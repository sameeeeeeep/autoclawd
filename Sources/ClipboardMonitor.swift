import AppKit
import Foundation

// MARK: - ClipboardEntry

struct ClipboardEntry {
    let timestamp: Date
    let type: String  // "text", "image", "url", "other"
    let preview: String
    let charCount: Int
}

// MARK: - ClipboardMonitor

/// Polls NSPasteboard every 2 seconds for new content.
/// Stores entries in memory; persisted to SQLite in Phase 2.
/// When an image is detected, saves it to disk via ContextCaptureStore for pipeline consumption.
final class ClipboardMonitor: @unchecked Sendable {
    static let shared = ClipboardMonitor()

    private var timer: Timer?
    private var lastChangeCount: Int = -1
    private(set) var entries: [ClipboardEntry] = []
    private let maxEntries = 500
    private let queue = DispatchQueue(label: "com.autoclawd.clipboard", qos: .utility)

    /// The current listening session ID (set by ChunkManager when listening starts).
    var currentSessionID: String?

    private init() {}

    func start() {
        DispatchQueue.main.async { [weak self] in
            self?.timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.poll()
            }
        }
        Log.info(.clipboard, "ClipboardMonitor started (polling every 2s)")
    }

    func stop() {
        DispatchQueue.main.async { [weak self] in
            self?.timer?.invalidate()
            self?.timer = nil
        }
        Log.info(.clipboard, "ClipboardMonitor stopped")
    }

    // MARK: - Private

    private func poll() {
        let pb = NSPasteboard.general
        let changeCount = pb.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        queue.async { [weak self] in
            self?.capture(pasteboard: pb)
        }
    }

    private func capture(pasteboard: NSPasteboard) {
        let (type, preview, charCount) = classify(pasteboard: pasteboard)
        let entry = ClipboardEntry(
            timestamp: Date(),
            type: type,
            preview: preview,
            charCount: charCount
        )

        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }

        // Save clipboard images to disk for pipeline context capture
        if type == "image" {
            saveClipboardImage(pasteboard: pasteboard)
        } else if type == "url" {
            if let urlString = pasteboard.string(forType: .URL) {
                ContextCaptureStore.shared.registerURL(urlString, sessionID: currentSessionID)
            }
        }

        Log.info(.clipboard, "\(type) copied: \(charCount) chars — '\(preview)'")
    }

    /// Save clipboard image data to disk via ContextCaptureStore.
    private func saveClipboardImage(pasteboard: NSPasteboard) {
        let sessionID = currentSessionID
        if let pngData = pasteboard.data(forType: .png) {
            ContextCaptureStore.shared.registerImageData(
                pngData, type: .clipboardImage, sessionID: sessionID,
                mimeType: "image/png", ext: "png"
            )
        } else if let tiffData = pasteboard.data(forType: .tiff),
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            ContextCaptureStore.shared.registerImageData(
                pngData, type: .clipboardImage, sessionID: sessionID,
                mimeType: "image/png", ext: "png"
            )
        }
    }

    private func classify(pasteboard: NSPasteboard) -> (type: String, preview: String, charCount: Int) {
        // Check for images first — screenshots (Cmd+Shift+3/4) go to clipboard as images
        if pasteboard.data(forType: .png) != nil || pasteboard.data(forType: .tiff) != nil {
            return ("image", "[image data]", 0)
        }
        if let string = pasteboard.string(forType: .string) {
            let preview = String(string.prefix(60)).replacingOccurrences(of: "\n", with: " ")
            return ("text", preview, string.count)
        }
        if let urlString = pasteboard.string(forType: .URL) {
            return ("url", String(urlString.prefix(60)), urlString.count)
        }
        return ("other", "[unknown type]", 0)
    }
}
