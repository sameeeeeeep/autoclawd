import AppKit
import SwiftUI

// MARK: - CallStreamWidget

/// Always-on-top floating widget that shows the live call stream — agent tiles,
/// camera feed, and conversation feed. Separate from the main pill so it can
/// overlay any screen or app during a Claude Code session.
///
/// Activated when pillMode == .callMode and the setting is enabled.
/// Draggable from anywhere; snaps to the bottom-right corner by default.
final class CallStreamWidget: NSPanel {

    static let defaultWidth:  CGFloat = 420
    static let defaultHeight: CGFloat = 560

    private var hostingView: NSHostingView<AnyView>?

    // Smooth drag
    private var initialMouseLoc: NSPoint = .zero
    private var initialOrigin:   NSPoint = .zero

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0,
                                width: Self.defaultWidth,
                                height: Self.defaultHeight),
            styleMask:  [.borderless, .nonactivatingPanel, .utilityWindow],
            backing:    .buffered,
            defer:      false
        )
        configure()
    }

    private func configure() {
        isOpaque               = false
        backgroundColor        = .clear
        hasShadow              = true
        level                  = .floating
        collectionBehavior     = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false
        animationBehavior      = .utilityWindow

        // Default position: bottom-right, 20pt inset from visible frame
        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            let x  = vf.maxX - Self.defaultWidth  - 20
            let y  = vf.minY + 20
            setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    func setContent<V: View>(_ view: V) {
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = contentView?.bounds ?? .zero
        hosting.autoresizingMask   = [.width, .height]
        hosting.wantsLayer         = true
        hosting.layer?.backgroundColor = CGColor.clear
        hosting.layer?.isOpaque    = false
        contentView  = hosting
        hostingView  = hosting
    }

    // MARK: - Dragging

    override func mouseDown(with event: NSEvent) {
        initialMouseLoc = NSEvent.mouseLocation
        initialOrigin   = frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        let cur = NSEvent.mouseLocation
        setFrameOrigin(NSPoint(
            x: initialOrigin.x + (cur.x - initialMouseLoc.x),
            y: initialOrigin.y + (cur.y - initialMouseLoc.y)
        ))
    }

    // MARK: - Visibility

    func show() {
        orderFront(nil)
    }

    func hide() {
        orderOut(nil)
    }

    /// Animate in from bottom (slide + fade).
    func animateIn() {
        alphaValue  = 0
        let target  = frame
        var start   = target
        start.origin.y -= 24
        setFrame(start, display: false)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(target, display: true)
            animator().alphaValue = 1
        }
        orderFront(nil)
    }

    /// Animate out (slide + fade).
    func animateOut(completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            var end = frame; end.origin.y -= 24
            animator().setFrame(end, display: true)
            animator().alphaValue = 0
        } completionHandler: {
            self.orderOut(nil)
            completion?()
        }
    }
}
