import AppKit
import SwiftUI

// MARK: - Learn Mode Monitor Window
//
// A small floating NSPanel positioned in the top-right corner that shows
// the live CanvasNode list while Learn Mode is active.
//
// Wired by AppDelegate (Task 9): created when learnModeService.isActive fires,
// closed when the session stops or the user closes the window.

final class LearnModeMonitorWindow: NSPanel {

    private let service: LearnModeService

    init(service: LearnModeService) {
        self.service = service
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 420),
            styleMask: [
                .titled,
                .closable,
                .resizable,
                .nonactivatingPanel,
                .fullSizeContentView
            ],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        delegate = self

        let view = LearnModeMonitorView(service: service)
        contentView = NSHostingView(rootView: view)

        positionTopRight()
    }

    // MARK: - Positioning

    private func positionTopRight() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let windowWidth: CGFloat = 320
        let windowHeight: CGFloat = 420
        let x = screenFrame.maxX - windowWidth - 16
        let y = screenFrame.maxY - windowHeight - 80  // below toast zone
        setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: false)
    }
}

// MARK: - NSWindowDelegate

extension LearnModeMonitorWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            service.stopSession()
        }
    }
}
