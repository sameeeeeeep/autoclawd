import AppKit
import Foundation

// MARK: - ScreenshotService

/// Captures screenshots of the main display or specific windows using CGWindowList APIs.
enum ScreenshotService {

    /// Capture the entire main display (all windows composited).
    static func captureMainDisplay() -> NSImage? {
        let displayID = CGMainDisplayID()
        guard let cgImage = CGDisplayCreateImage(displayID) else {
            Log.warn(.system, "ScreenshotService: failed to capture main display")
            return nil
        }
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        return NSImage(cgImage: cgImage, size: size)
    }

    /// Capture all on-screen windows composited (excludes desktop wallpaper).
    static func captureAllWindows() -> NSImage? {
        guard let cgImage = CGWindowListCreateImage(
            .null,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.boundsIgnoreFraming]
        ) else {
            Log.warn(.system, "ScreenshotService: failed to capture all windows")
            return nil
        }
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        return NSImage(cgImage: cgImage, size: size)
    }

    /// Capture a specific screen region.
    static func captureRegion(_ rect: CGRect) -> NSImage? {
        let displayID = CGMainDisplayID()
        guard let cgImage = CGDisplayCreateImage(displayID, rect: rect) else {
            Log.warn(.system, "ScreenshotService: failed to capture region \(rect)")
            return nil
        }
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        return NSImage(cgImage: cgImage, size: size)
    }

    /// Capture and downscale to keep data size reasonable for API transmission.
    /// Returns a PNG-encoded NSImage scaled to fit within maxDimension.
    static func captureAndResize(maxDimension: CGFloat = 1920) -> NSImage? {
        guard let original = captureMainDisplay() else { return nil }
        let origSize = original.size

        // If already within limits, return as-is
        if origSize.width <= maxDimension && origSize.height <= maxDimension {
            return original
        }

        // Calculate scaled size
        let scale = min(maxDimension / origSize.width, maxDimension / origSize.height)
        let newSize = NSSize(width: origSize.width * scale, height: origSize.height * scale)

        let resized = NSImage(size: newSize)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        original.draw(in: NSRect(origin: .zero, size: newSize))
        resized.unlockFocus()
        return resized
    }
}
