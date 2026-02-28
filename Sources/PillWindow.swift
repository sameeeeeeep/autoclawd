import AppKit
import SwiftUI

/// Floating always-on-top glassmorphic pill window.
/// Smooth dragging via screen coordinates. Stays above all other apps.
final class PillWindow: NSPanel {

    private var hostingView: NSHostingView<AnyView>?

    // Smooth drag state — uses screen coordinates for jitter-free movement
    private var initialMouseScreenLocation: NSPoint = .zero
    private var initialWindowOrigin: NSPoint = .zero
    private var isDragging = false

    /// Called when the user right-clicks the pill. Return an NSMenu to show.
    var menuProvider: (() -> NSMenu)?

    static let pillWidth: CGFloat = 220
    static let pillHeight: CGFloat = 44

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.pillWidth, height: Self.pillHeight),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        configure()
    }

    private func configure() {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow

        // Default position: top-right corner
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - Self.pillWidth - 20
            let y = screen.visibleFrame.maxY - 60
            setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    func setContent<V: View>(_ view: V) {
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
        hostingView = hosting
    }

    // MARK: - Smooth Dragging (screen coordinates — no jitter)

    override func mouseDown(with event: NSEvent) {
        initialMouseScreenLocation = NSEvent.mouseLocation
        initialWindowOrigin = frame.origin
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        isDragging = true
        let current = NSEvent.mouseLocation
        let newOrigin = NSPoint(
            x: initialWindowOrigin.x + (current.x - initialMouseScreenLocation.x),
            y: initialWindowOrigin.y + (current.y - initialMouseScreenLocation.y)
        )
        setFrameOrigin(newOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            // Snap to screen edges if within 12pt
            snapToEdges()
        }
        isDragging = false
    }

    private func snapToEdges() {
        guard let screen = NSScreen.main else { return }
        let margin: CGFloat = 12
        let visible = screen.visibleFrame
        var origin = frame.origin

        // Snap left edge
        if abs(origin.x - visible.minX) < margin {
            origin.x = visible.minX
        }
        // Snap right edge
        if abs(origin.x + frame.width - visible.maxX) < margin {
            origin.x = visible.maxX - frame.width
        }
        // Snap top edge (macOS: higher y = higher on screen)
        if abs(origin.y + frame.height - visible.maxY) < margin {
            origin.y = visible.maxY - frame.height
        }
        // Snap bottom edge
        if abs(origin.y - visible.minY) < margin {
            origin.y = visible.minY
        }

        if origin != frame.origin {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().setFrameOrigin(origin)
            }
        }
    }

    // MARK: - Right-click context menu

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menuProvider?(), let view = contentView else {
            super.rightMouseDown(with: event)
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    // MARK: - Widget panel expansion

    /// Resize the window to accommodate a widget panel below the pill.
    /// Pass 0 to collapse. Keeps the top edge pinned so the pill stays in place.
    func setWidgetHeight(_ widgetHeight: CGFloat) {
        let totalH = Self.pillHeight + (widgetHeight > 0 ? 8 + widgetHeight : 0)
        guard abs(frame.height - totalH) > 1 else { return }
        let delta = totalH - frame.height
        var r = frame
        r.origin.y -= delta   // lower origin to keep top edge pinned
        r.size.height = totalH
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.allowsImplicitAnimation = true
            self.animator().setFrame(r, display: true)
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
