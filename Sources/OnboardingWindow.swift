import AppKit
import SwiftUI

// MARK: - OnboardingWindow

/// NSWindow wrapper for the liquid glass onboarding flow.
/// Shown on first launch before the dependency setup screen.
final class OnboardingWindow: NSWindow {
    init(onComplete: @escaping () -> Void) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "Welcome to AutoClawd"
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isReleasedWhenClosed = false
        backgroundColor = NSColor(red: 0.03, green: 0.04, blue: 0.08, alpha: 1)

        // Prevent resize — fixed frame for onboarding
        minSize = NSSize(width: 700, height: 600)
        maxSize = NSSize(width: 700, height: 600)

        let view = OnboardingView(onComplete: onComplete)
        contentViewController = NSHostingController(rootView: view)
        center()
    }
}
