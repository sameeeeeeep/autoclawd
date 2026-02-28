import AppKit
import SwiftUI

// MARK: - MainPanelWindow

final class MainPanelWindow: NSWindow {

    init(appState: AppState) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 580),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "AutoClawd"
        titlebarAppearsTransparent = false
        isReleasedWhenClosed = false
        minSize = NSSize(width: 500, height: 400)
        center()

        contentView = NSHostingView(rootView: MainPanelView(appState: appState))
    }
}
