import AppKit

final class GlobalHotkeyMonitor {
    static let shared = GlobalHotkeyMonitor()

    var onToggleMic:    (() -> Void)?  // ⌃Z — toggle mic on/off
    var onAmbientMode:  (() -> Void)?  // ⌃A — switch to Ambient, mic on
    var onSearchMode:   (() -> Void)?  // ⌃S — switch to AI Search, mic on
    var onTranscribeMode: (() -> Void)?  // ⌃X — switch to Transcribe, mic on

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
            case 6:   // Z
                self?.onToggleMic?()
            case 0:   // A
                self?.onAmbientMode?()
            case 1:   // S
                self?.onSearchMode?()
            case 7:   // X
                self?.onTranscribeMode?()
            default:
                break
            }
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler)
        localMonitor  = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handler(event)
            return event
        }
        Log.info(.system, "GlobalHotkeyMonitor started (⌃Z toggle mic, ⌃A ambient, ⌃S search, ⌃X transcribe)")
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor  { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor  = nil
    }
}
