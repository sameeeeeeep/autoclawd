import SwiftUI

@main
struct AutoClawdApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No default window — the pill is our main UI
        Settings {
            EmptyView()
        }
    }
}
