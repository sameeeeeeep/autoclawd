import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Vision

// MARK: - Result Types

/// Full screen or region capture result.
struct ScreenGrab {
    let ocrText: String
    let metadata: String         // app name, window title, etc.
    let imageJPEGData: Data?     // nil if capture failed
    let capturedAt: Date
}

/// Selected text + context screenshot.
struct SelectionGrab {
    let selectedText: String
    let contextImageJPEGData: Data?
    let capturedAt: Date
}

// MARK: - ScreenGrabService

/// On-demand screen / cursor / selection capture for Call Mode MCP tools.
///
/// - `captureScreen(region:)` — full screen or cropped region, Vision OCR + JPEG
/// - `captureCursorContext()` — 600×400 crop around current cursor, OCR + AX element info
/// - `captureSelection()` — AX selected text + screenshot of selection bounds
///
/// Wraps `ScreenVisionAnalyzer` for full-screen grabs; adds cursor and AX selection on top.
/// Thread-safe: all async methods dispatch to the right actor internally.
final class ScreenGrabService: @unchecked Sendable {

    private let visionAnalyzer = ScreenVisionAnalyzer()

    // MARK: - Full Screen / Region

    /// Capture the full screen (or a specific pixel region) with Vision OCR and a JPEG screenshot.
    func captureScreen(region: CGRect? = nil) async -> ScreenGrab {
        guard let snapshot = await visionAnalyzer.captureNow() else {
            return ScreenGrab(ocrText: "", metadata: "Screen capture unavailable",
                              imageJPEGData: nil, capturedAt: Date())
        }

        let finalSnapshot: ScreenSnapshot
        if let region {
            let screen = await MainActor.run { NSScreen.main?.frame ?? .zero }
            guard screen.width > 0, screen.height > 0 else {
                return makeGrab(from: snapshot)
            }
            let normalized = CGRect(
                x: region.minX / screen.width,
                y: region.minY / screen.height,
                width: region.width / screen.width,
                height: region.height / screen.height
            )
            finalSnapshot = await visionAnalyzer.applySelection(normalizedRect: normalized, to: snapshot)
        } else {
            finalSnapshot = snapshot
        }

        return makeGrab(from: finalSnapshot)
    }

    private func makeGrab(from snapshot: ScreenSnapshot) -> ScreenGrab {
        let imageData = snapshot.savedImagePath.flatMap { path -> Data? in
            guard let png = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
            return jpegFromPNG(png)
        }
        let parts = [
            snapshot.appName.map    { "App: \($0)" },
            snapshot.windowTitle.map { "Window: \($0)" },
            snapshot.hasDialog ? "Modal/dialog visible" : nil
        ].compactMap { $0 }

        return ScreenGrab(
            ocrText: snapshot.croppedText ?? snapshot.extractedText,
            metadata: parts.joined(separator: " | "),
            imageJPEGData: imageData,
            capturedAt: snapshot.capturedAt
        )
    }

    // MARK: - Cursor Context

    /// Capture a 600×400 screenshot centred on the current cursor with OCR and AX element info.
    /// Use this when the user points at something without saying explicitly what it is.
    func captureCursorContext() async -> ScreenGrab {
        let (mouseLocation, screenHeight) = await MainActor.run {
            (NSEvent.mouseLocation, NSScreen.main?.frame.height ?? 900.0)
        }

        // AppKit uses bottom-left origin; CGWindowListCreateImage uses top-left.
        let cgX = mouseLocation.x
        let cgY = screenHeight - mouseLocation.y

        let grabW: CGFloat = 600
        let grabH: CGFloat = 400
        let region = CGRect(
            x: max(0, cgX - grabW / 2),
            y: max(0, cgY - grabH / 2),
            width: grabW,
            height: grabH
        )

        guard let cgImage = CGWindowListCreateImage(
            region, .optionOnScreenOnly, kCGNullWindowID, .bestResolution
        ) else {
            return ScreenGrab(ocrText: "", metadata: "Cursor capture failed",
                              imageJPEGData: nil, capturedAt: Date())
        }

        let ocrText   = runOCR(on: cgImage)
        let imageData = jpegFromCGImage(cgImage)
        let elemInfo  = axElementInfo(at: mouseLocation, screenHeight: screenHeight)

        let metadata = "Cursor at (\(Int(mouseLocation.x)), \(Int(mouseLocation.y)))" +
                       (elemInfo.isEmpty ? "" : " | \(elemInfo)")

        return ScreenGrab(ocrText: ocrText, metadata: metadata,
                          imageJPEGData: imageData, capturedAt: Date())
    }

