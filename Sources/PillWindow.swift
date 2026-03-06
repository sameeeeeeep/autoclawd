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

    /// Default widget width — icon mode uses 52 pt, everything else 240 pt.
    static let defaultWidth: CGFloat = 240

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0,
                                width: Self.defaultWidth,
                                height: WidgetCollapseLevel.full.height),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        configure()
    }

    private func configure() {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false          // SwiftUI liquidGlass applies its own shadow
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow

        // Default position: top-right corner
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - Self.defaultWidth - 20
            let y = screen.visibleFrame.maxY - WidgetCollapseLevel.full.height - 20
            setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    func setContent<V: View>(_ view: V) {
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        // Clear all default backgrounds so the SwiftUI layer is the only visual layer
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = CGColor.clear
        hosting.layer?.isOpaque = false
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

    // MARK: - Collapse-level resize

    /// Whether the camera feed is currently shown — adds extra height to the widget.
    var showsCameraFeed: Bool = false

    /// Animate the window frame to match a WidgetCollapseLevel.
    /// Top edge and right edge are pinned — the widget grows downward / inward.
    func setCollapseLevel(_ level: WidgetCollapseLevel) {
        let newW = level.width
        let newH = showsCameraFeed ? level.heightWithCamera : level.height
        guard abs(frame.width - newW) > 1 || abs(frame.height - newH) > 1 else { return }
        let deltaH = newH - frame.height
        let deltaW = newW - frame.width
        var r = frame
        r.origin.y -= deltaH    // keep top edge pinned
        r.origin.x -= deltaW    // keep right edge pinned
        r.size.width  = newW
        r.size.height = newH
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.36
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.allowsImplicitAnimation = true
            self.animator().setFrame(r, display: true)
        }
    }

    /// Set to true when the code co-pilot needs keyboard input.
    var needsKeyboardInput: Bool = false

    override var canBecomeKey: Bool { needsKeyboardInput }
    override var canBecomeMain: Bool { false }
}
