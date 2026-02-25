import AppKit
import SwiftUI

/// Floating glass toast panel, positioned below the pill.
final class ToastWindow: NSPanel {

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 36),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false
    }

    // TODO: Performance — creates a new NSHostingView on every log event.
    // Refactor to use CurrentValueSubject<LogEntry?, Never> so the hosting view
    // is created once and entry updates are pushed via binding.
    func setContent<V: View>(_ view: V) {
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
    }

    override var canBecomeKey: Bool  { false }
    override var canBecomeMain: Bool { false }
}
