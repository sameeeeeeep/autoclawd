import AppKit

final class GlobalHotkeyMonitor {
    static let shared = GlobalHotkeyMonitor()

    var onTranscribeNow: (() -> Void)?  // ⌃Space
    var onToggleMic: (() -> Void)?       // ⌃R

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private init() {}

    func start() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            let ctrl = event.modifierFlags.contains(.control)
            let noOtherMods = !event.modifierFlags.contains(.option) &&
                              !event.modifierFlags.contains(.command) &&
                              !event.modifierFlags.contains(.shift)
            guard ctrl && noOtherMods else { return }

            switch event.keyCode {
            case 49:  // Space
                self?.onTranscribeNow?()
            case 15:  // R
                self?.onToggleMic?()
            default:
                break
            }
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler)
        localMonitor  = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handler(event)
            return event
        }
        Log.info(.system, "GlobalHotkeyMonitor started (⌃Space, ⌃R)")
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor  { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor  = nil
    }
}
