import Foundation

// MARK: - CapabilityStore (Unified)
//
// The single source of truth for ALL capabilities in AutoClawd.
// Loads from three sources:
//   1. Persisted (FUCBC-built + catalog-activated) → ~/.autoclawd/capabilities/index.json
//   2. OpenClaw SKILL.md files → ~/.autoclawd/openclaw-skills/ (with SkillTagRegistry tag injection)
//   3. Built-in execution skills (frontend-design, call-mode, etc.)
//
// Thread safety: uses an atomic snapshot for lock-free reads.
// Writes happen on a background queue and swap the snapshot atomically.
// `all()` and `suggest()` NEVER block the main thread.

final class CapabilityStore: @unchecked Sendable {

    static let shared = CapabilityStore()
    private init() { loadAll() }

    /// Background queue for file I/O and writes. Never use sync on this queue.
    private let writeQueue = DispatchQueue(label: "com.autoclawd.capability-store.write", qos: .utility)

    /// Lock-protected snapshot for thread-safe reads without queue.sync.
    private let lock = NSLock()
    private var _snapshot: [Capability] = []
    private var _persisted: [Capability] = []

    /// Thread-safe read of current capabilities snapshot. Never blocks.
    private var snapshot: [Capability] {
        lock.lock()
        let s = _snapshot
        lock.unlock()
        return s
    }

    /// Thread-safe write of snapshot.
    private func setSnapshot(_ caps: [Capability], persisted: [Capability]? = nil) {
        lock.lock()
        _snapshot = caps
        if let p = persisted { _persisted = p }
        lock.unlock()
    }

    /// Thread-safe read of persisted capabilities.
    private var persistedSnapshot: [Capability] {
        lock.lock()
        let p = _persisted
        lock.unlock()
        return p
    }

    /// Cache for OpenClaw loading (30-second TTL).
    private var openClawCache: [Capability] = []
    private var openClawCacheDate: Date?
    private let openClawCacheTTL: TimeInterval = 30.0

    // MARK: - Persistence

