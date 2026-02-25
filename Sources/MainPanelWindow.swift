import AppKit
import SwiftUI

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
        minSize = NSSize(width: 700, height: 480)
        center()

        let panel = MainPanelView(appState: appState)
        contentView = NSHostingView(rootView: panel)
    }
}
