import AppKit
import SwiftUI

/// Floating always-on-top brutalist pill window.
/// Draggable. Stays above all other apps.
final class PillWindow: NSPanel {

    private var hostingView: NSHostingView<AnyView>?
    private var lastMouseDown: NSPoint = .zero
    private var windowOriginOnDown: NSPoint = .zero

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 44),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        configure()
    }

    private func configure() {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false

        // Default position: top-right corner
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - 240
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

    // MARK: - Dragging

    override func mouseDown(with event: NSEvent) {
        lastMouseDown = event.locationInWindow
        windowOriginOnDown = frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        let delta = NSPoint(
            x: event.locationInWindow.x - lastMouseDown.x,
            y: event.locationInWindow.y - lastMouseDown.y
        )
        setFrameOrigin(NSPoint(
            x: windowOriginOnDown.x + delta.x,
            y: windowOriginOnDown.y + delta.y
        ))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