    private var indexURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".autoclawd/capabilities/index.json")
    }

    // MARK: - Multi-Source Loading

    /// Load capabilities from all sources: persisted + OpenClaw + built-in.
    /// Runs on background queue. Reads remain non-blocking during the scan.
    func loadAll() {
        writeQueue.async { [weak self] in
            guard let self else { return }

            var all: [String: Capability] = [:]  // keyed by id for dedup

            // ── Source 1: Persisted (FUCBC-built + catalog-activated) ──
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var loadedPersisted: [Capability] = []
            if let data = try? Data(contentsOf: self.indexURL),
               let decoded = try? decoder.decode([Capability].self, from: data) {
                loadedPersisted = decoded
                for cap in decoded { all[cap.id] = cap }
            }

            // ── Source 2: OpenClaw SKILL.md → Capability (with tag injection) ──
            let openClawDir = SkillStore.openClawDirectory()
            let openClawCaps = OpenClawSkillLoader.loadCapabilities(from: openClawDir)
            self.openClawCache = openClawCaps
            self.openClawCacheDate = Date()
            for cap in openClawCaps {
                // Persisted wins over OpenClaw when same id (user may have customized)
                if all[cap.id] == nil {
                    all[cap.id] = cap
                }
            }

            // ── Source 3: Built-in execution skills ──
            for cap in Self.builtinCapabilities {
                if all[cap.id] == nil {
                    all[cap.id] = cap
                }
            }

            let result = Array(all.values)
            self.setSnapshot(result, persisted: loadedPersisted)
            Log.info(.system, "CapabilityStore: loaded \(result.count) total (\(loadedPersisted.count) persisted, \(openClawCaps.count) openclaw, \(Self.builtinCapabilities.count) builtin)")

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .capabilityStoreDidChange, object: nil)
            }
        }
    }

    /// Force-refresh OpenClaw capabilities from disk.
    func refreshOpenClaw() {
        openClawCacheDate = nil
        loadAll()
    }

    // MARK: - CRUD

    /// Save (or update) a persisted capability. Deduplicates by id.
    func save(_ capability: Capability) {
        writeQueue.async { [weak self] in
            guard let self else { return }

            // Update persisted list
            var persisted = self.persistedSnapshot
            if let idx = persisted.firstIndex(where: { $0.id == capability.id }) {
                persisted[idx] = capability
            } else {
                persisted.append(capability)
            }
            self.persistFile(persisted)

            // Update unified list
            var caps = self.snapshot
            if let idx = caps.firstIndex(where: { $0.id == capability.id }) {
                caps[idx] = capability
            } else {
                caps.append(capability)
            }

            self.setSnapshot(caps, persisted: persisted)
            Log.info(.system, "CapabilityStore: saved '\(capability.name)' (total: \(caps.count))")

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .capabilityStoreDidChange, object: nil)
            }
        }
    }

    /// All capabilities from all sources. Non-blocking — returns current snapshot instantly.
    func all() -> [Capability] {
        snapshot
    }

    /// Look up a single capability by id. Non-blocking.
    func load(id: String) -> Capability? {
        snapshot.first(where: { $0.id == id })
    }

    /// Delete a persisted capability by id.
    func delete(id: String) {
        writeQueue.async { [weak self] in
            guard let self else { return }

            var persisted = self.persistedSnapshot
            persisted.removeAll { $0.id == id }
            self.persistFile(persisted)

            var caps = self.snapshot
            caps.removeAll { $0.id == id }

            self.setSnapshot(caps, persisted: persisted)
            Log.info(.system, "CapabilityStore: deleted '\(id)'")

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .capabilityStoreDidChange, object: nil)
            }
        }
    }

    private func persistFile(_ persisted: [Capability]) {
        let dir = indexURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(persisted) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    // MARK: - Auto-Trigger Detection (fast, offline, scoring)

    /// Returns capabilities that match the current screen context, sorted by score.
    /// Non-blocking — reads from the current snapshot.
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
        let caps = snapshot  // single atomic read
        let lowerScreen     = screenText.lowercased()
        let lowerTranscript = transcript.lowercased()
        let lowerApp        = app?.lowercased()
        let lowerURLs       = urls.map { $0.lowercased() }
        let combined        = lowerScreen + " " + lowerTranscript

        let scored: [(cap: Capability, score: Int)] = caps.map { cap in
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

    // MARK: - Built-in Capabilities

    /// Non-pipeline built-in skills converted to Capabilities.
    /// Pipeline skills (transcript-cleaning, transcript-analysis, task-creation) stay in SkillStore.
    static let builtinCapabilities: [Capability] = [
        Capability(
            id: "builtin-frontend-design",
            name: "Frontend Design",
            description: "Generate UI components, pages, and styling code",
            emoji: "🎨",
            category: .creative,
            triggers: CapabilityTriggers(apps: ["Xcode", "VS Code", "Cursor"], urlPatterns: ["figma.com", "dribbble.com"], keywords: ["design", "frontend", "UI", "CSS", "styling"], ocrPatterns: []),
            slug: "frontend-design",
            source: .builtin,
            workflowTags: ["development", "design"]
        ),
        Capability(
            id: "builtin-data-analysis",
            name: "Data Analysis",
            description: "Analyze data: aggregation, clustering, visualization, insights",
            emoji: "📊",
            category: .analysis,
            triggers: CapabilityTriggers(apps: ["Numbers", "Excel"], urlPatterns: [], keywords: ["data", "analysis", "chart", "statistics", "aggregate", "cluster"], ocrPatterns: []),
            slug: "data-analysis",
            source: .builtin,
            workflowTags: ["analysis", "data"]
        ),
        Capability(
            id: "builtin-project-management",
            name: "Project Management",
            description: "Sprint planning, scheduling, ticket creation, team coordination",
            emoji: "📋",
            category: .organization,
            triggers: CapabilityTriggers(apps: ["Linear", "Jira", "Notion"], urlPatterns: ["linear.app", "jira.atlassian"], keywords: ["sprint", "ticket", "backlog", "milestone", "planning"], ocrPatterns: []),
            slug: "project-management",
            source: .builtin,
            workflowTags: ["management", "planning"]
        ),
        Capability(
            id: "builtin-video-generation",
            name: "Video Generation",
            description: "AI-powered video synthesis and generation",
            emoji: "🎬",
            category: .creative,
            triggers: CapabilityTriggers(apps: [], urlPatterns: ["freepik.com"], keywords: ["generate video", "video generation", "AI video"], ocrPatterns: []),
            slug: "video-generation",
            source: .builtin,
            workflowTags: ["video-production", "creative"]
        ),
        Capability(
            id: "builtin-campaign-activation",
            name: "Campaign Activation",
            description: "Marketing campaign planning and activation across platforms",
            emoji: "📣",
            category: .marketing,
            triggers: CapabilityTriggers(apps: ["Threads", "Twitter"], urlPatterns: ["threads.net", "x.com", "facebook.com", "instagram.com"], keywords: ["campaign", "launch", "promote", "marketing"], ocrPatterns: []),
            slug: "campaign-activation",
            source: .builtin,
            workflowTags: ["marketing", "social-media"]
        ),
        Capability(
            id: "builtin-call-mode",
            name: "Call Mode",
            description: "Real-time screen sharing with Claude — cursor context, selection, transcript",
            emoji: "📞",
            category: .automation,
            triggers: CapabilityTriggers(apps: [], urlPatterns: [], keywords: ["call mode", "screen share", "pair program"], ocrPatterns: []),
            slug: "call-mode",
            source: .builtin,
            workflowTags: ["development", "collaboration"]
        ),
        Capability(
            id: "builtin-graphic-design",
            name: "Graphic Design Studio",
            description: "Create event invites, social posts, banners, thumbnails — programmatic design with Remotion",
            emoji: "🖼️",
            category: .creative,
            triggers: CapabilityTriggers(
                apps: ["Canva", "Figma", "Keynote", "Preview"],
                urlPatterns: ["canva.com", "figma.com", "dribbble.com", "behance.net"],
                keywords: ["event invite", "social post", "banner", "thumbnail", "graphic design", "create poster", "flyer", "story card", "design image"],
                ocrPatterns: ["Create a design", "New Design", "Custom size"]
            ),
            slug: "design-to-image",
            source: .builtin,
            workflowTags: ["graphic-design", "creative", "content-creation", "visual-design"]
        ),
    ]
}
