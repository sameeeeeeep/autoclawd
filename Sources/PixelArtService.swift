import AppKit

// MARK: - PixelArtService
//
// Converts any NSImage to pixel art by:
//   1. Drawing the source image at a tiny size (1/blockSize resolution)
//   2. Drawing each pixel back as a blockSize×blockSize square (nearest-neighbor)
//
// This is the Swift equivalent of the HTML canvas technique at
// https://dev.to/gustavosfq/convert-an-image-to-html-pixel-by-pixel-3m1n
//
// Usage:
//   let pixelated = PixelArtService.pixelate(image, blockSize: 6)
//   let avatar    = PixelArtService.pixelate(AppIcon.forProject("AutoClawd"), blockSize: 4)

enum PixelArtService {

    // MARK: - Pixelate

    /// Converts an NSImage to pixel art at the same display size.
    /// - Parameters:
    ///   - image: Source image (any size).
    ///   - blockSize: Width/height of each rendered pixel block in points. Default 6.
    /// - Returns: Pixelated NSImage at the same size as the input.
    static func pixelate(_ image: NSImage, blockSize: Int = 6) -> NSImage {
        let size = image.size
        guard size.width > 0, size.height > 0, blockSize > 1 else { return image }

        let smallW = max(1, Int(size.width)  / blockSize)
        let smallH = max(1, Int(size.height) / blockSize)

        // Step 1 — draw at tiny resolution to sample pixel colors
        guard let small = downsample(image, to: CGSize(width: smallW, height: smallH)) else {
            return image
        }

        // Step 2 — draw each tiny pixel back as a blockSize square
        let output = NSImage(size: size)
        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none

        for row in 0..<smallH {
            for col in 0..<smallW {
                let color = small.sampleColor(atX: col, y: row)
                color.setFill()
                let rect = CGRect(
                    x: CGFloat(col * blockSize),
                    y: CGFloat(row * blockSize),
                    width:  CGFloat(blockSize),
                    height: CGFloat(blockSize)
                )
                NSBezierPath(rect: rect).fill()
            }
        }

        output.unlockFocus()
        return output
    }

    // MARK: - App Icon Loader

    /// Attempts to load the icon for a macOS app whose source is at `projectPath`.
    /// Falls back to nil if no icon is found.
    static func appIcon(forProjectPath path: String) -> NSImage? {
        let expanded = (path as NSString).expandingTildeInPath
        let fm = FileManager.default

        // Look for a .app bundle at or below the project path (max 2 levels deep)
        let candidates = [
            expanded,
            (expanded as NSString).appendingPathComponent(".."),
        ]

        for base in candidates {
            guard let contents = try? fm.contentsOfDirectory(atPath: base) else { continue }
            for entry in contents where entry.hasSuffix(".app") {
                let appPath = (base as NSString).appendingPathComponent(entry)
                if let icon = NSWorkspace.shared.icon(forFile: appPath) as NSImage? {
                    return icon
                }
            }
        }
        return nil
    }

    // MARK: - Private helpers

    private static func downsample(_ image: NSImage, to size: CGSize) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .none
        image.draw(in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()

        return rep
    }
}

// MARK: - NSBitmapImageRep color sampling

private extension NSBitmapImageRep {
    /// Sample a pixel color using top-left origin (flips NSBitmapImageRep's bottom-left origin).
    func sampleColor(atX x: Int, y: Int) -> NSColor {
        let flippedY = pixelsHigh - 1 - y
        return colorAt(x: x, y: flippedY) ?? .clear
    }
}
