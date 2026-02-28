import AppKit
import SwiftUI

// MARK: - Appearance Wrapper
// Reads @AppStorage so the color scheme re-applies whenever the setting changes.
private struct AppearanceWrapper: View {
    @AppStorage("color_scheme_setting") private var schemeSetting: String = "system"
    let appState: AppState

    private var preferredScheme: ColorScheme? {
        switch ColorSchemeSetting(rawValue: schemeSetting) ?? .system {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var body: some View {
        MainPanelView(appState: appState)
            .preferredColorScheme(preferredScheme)
    }
}

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

        contentView = NSHostingView(rootView: AppearanceWrapper(appState: appState))
    }
}