    // MARK: - Selection

    /// Get the user's currently highlighted text and a screenshot of the selection bounds.
    /// Use this when the user selects code, an error, or any text.
    func captureSelection() async -> SelectionGrab {
        let (text, bounds) = await MainActor.run { axSelectedTextAndBounds() }
        let screenHeight   = await MainActor.run { NSScreen.main?.frame.height ?? 900.0 }

        var imageData: Data?
        if let b = bounds, b.width > 0, b.height > 0 {
            // AX bounds use top-left origin on macOS (screen-space, not AppKit-space).
            // Add padding around the selection.
            let padded = CGRect(
                x: b.minX - 24,
                y: b.minY - 12,
                width: b.width + 48,
                height: b.height + 24
            )
            // CGWindowListCreateImage also uses top-left origin, so no flip needed here.
            if let img = CGWindowListCreateImage(
                padded, .optionOnScreenOnly, kCGNullWindowID, .bestResolution
            ) {
                imageData = jpegFromCGImage(img)
            }
        }

        return SelectionGrab(
            selectedText: text ?? "",
            contextImageJPEGData: imageData,
            capturedAt: Date()
        )
    }

    // MARK: - Accessibility Helpers

    /// Returns (selectedText, selectionBounds) for the focused UI element.
    /// AX bounds are in screen-space top-left coordinates (same as CGWindow).
    private func axSelectedTextAndBounds() -> (String?, CGRect?) {
        let systemWide = AXUIElementCreateSystemWide()

        // Focused element
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef
        ) == .success, let focused = focusedRef,
              CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return (nil, nil) }

        let element = focused as! AXUIElement  // safe: type ID verified above

        // Selected text
        var textRef: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &textRef)
        let text = textRef as? String

        // Selected text range
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeRef
        ) == .success, let rangeVal = rangeRef else { return (text, nil) }

        // Bounding rect for that range
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeVal,
            &boundsRef
        ) == .success, let bVal = boundsRef,
              CFGetTypeID(bVal) == AXValueGetTypeID()
        else { return (text, nil) }

        var rect = CGRect.zero
        AXValueGetValue(bVal as! AXValue, .cgRect, &rect)  // safe: type ID verified
        return (text, rect.width > 0 ? rect : nil)
    }

    /// Description of the UI element under the cursor (role + title).
    private func axElementInfo(at point: NSPoint, screenHeight: CGFloat) -> String {
        let systemWide = AXUIElementCreateSystemWide()
        var elementRef: AXUIElement?
        // AX position uses top-left origin → flip AppKit Y
        let axY = Float(screenHeight - point.y)
        guard AXUIElementCopyElementAtPosition(
            systemWide, Float(point.x), axY, &elementRef
        ) == .success, let element = elementRef else { return "" }

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = (roleRef as? String) ?? ""

        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        let title = (titleRef as? String) ?? ""

        return [role, title].filter { !$0.isEmpty }.joined(separator: ": ")
    }

    // MARK: - Vision OCR

    private func runOCR(on image: CGImage) -> String {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([req])
        return (req.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Image Conversion

    private func jpegFromPNG(_ pngData: Data) -> Data? {
        guard let rep = NSBitmapImageRep(data: pngData) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }

    private func jpegFromCGImage(_ cgImage: CGImage) -> Data? {
        let nsImage = NSImage(cgImage: cgImage, size: .zero)
        guard let tiff = nsImage.tiffRepresentation,
              let rep  = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }
}
