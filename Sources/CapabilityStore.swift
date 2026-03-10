import Foundation

// MARK: - CapabilityStore
//
// Persists capabilities built by FUCBC to:
//   ~/.autoclawd/capabilities/index.json
//
// Retrieval is instant and offline — scoring-based suggest() lets AppState
// check all capabilities against the current screen context every 10 seconds
// for auto-trigger detection.

final class CapabilityStore: @unchecked Sendable {

    static let shared = CapabilityStore()
    private init() { load() }

    private let queue = DispatchQueue(label: "com.autoclawd.capability-store", qos: .utility)
    private var capabilities: [Capability] = []

    // MARK: - Persistence

    private var indexURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".autoclawd/capabilities/index.json")
    }

    private func load() {
        queue.async { [weak self] in
            guard let self else { return }
            guard let data = try? Data(contentsOf: self.indexURL),
                  let decoded = try? JSONDecoder().decode([Capability].self, from: data)
            else { return }
            self.capabilities = decoded
            Log.info(.system, "CapabilityStore: loaded \(decoded.count) capability(ies)")
        }
    }

    /// Save (or update) a capability. Deduplicates by id.
    func save(_ capability: Capability) {
        queue.async { [weak self] in
            guard let self else { return }
            if let idx = self.capabilities.firstIndex(where: { $0.id == capability.id }) {
                self.capabilities[idx] = capability
            } else {
                self.capabilities.append(capability)
            }
            self.persist()
            Log.info(.system, "CapabilityStore: saved '\(capability.name)' (total: \(self.capabilities.count))")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .capabilityStoreDidChange, object: nil)
            }
        }
    }

    func all() -> [Capability] {
        queue.sync { capabilities }
    }

    private func persist() {
        let dir = indexURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(capabilities) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    // MARK: - Auto-Trigger Detection (fast, offline, scoring)

    /// Returns capabilities that match the current screen context, sorted by score.
    /// Called after every OCR cycle (~10s) for passive auto-trigger detection.
    ///
    /// Scoring (additive):
    ///   +4  per matching app (exact, case-insensitive)
    ///   +3  per matching URL pattern (substring of any detected URL)
    ///   +2  per matching OCR pattern (substring of screen text)
    ///   +1  per matching keyword (in transcript or screen text)
    func suggest(
        screenText: String = "",
        transcript: String = "",
        app: String? = nil,
        urls: [String] = []
    ) -> [Capability] {
        let lowerScreen     = screenText.lowercased()
        let lowerTranscript = transcript.lowercased()
        let lowerApp        = app?.lowercased()
        let lowerURLs       = urls.map { $0.lowercased() }
        let combined        = lowerScreen + " " + lowerTranscript

        let scored: [(cap: Capability, score: Int)] = capabilities.map { cap in
            var score = 0
            let t = cap.triggers

            // App match
            if let a = lowerApp {
                for trigger in t.apps where trigger.lowercased() == a { score += 4 }
            }

            // URL pattern match
            for pattern in t.urlPatterns {
                let lp = pattern.lowercased()
                if lowerURLs.contains(where: { $0.contains(lp) }) { score += 3 }
            }

            // OCR pattern match
            for pattern in t.ocrPatterns {
                if lowerScreen.contains(pattern.lowercased()) { score += 2 }
            }

            // Keyword match
            for kw in t.keywords {
                if combined.contains(kw.lowercased()) { score += 1 }
            }

            return (cap, score)
        }

        return scored
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .map { $0.cap }
    }
}
