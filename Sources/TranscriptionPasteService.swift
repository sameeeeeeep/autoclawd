import AppKit
import CoreGraphics
import Foundation

// MARK: - TranscriptionPasteService

/// Pastes text into the currently focused application.
/// Uses CGEventPost (Cmd+V simulation) if Accessibility is granted.
/// Falls back to clipboard-only if not.
final class TranscriptionPasteService: @unchecked Sendable {

    var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Copy text to clipboard, then simulate Cmd+V if Accessibility is granted.
    func paste(text: String) {
        // Always write to clipboard
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        guard isAccessibilityGranted else {
            Log.info(.paste, "Accessibility not granted — copied \(text.count) chars to clipboard")
            return
        }

        // Small delay so clipboard write is visible to the target app
        Thread.sleep(forTimeInterval: 0.05)

        // Simulate Cmd+V
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9  // 'v'

        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)

        Log.info(.paste, "Pasted \(text.count) chars via CGEventPost (Cmd+V)")
    }
}
