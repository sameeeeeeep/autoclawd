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
    private init() {
        loadDismissals()  // load persisted snooze/irrelevant before capability loading
        loadAll()
    }

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

    // MARK: - Dismissal Memory (persisted across launches)

    /// capID → suppress until this date (X button — "not now").
    /// Accessed only under `lock` (same NSLock used for `snapshot`).
    private var snoozedUntil: [String: Date] = [:]
    /// Permanently suppressed across sessions (👎 button — "not relevant").
    /// Accessed only under `lock`.
    private var irrelevantIDs: Set<String> = []

    private let snoozedKey   = "autoclawd.capability.snoozed"
    private let irrelevantKey = "autoclawd.capability.irrelevant"

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

    /// Suppress this capability for 2 hours ("not now" — X button).
    func snooze(capabilityID: String) {
        lock.lock()
        snoozedUntil[capabilityID] = Date().addingTimeInterval(7200)
        lock.unlock()
        saveDismissals()
    }

    /// Permanently suppress across sessions ("not relevant" — 👎 button).
    func markIrrelevant(capabilityID: String) {
        lock.lock()
        irrelevantIDs.insert(capabilityID)
        lock.unlock()
        saveDismissals()
    }

    // MARK: - Dismissal Persistence

    private func loadDismissals() {
        let fmt = ISO8601DateFormatter()
        let now = Date()
        if let dict = UserDefaults.standard.dictionary(forKey: snoozedKey) as? [String: String] {
            for (id, dateStr) in dict {
                if let date = fmt.date(from: dateStr), date > now {
                    snoozedUntil[id] = date
                }
            }
        }
        if let ids = UserDefaults.standard.array(forKey: irrelevantKey) as? [String] {
            irrelevantIDs = Set(ids)
        }
    }

    private func saveDismissals() {
        let fmt = ISO8601DateFormatter()
        let (snoozed, irrelevant): ([String: Date], Set<String>)
        lock.lock()
        snoozed = snoozedUntil
        irrelevant = irrelevantIDs
        lock.unlock()
        let dict = snoozed.mapValues { fmt.string(from: $0) }
        UserDefaults.standard.set(dict, forKey: snoozedKey)
        UserDefaults.standard.set(Array(irrelevant), forKey: irrelevantKey)
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

    /// Returns suggestion matches for the current screen context, sorted by score.
    /// Score threshold: >= 3. Skips snoozed and irrelevant capabilities.
    func suggest(
        screenText: String = "",
        transcript: String = "",
        app: String? = nil,
        urls: [String] = []
    ) -> [SuggestionMatch] {
        let caps = snapshot  // single atomic read
        lock.lock()
        let snoozedSnapshot    = snoozedUntil
        let irrelevantSnapshot = irrelevantIDs
        lock.unlock()
        let lowerScreen     = screenText.lowercased()
        let lowerTranscript = transcript.lowercased()
        let lowerApp        = app?.lowercased()
        // Merge explicit URLs with those extracted from OCR text (e.g. typed/visible URLs)
        let ocrURLs   = Self.extractURLs(from: screenText).map { $0.lowercased() }
        let lowerURLs = (urls.map { $0.lowercased() } + ocrURLs)

        var results: [SuggestionMatch] = []

        for cap in caps {
            guard !irrelevantSnapshot.contains(cap.id) else { continue }
            if let until = snoozedSnapshot[cap.id], Date() < until { continue }

            var score = 0
            var signals: [MatchSignal] = []
            let t = cap.triggers

            // App match (+2). Intentionally below threshold (3) so app alone never triggers.
            // Requires at least one additional signal (URL, OCR pattern, or keyword) to surface.
            if let a = lowerApp {
                for trigger in t.apps where trigger.lowercased() == a {
                    score += 2
                    signals.append(.app(trigger))
                }
            }

            // URL pattern match (+3). Most specific signal — URL alone can trigger.
            for pattern in t.urlPatterns {
                let lp = pattern.lowercased()
                if lowerURLs.contains(where: { $0.contains(lp) }) {
                    score += 3
                    signals.append(.url(pattern))
                }
            }

            // OCR pattern match (+2)
            for pattern in t.ocrPatterns {
                if lowerScreen.contains(pattern.lowercased()) {
                    score += 2
                    signals.append(.ocr(pattern))
                }
            }

            // Keyword match: transcript (+2, intentional speech) or OCR (+1, ambient context).
            // Using transcript wins — prevents double-counting if the keyword appears in both.
            // App (2) + OCR keyword (1) = 3 → fires. App alone (2) = still blocked.
            for kw in t.keywords {
                let lkw = kw.lowercased()
                if lowerTranscript.contains(lkw) {
                    score += 2
                    signals.append(.keyword(kw))
                } else if lowerScreen.contains(lkw) {
                    score += 1
                    signals.append(.keyword(kw))
                }
            }

            guard score >= 3 else { continue }

            let headline = resolveHeadline(
                template: cap.contextualQuestionTemplate,
                signals: signals,
                capabilityName: cap.name
            )
            results.append(SuggestionMatch(
                capability: cap,
                score: score,
                matchedSignals: signals,
                contextualHeadline: headline
            ))
        }

        return results.sorted { $0.score > $1.score }
    }

    // MARK: - URL Extraction from OCR

    /// Extracts http/https URLs from raw screen/OCR text using NSDataDetector.
    private static func extractURLs(from text: String) -> [String] {
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap { $0.url?.absoluteString }
    }

    private func isAppSignal(_ s: MatchSignal) -> Bool {
        if case .app = s { return true }
        return false
    }

    private func isUrlSignal(_ s: MatchSignal) -> Bool {
        if case .url = s { return true }
        return false
    }

    private func isOcrSignal(_ s: MatchSignal) -> Bool {
        if case .ocr = s { return true }
        return false
    }

    private func resolveHeadline(template: String, signals: [MatchSignal], capabilityName: String) -> String {
        guard !template.isEmpty else {
            for signal in signals {
                switch signal {
                case .app(let name):
                    return "Working in \(name)?"
                case .url(let pattern):
                    let clean = pattern.hasPrefix("www.") ? String(pattern.dropFirst(4)) : pattern
                    return "Something to do with \(clean)?"
                case .ocr(let snippet):
                    let short = snippet.count > 30 ? String(snippet.prefix(30)) + "…" : snippet
                    return "Working on: \(short)?"
                case .keyword:
                    continue
                }
            }
            return "Automate \(capabilityName)?"
        }

        var resolved = template

        if resolved.contains("{app}") {
            if let appSignal = signals.first(where: isAppSignal),
               case .app(let name) = appSignal {
                resolved = resolved.replacingOccurrences(of: "{app}", with: name)
            } else if let urlSignal = signals.first(where: isUrlSignal),
                      case .url(let p) = urlSignal {
                let clean = p.hasPrefix("www.") ? String(p.dropFirst(4)) : p
                resolved = resolved.replacingOccurrences(of: "{app}", with: clean)
            } else {
                resolved = resolved.replacingOccurrences(of: " {app}", with: "").replacingOccurrences(of: "{app}", with: "")
            }
        }

        if resolved.contains("{url}") {
            if let urlSignal = signals.first(where: isUrlSignal),
               case .url(let p) = urlSignal {
                let clean = p.hasPrefix("www.") ? String(p.dropFirst(4)) : p
                resolved = resolved.replacingOccurrences(of: "{url}", with: clean)
            } else {
                resolved = resolved.replacingOccurrences(of: " {url}", with: "").replacingOccurrences(of: "{url}", with: "")
            }
        }

        if resolved.contains("{ocr}") {
            if let ocrSignal = signals.first(where: isOcrSignal),
               case .ocr(let snippet) = ocrSignal {
                let short = snippet.count > 30 ? String(snippet.prefix(30)) + "…" : snippet
                resolved = resolved.replacingOccurrences(of: "{ocr}", with: short)
            } else {
                resolved = resolved.replacingOccurrences(of: " {ocr}", with: "").replacingOccurrences(of: "{ocr}", with: "")
            }
        }

        return resolved.trimmingCharacters(in: .whitespaces)
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
            workflowTags: ["development", "design"],
            contextualQuestionTemplate: "Building a UI in {app}?"
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
            workflowTags: ["analysis", "data"],
            contextualQuestionTemplate: "Analysing data in {app}?"
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
            workflowTags: ["management", "planning"],
            contextualQuestionTemplate: "Planning in {app}?"
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
            workflowTags: ["video-production", "creative"],
            contextualQuestionTemplate: "Generating a video?"
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
            workflowTags: ["marketing", "social-media"],
            contextualQuestionTemplate: "Launching a {app} campaign?"
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
            workflowTags: ["development", "collaboration"],
            contextualQuestionTemplate: "Want real-time screen context?"
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
            workflowTags: ["graphic-design", "creative", "content-creation", "visual-design"],
            contextualQuestionTemplate: "Creating a design in {app}?"
        ),
    ]
}
