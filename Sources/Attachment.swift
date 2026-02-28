import AppKit
import Foundation
import UniformTypeIdentifiers

// MARK: - Attachment

/// Represents a file/image/document attachment that can be sent to Claude Code sessions.
struct Attachment: Identifiable {
    let id = UUID()
    let type: AttachmentType
    let fileName: String
    let data: Data
    let mimeType: String

    enum AttachmentType: String {
        case image
        case document
        case screenshot
    }

    /// Human-readable size string.
    var sizeLabel: String {
        let bytes = data.count
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    /// SF Symbol icon name for the attachment type.
    var iconName: String {
        switch type {
        case .screenshot: return "camera.viewfinder"
        case .image: return "photo"
        case .document: return "doc.text"
        }
    }

    /// Thumbnail for preview (images/screenshots only).
    var thumbnail: NSImage? {
        guard type == .image || type == .screenshot else { return nil }
        return NSImage(data: data)
    }

    /// Build Anthropic API content block for this attachment.
    func toContentBlock() -> [String: Any]? {
        let base64 = data.base64EncodedString()

        switch type {
        case .image, .screenshot:
            return [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": mimeType,
                    "data": base64,
                ] as [String: Any],
            ]

        case .document:
            // PDFs can be sent as document content blocks
            if mimeType == "application/pdf" {
                return [
                    "type": "document",
                    "source": [
                        "type": "base64",
                        "media_type": mimeType,
                        "data": base64,
                    ] as [String: Any],
                ]
            }
            // Text-based documents: send as text content
            if let text = String(data: data, encoding: .utf8) {
                return [
                    "type": "text",
                    "text": "--- \(fileName) ---\n\(text)\n--- end \(fileName) ---",
                ]
            }
            return nil
        }
    }

    // MARK: - Factory Methods

    /// Create an attachment from a file URL.
    static func fromFile(url: URL) -> Attachment? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let ext = url.pathExtension.lowercased()
        let fileName = url.lastPathComponent
        let mimeType = Self.mimeType(for: ext)
        let type = Self.attachmentType(for: ext)
        return Attachment(type: type, fileName: fileName, data: data, mimeType: mimeType)
    }

    /// Create an attachment from pasteboard image data.
    static func fromPasteboardImage() -> Attachment? {
        let pb = NSPasteboard.general
        // Try PNG first, then TIFF
        if let data = pb.data(forType: .png) {
            return Attachment(type: .image, fileName: "pasted-image.png", data: data, mimeType: "image/png")
        }
        if let data = pb.data(forType: .tiff),
           let bitmapRep = NSBitmapImageRep(data: data),
           let pngData = bitmapRep.representation(using: .png, properties: [:])
        {
            return Attachment(type: .image, fileName: "pasted-image.png", data: pngData, mimeType: "image/png")
        }
        return nil
    }

    /// Create an attachment from a screenshot (NSImage).
    static func fromScreenshot(_ image: NSImage) -> Attachment? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:])
        else { return nil }
        return Attachment(
            type: .screenshot,
            fileName: "screenshot-\(Self.timestampString()).png",
            data: pngData,
            mimeType: "image/png"
        )
    }

    // MARK: - Helpers

    private static func mimeType(for ext: String) -> String {
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "pdf": return "application/pdf"
        case "md", "markdown": return "text/markdown"
        case "txt": return "text/plain"
        case "json": return "application/json"
        case "swift": return "text/x-swift"
        case "py": return "text/x-python"
        case "js": return "text/javascript"
        case "ts": return "text/typescript"
        case "html": return "text/html"
        case "css": return "text/css"
        case "yaml", "yml": return "text/yaml"
        case "xml": return "text/xml"
        case "csv": return "text/csv"
        default: return "application/octet-stream"
        }
    }

    private static func attachmentType(for ext: String) -> AttachmentType {
        switch ext {
        case "png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "tif":
            return .image
        default:
            return .document
        }
    }

    /// Supported file extensions for the file picker.
    static var supportedExtensions: [String] {
        [
            "png", "jpg", "jpeg", "gif", "webp",
            "pdf", "md", "txt", "json",
            "swift", "py", "js", "ts", "html", "css",
            "yaml", "yml", "xml", "csv",
        ]
    }

    /// UTTypes for the file picker.
    static var supportedUTTypes: [UTType] {
        var types: [UTType] = [
            .png, .jpeg, .gif, .pdf,
            .plainText, .json, .html, .xml,
            .commaSeparatedText, .swiftSource,
        ]
        if let webp = UTType("org.webmproject.webp") { types.append(webp) }
        if let md = UTType("public.markdown") { types.append(md) }
        if let yaml = UTType("public.yaml") { types.append(yaml) }
        if let py = UTType("public.python-script") { types.append(py) }
        if let js = UTType("com.netscape.javascript-source") { types.append(js) }
        return types
    }

    private static func timestampString() -> String {
        let df = DateFormatter()
        df.dateFormat = "HHmmss"
        return df.string(from: Date())
    }
}
