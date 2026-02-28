import AppKit
import SwiftUI

/// Observable model that drives the toast view without recreating the hosting view.
final class ToastModel: ObservableObject {
    @Published var entry: LogEntry
    init(_ entry: LogEntry) { self.entry = entry }
}

/// Thin SwiftUI wrapper that re-renders ToastView whenever the model changes.
private struct ToastModelView: View {
    @ObservedObject var model: ToastModel
    var body: some View { ToastView(entry: model.entry) }
}

/// Floating glass toast panel, positioned below the pill.
final class ToastWindow: NSPanel {

    private var model: ToastModel?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 40),
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

    /// Update the displayed log entry. Creates the hosting view on first call;
    /// subsequent calls push the new entry through the @Published binding so
    /// SwiftUI re-renders without replacing the NSHostingView.
    func updateEntry(_ entry: LogEntry) {
        if let model = model {
            model.entry = entry
        } else {
            let m = ToastModel(entry)
            self.model = m
            let hosting = NSHostingView(rootView: ToastModelView(model: m))
            hosting.frame = contentView?.bounds ?? .zero
            hosting.autoresizingMask = [.width, .height]
            contentView = hosting
        }
    }

    override var canBecomeKey: Bool  { false }
    override var canBecomeMain: Bool { false }
}
