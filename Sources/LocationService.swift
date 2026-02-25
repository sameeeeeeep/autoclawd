import CoreWLAN
import Foundation

@MainActor
final class LocationService: ObservableObject {
    static let shared = LocationService()

    @Published private(set) var currentSSID: String?
    @Published private(set) var currentPlaceName: String?

    /// Called when an unrecognised SSID is first seen. Arg = raw SSID.
    var onUnknownSSID: ((String) -> Void)?

    private let store = SessionStore.shared
    private var pollTimer: Timer?
    private var knownSSIDs: Set<String> = []

    private init() {}

    func start() {
        pollOnce()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollOnce() }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func labelCurrentSSID(_ name: String) {
        guard let ssid = currentSSID else { return }
        store.createPlace(wifiSSID: ssid, name: name)
        currentPlaceName = name
        knownSSIDs.insert(ssid)
        Log.info(.system, "Labeled '\(ssid)' as '\(name)'")
    }

    // MARK: - Private

    private func pollOnce() {
        let ssid = CWWiFiClient.shared().interface()?.ssid()
        let resolved = ssid ?? "Mobile"   // nil = no WiFi = on hotspot or offline

        guard resolved != currentSSID else { return }
        currentSSID = resolved

        if let place = store.findPlace(wifiSSID: resolved) {
            currentPlaceName = place.name
        } else if resolved == "Mobile" || resolved.lowercased().contains("iphone") {
            // Auto-label hotspot
            store.createPlace(wifiSSID: resolved, name: "Mobile")
            currentPlaceName = "Mobile"
        } else if !knownSSIDs.contains(resolved) {
            knownSSIDs.insert(resolved)
            onUnknownSSID?(resolved)   // prompt user
        }
    }
}
