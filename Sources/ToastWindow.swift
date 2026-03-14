import AppKit
import SwiftUI

/// Observable model for the capability suggestion toast.
final class CapabilityToastModel: ObservableObject {
    @Published var item: SuggestionItem?
    var onTap: () -> Void = {}
    var onSnooze: () -> Void = {}
    var onMarkIrrelevant: () -> Void = {}
}

/// SwiftUI wrapper that renders the capability toast.
private struct CapabilityToastModelView: View {
    @ObservedObject var model: CapabilityToastModel

    var body: some View {
        if let i = model.item {
            CapabilityToastView(
                item: i,
                onTap: model.onTap,
                onSnooze: model.onSnooze,
                onMarkIrrelevant: model.onMarkIrrelevant
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}

/// Floating glass toast panel for capability suggestions.
/// Positioned in the top-right corner of the screen, notification-style.
final class ToastWindow: NSPanel {

    private let capModel = CapabilityToastModel()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 110),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false

        let hosting = NSHostingView(rootView: CapabilityToastModelView(model: capModel))
        hosting.frame = contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
    }

    /// Show a suggestion toast in the top-right corner.
    func show(_ item: SuggestionItem, onTap: @escaping () -> Void, onSnooze: @escaping () -> Void, onMarkIrrelevant: @escaping () -> Void) {
        capModel.item = item
        capModel.onTap = onTap
        capModel.onSnooze = onSnooze
        capModel.onMarkIrrelevant = onMarkIrrelevant
        positionTopRight()
        orderFront(nil)
    }

    /// Hide the toast.
    func dismiss() {
        capModel.item = nil
        orderOut(nil)
    }

    private func positionTopRight() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let x = visibleFrame.maxX - 300 - 16
        let y = visibleFrame.maxY - 110 - 16
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    override var canBecomeKey: Bool  { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Legacy Support

/// Observable model that drives the legacy log toast view.
final class ToastModel: ObservableObject {
    @Published var entry: LogEntry
    init(_ entry: LogEntry) { self.entry = entry }
}

/// Legacy method extension for updating with log entries (used by pill log lines).
extension ToastWindow {
    func updateEntry(_ entry: LogEntry) {
        // Legacy toast display — no-op since toast is now used for capability suggestions
    }
}
