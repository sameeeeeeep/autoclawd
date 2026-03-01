import AppKit
import Foundation

// MARK: - ContextCapture

/// A captured piece of context (screenshot, clipboard image, URL) associated with a listening session.
struct ContextCapture: Identifiable {
    let id: String
    let timestamp: Date
    let sessionID: String?
    let type: CaptureType
    let filePath: String       // absolute path to saved file in ~/.autoclawd/captures/
    let preview: String        // human-readable description
    var attached: Bool = false  // true once bound to a pipeline task

    enum CaptureType: String {
        case screenshot       // user took a screenshot (Cmd+Shift+3/4/5)
        case clipboardImage   // image appeared on clipboard
        case url              // URL copied to clipboard
    }
}

// MARK: - ContextCaptureStore

/// Manages ambient context captures — screenshots/images/URLs that appear during listening sessions.
/// Saved to ~/.autoclawd/captures/ as files, indexed in memory.
///
/// Flow:
///   ClipboardMonitor detects image → saves to disk → registers here
///   PipelineOrchestrator processes transcript → queries recent unattached captures → attaches to task
final class ContextCaptureStore: @unchecked Sendable {
    static let shared = ContextCaptureStore()

    private var captures: [ContextCapture] = []
    private let lock = NSLock()
    private let maxCaptures = 200

    /// Directory for saved capture files.
    private let capturesDir: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".autoclawd/captures")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {}

    // MARK: - Registration

    /// Save an NSImage as a capture and register it.
    @discardableResult
    func registerImage(_ image: NSImage, type: ContextCapture.CaptureType, sessionID: String?) -> ContextCapture? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:])
        else {
            Log.warn(.clipboard, "ContextCaptureStore: failed to convert image to PNG")
            return nil
        }
        return registerImageData(pngData, type: type, sessionID: sessionID, mimeType: "image/png", ext: "png")
    }

    /// Save raw image data as a capture and register it.
    @discardableResult
    func registerImageData(
        _ data: Data, type: ContextCapture.CaptureType, sessionID: String?,
        mimeType: String = "image/png", ext: String = "png"
    ) -> ContextCapture? {
        let id = UUID().uuidString
        let filename = "\(timestampString())-\(id.prefix(8)).\(ext)"
        let fileURL = capturesDir.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL)
        } catch {
            Log.warn(.clipboard, "ContextCaptureStore: failed to write capture: \(error.localizedDescription)")
            return nil
        }

        let sizeKB = data.count / 1024
        let capture = ContextCapture(
            id: id,
            timestamp: Date(),
            sessionID: sessionID,
            type: type,
            filePath: fileURL.path,
            preview: "\(type.rawValue) (\(sizeKB)KB)"
        )

        lock.lock()
        captures.append(capture)
        if captures.count > maxCaptures {
            // Remove oldest attached captures first, then oldest unattached
            let attached = captures.filter(\.attached)
            if attached.count > maxCaptures / 2 {
                let toRemove = attached.prefix(attached.count - maxCaptures / 2)
                for cap in toRemove {
                    try? FileManager.default.removeItem(atPath: cap.filePath)
                }
                captures.removeAll { cap in toRemove.contains(where: { $0.id == cap.id }) }
            }
        }
        lock.unlock()

        Log.info(.clipboard, "ContextCaptureStore: registered \(type.rawValue) → \(filename) (\(sizeKB)KB)")
        return capture
    }

    /// Register a URL capture.
    @discardableResult
    func registerURL(_ urlString: String, sessionID: String?) -> ContextCapture? {
        let id = UUID().uuidString
        let capture = ContextCapture(
            id: id,
            timestamp: Date(),
            sessionID: sessionID,
            type: .url,
            filePath: "",  // no file for URLs
            preview: String(urlString.prefix(100))
        )

        lock.lock()
        captures.append(capture)
        lock.unlock()

        Log.info(.clipboard, "ContextCaptureStore: registered URL → \(urlString.prefix(60))")
        return capture
    }

    // MARK: - Querying

    /// Get all unattached captures from a given session, or within a time window.
    func recentUnattached(sessionID: String?, since: Date? = nil) -> [ContextCapture] {
        lock.lock()
        defer { lock.unlock() }

        let cutoff = since ?? Date().addingTimeInterval(-120)  // default: last 2 minutes
        return captures.filter { cap in
            !cap.attached
                && cap.timestamp >= cutoff
                && (sessionID == nil || cap.sessionID == sessionID || cap.sessionID == nil)
        }
    }

    /// Mark captures as attached (bound to a task).
    func markAttached(ids: [String]) {
        lock.lock()
        for i in captures.indices {
            if ids.contains(captures[i].id) {
                captures[i].attached = true
            }
        }
        lock.unlock()
    }

    /// Load an Attachment from a capture file path.
    static func loadAttachment(path: String) -> Attachment? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return Attachment.fromFile(url: url)
    }

    // MARK: - Cleanup

    /// Purge capture files older than the given number of days.
    func purgeOldCaptures(retentionDays: Int = 7) {
        let cutoff = Date().addingTimeInterval(-Double(retentionDays * 86400))
        lock.lock()
        let old = captures.filter { $0.timestamp < cutoff }
        captures.removeAll { $0.timestamp < cutoff }
        lock.unlock()

        for cap in old where !cap.filePath.isEmpty {
            try? FileManager.default.removeItem(atPath: cap.filePath)
        }
        if !old.isEmpty {
            Log.info(.clipboard, "ContextCaptureStore: purged \(old.count) old captures")
        }
    }

    // MARK: - Helpers

    private func timestampString() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        return df.string(from: Date())
    }
}
