# Smarter Capability Suggestions Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace generic capability toasts with contextually smart suggestions — specific question headlines, two-tier dismissal, score threshold of 3+, tool icon strip.

**Architecture:** New `MatchSignal` + `SuggestionMatch` value types flow from `CapabilityStore.suggest()` through `AppState` → `AppDelegate` → `ToastWindow` → `ToastView`. All seven files are updated in dependency order so each incremental `make` build passes cleanly.

**Tech Stack:** Swift/SwiftUI + AppKit macOS app; build with `make` (not `swift build`); Glass design system from `LiquidGlass.swift`; `NSWorkspace` for app icons.

**Spec:** `docs/superpowers/specs/2026-03-14-smarter-suggestions-design.md`

---

## Chunk 1: Data Model & Detection Engine

### Task 1: Add MatchSignal, SuggestionMatch and contextualQuestionTemplate to LearnModeModels.swift

**Files:**
- Modify: `Sources/LearnModeModels.swift`

- [ ] **Step 1: Add `MatchSignal` enum after the imports block (before `// MARK: - Event Snapshot`)**

Insert this block at the very top of `LearnModeModels.swift`, after `import Foundation`:

```swift
// MARK: - Suggestion Match Types

/// A single signal that fired during capability scoring.
/// Passed through to the toast so it can surface "why" in the headline.
enum MatchSignal: Equatable, Sendable {
    case app(String)      // matched app name, e.g. "Threads"
    case url(String)      // matched URL pattern, e.g. "threads.net"
    case ocr(String)      // matched OCR pattern, e.g. "New Post"
    case keyword(String)  // matched keyword, e.g. "campaign"
}

/// Returned by CapabilityStore.suggest() instead of bare Capability.
/// Carries everything the toast needs. Transient — never persisted.
struct SuggestionMatch: Sendable {
    let capability: Capability
    let score: Int
    let matchedSignals: [MatchSignal]  // all signals that contributed to the score
    let contextualHeadline: String     // resolved question, e.g. "Launching a Threads campaign?"
}
```

- [ ] **Step 2: Add `contextualQuestionTemplate` to `Capability`**

In `Capability`, add the property after the existing `workflowTags` property declaration (around line 91):

```swift
    /// Context-specific question shown in the toast headline.
    /// Tokens: {app}, {url}, {ocr} are filled at match time.
    /// Empty string → fallback headline derivation at suggestion time.
    var contextualQuestionTemplate: String
```

- [ ] **Step 3: Add `contextualQuestionTemplate` to `CodingKeys`**

In the `enum CodingKeys` block, add after `case workflowTags`:

```swift
        case contextualQuestionTemplate
```

- [ ] **Step 4: Add decode in `init(from decoder:)` with fallback default**

In `init(from decoder:)`, add after the `workflowTags` decode line:

```swift
        contextualQuestionTemplate = try c.decodeIfPresent(String.self, forKey: .contextualQuestionTemplate) ?? ""
```

- [ ] **Step 5: Add parameter to memberwise `init(...)`**

In the memberwise `init(...)`, add after the `workflowTags` parameter:

```swift
        contextualQuestionTemplate: String = "",
```

And in the body of the memberwise `init`, add after `self.workflowTags = workflowTags`:

```swift
        self.contextualQuestionTemplate = contextualQuestionTemplate
```

- [ ] **Step 6: Build and confirm clean compilation**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd/.claude/worktrees/epic-robinson" && make 2>&1 | tail -20
```

Expected: build succeeds. (The rest of the codebase still uses `Capability` directly — that's fine, no call sites have changed yet.)

- [ ] **Step 7: Commit**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd/.claude/worktrees/epic-robinson"
git add Sources/LearnModeModels.swift
git commit -m "feat: add MatchSignal, SuggestionMatch, contextualQuestionTemplate to data model"
```

---

### Task 2: Rewrite CapabilityStore.suggest() and update builtins

**Files:**
- Modify: `Sources/CapabilityStore.swift`

- [ ] **Step 1: Add dismissal dictionaries (in-memory, resets on launch)**

In `CapabilityStore`, add these two properties after the `openClawCache*` properties (around line 53–55):

```swift
    // MARK: - Dismissal Memory (in-memory, resets on launch)

    /// capID → suppress until this date (X button — "not now").
    /// Accessed only under `lock` (same NSLock used for `snapshot`).
    private var snoozedUntil: [String: Date] = [:]
    /// Permanently suppressed for this session (👎 button — "not relevant").
    /// Accessed only under `lock`.
    private var irrelevantIDs: Set<String> = []
```

- [ ] **Step 2: Add public snooze/markIrrelevant methods**

Add these after the `delete(id:)` method and before `persistFile`:

```swift
    /// Suppress this capability for 2 hours ("not now" — X button).
    func snooze(capabilityID: String) {
        lock.lock()
        snoozedUntil[capabilityID] = Date().addingTimeInterval(7200)
        lock.unlock()
    }

    /// Permanently suppress for this session ("not relevant" — 👎 button).
    func markIrrelevant(capabilityID: String) {
        lock.lock()
        irrelevantIDs.insert(capabilityID)
        lock.unlock()
    }
```

- [ ] **Step 3: Replace the `suggest()` method entirely**

Replace the entire `suggest(screenText:transcript:app:urls:) -> [Capability]` method (lines 202–247) with the new implementation:

```swift
    /// Returns suggestion matches for the current screen context, sorted by score.
    /// Score threshold: >= 3. Skips snoozed and irrelevant capabilities.
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
    ) -> [SuggestionMatch] {
        let caps = snapshot  // single atomic read
        lock.lock()
        let snoozedSnapshot    = snoozedUntil
        let irrelevantSnapshot = irrelevantIDs
        lock.unlock()
        let lowerScreen     = screenText.lowercased()
        let lowerTranscript = transcript.lowercased()
        let lowerApp        = app?.lowercased()
        let lowerURLs       = urls.map { $0.lowercased() }
        let combined        = lowerScreen + " " + lowerTranscript

        var results: [SuggestionMatch] = []

        for cap in caps {
            // Skip dismissed capabilities (using thread-safe snapshots taken above)
            guard !irrelevantSnapshot.contains(cap.id) else { continue }
            if let until = snoozedSnapshot[cap.id], Date() < until { continue }

            var score = 0
            var signals: [MatchSignal] = []
            let t = cap.triggers

            // App match (+4)
            if let a = lowerApp {
                for trigger in t.apps where trigger.lowercased() == a {
                    score += 4
                    signals.append(.app(trigger))
                }
            }

            // URL pattern match (+3)
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

            // Keyword match (+1)
            for kw in t.keywords {
                if combined.contains(kw.lowercased()) {
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

    /// Resolves the contextual question headline from a template and fired signals.
    private func resolveHeadline(template: String, signals: [MatchSignal], capabilityName: String) -> String {
        guard !template.isEmpty else {
            // Fallback: derive from strongest signal type
            for signal in signals {
                switch signal {
                case .app(let name):     return "Working in \(name)?"
                case .url(let pattern):
                    let clean = pattern.hasPrefix("www.") ? String(pattern.dropFirst(4)) : pattern
                    return "Something to do with \(clean)?"
                case .ocr(let snippet):
                    let short = snippet.count > 30 ? String(snippet.prefix(30)) + "…" : snippet
                    return "Working on: \(short)?"
                case .keyword:           continue
                }
            }
            return "Automate \(capabilityName)?"
        }

        var resolved = template

        // {app} → first app signal
        if resolved.contains("{app}") {
            if let appSignal = signals.first(where: { if case .app = $0 { return true }; return false }),
               case .app(let name) = appSignal {
                resolved = resolved.replacingOccurrences(of: "{app}", with: name)
            } else if let urlSignal = signals.first(where: { if case .url = $0 { return true }; return false }),
                      case .url(let p) = urlSignal {
                let clean = p.hasPrefix("www.") ? String(p.dropFirst(4)) : p
                resolved = resolved.replacingOccurrences(of: "{app}", with: clean)
            } else {
                resolved = resolved.replacingOccurrences(of: " {app}", with: "").replacingOccurrences(of: "{app}", with: "")
            }
        }

        // {url} → first url signal
        if resolved.contains("{url}") {
            if let urlSignal = signals.first(where: { if case .url = $0 { return true }; return false }),
               case .url(let p) = urlSignal {
                let clean = p.hasPrefix("www.") ? String(p.dropFirst(4)) : p
                resolved = resolved.replacingOccurrences(of: "{url}", with: clean)
            } else {
                resolved = resolved.replacingOccurrences(of: " {url}", with: "").replacingOccurrences(of: "{url}", with: "")
            }
        }

        // {ocr} → first ocr signal, truncated
        if resolved.contains("{ocr}") {
            if let ocrSignal = signals.first(where: { if case .ocr = $0 { return true }; return false }),
               case .ocr(let snippet) = ocrSignal {
                let short = snippet.count > 30 ? String(snippet.prefix(30)) + "…" : snippet
                resolved = resolved.replacingOccurrences(of: "{ocr}", with: short)
            } else {
                resolved = resolved.replacingOccurrences(of: " {ocr}", with: "").replacingOccurrences(of: "{ocr}", with: "")
            }
        }

        return resolved.trimmingCharacters(in: .whitespaces)
    }
```

- [ ] **Step 4: Update all 7 builtinCapabilities with `contextualQuestionTemplate:`**

In `builtinCapabilities`, each `Capability(...)` call needs `contextualQuestionTemplate:` added. Replace the entire `static let builtinCapabilities: [Capability] = [...]` array with:

```swift
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
```

- [ ] **Step 5: Build and confirm clean compilation**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd/.claude/worktrees/epic-robinson" && make 2>&1 | tail -20
```

Expected: build fails with errors about `[Capability]` vs `[SuggestionMatch]` type mismatches in AppState.swift and LearnModeService.swift — that's expected because the call sites haven't been updated yet. If it fails only on those downstream files, proceed. If there are errors IN CapabilityStore.swift itself, fix those first.

> **Note on Swift pattern matching in closures:** The `if case .app = $0 { return true }; return false` pattern inside `first(where:)` closures requires explicit semicolons since we're in single-expression closures. If the compiler complains, use a helper:
> ```swift
> func isApp(_ s: MatchSignal) -> Bool { if case .app = s { return true }; return false }
> ```
> and replace `{ if case .app = $0 { return true }; return false }` with `isApp`.
> Add these private helpers at the top of the `resolveHeadline` implementation or as a private extension. The plan code uses inline closures for brevity; if they cause "expression too complex" errors, extract them.

- [ ] **Step 6: Commit**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd/.claude/worktrees/epic-robinson"
git add Sources/CapabilityStore.swift
git commit -m "feat: rewrite suggest() returning SuggestionMatch, add dismissal memory, update 7 builtins"
```

---

## Chunk 2: State + Service Call Sites

### Task 3: Rename detectedCapability → detectedSuggestion in AppState.swift

**Files:**
- Modify: `Sources/AppState.swift`

- [ ] **Step 1: Replace the published property declaration (line ~166)**

Find:
```swift
    @Published var detectedCapability: Capability? = nil
```
Replace with:
```swift
    @Published var detectedSuggestion: SuggestionMatch? = nil
```

- [ ] **Step 2: Update the auto-trigger call site (line ~651)**

Find:
```swift
                    let matches = CapabilityStore.shared.suggest(screenText: ocrText, app: app)
                    self.detectedCapability = matches.first
```
Replace with:
```swift
                    let matches = CapabilityStore.shared.suggest(screenText: ocrText, app: app)
                    self.detectedSuggestion = matches.first
```

- [ ] **Step 3: Update executeCapability — clear detectedSuggestion (line ~1336)**

Find:
```swift
    func executeCapability(_ capability: Capability) {
        detectedCapability = nil
```
Replace with:
```swift
    func executeCapability(_ capability: Capability) {
        detectedSuggestion = nil
```

- [ ] **Step 4: Update dismissDetectedCapability (line ~1413)**

Find:
```swift
    func dismissDetectedCapability() {
        detectedCapability = nil
    }
```
Replace with:
```swift
    func dismissDetectedCapability() {
        detectedSuggestion = nil
    }
```

- [ ] **Step 5: Build — expect only LearnModeService and AppDelegate errors**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd/.claude/worktrees/epic-robinson" && make 2>&1 | grep -E "error:" | head -30
```

Expected remaining errors:
- `LearnModeService.swift`: type mismatch in `buildCapability()` and `suggestCapabilities()`
- `AppDelegate.swift`: `$detectedCapability` unknown + `showCapabilityToast` signature mismatch
- `ToastWindow.swift`: `CapabilityToastModel.capability` type mismatch

No errors should be in `AppState.swift` itself.

- [ ] **Step 6: Commit**

```bash
git add Sources/AppState.swift
git commit -m "feat: rename detectedCapability → detectedSuggestion in AppState"
```

---

### Task 4: Fix LearnModeService.swift call sites

**Files:**
- Modify: `Sources/LearnModeService.swift`

- [ ] **Step 1: Fix `buildCapability()` — map SuggestionMatch back to Capability**

In `buildCapability()`, find lines ~135–145:
```swift
        let similar = CapabilityStore.shared.suggest(
            screenText: snapshot?.extractedText ?? "",
            transcript: currentSession.events.compactMap { $0.speechSnippet.isEmpty ? nil : $0.speechSnippet }.joined(separator: " "),
            app: snapshot?.appName,
            urls: snapshot?.detectedURLs ?? []
        ).filter { $0.id != capID }

        session?.builtCapability = capability
        session?.suggestedCapabilities = Array(similar.prefix(5))
        session?.phase = .done(capID)
        Log.info(.ui, "FUCBC: built '\(capability.name)' slug=\(capability.slug) suggested=\(similar.prefix(5).map { $0.slug })")
```

Replace with:
```swift
        let similar = CapabilityStore.shared.suggest(
            screenText: snapshot?.extractedText ?? "",
            transcript: currentSession.events.compactMap { $0.speechSnippet.isEmpty ? nil : $0.speechSnippet }.joined(separator: " "),
            app: snapshot?.appName,
            urls: snapshot?.detectedURLs ?? []
        ).filter { $0.capability.id != capID }

        session?.builtCapability = capability
        session?.suggestedCapabilities = Array(similar.prefix(5).map { $0.capability })
        session?.phase = .done(capID)
        Log.info(.ui, "FUCBC: built '\(capability.name)' slug=\(capability.slug) suggested=\(similar.prefix(5).map { $0.capability.slug })")
```

(`LearnSession.suggestedCapabilities` stays `[Capability]` — we map back here. The `Log.info` line is included in the replace to fix the `$0.slug` reference, which would otherwise fail to compile since `SuggestionMatch` has no `.slug` property.)

- [ ] **Step 2: Update `suggestCapabilities()` return type and forwarding**

Find:
```swift
    func suggestCapabilities(screenText: String = "", app: String? = nil, urls: [String] = []) -> [Capability] {
        CapabilityStore.shared.suggest(screenText: screenText, app: app, urls: urls)
    }
```

Replace with:
```swift
    func suggestCapabilities(screenText: String = "", app: String? = nil, urls: [String] = []) -> [SuggestionMatch] {
        CapabilityStore.shared.suggest(screenText: screenText, app: app, urls: urls)
    }
```

- [ ] **Step 3: Build — expect only AppDelegate and ToastWindow errors**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd/.claude/worktrees/epic-robinson" && make 2>&1 | grep -E "error:" | head -20
```

Expected: errors only in `AppDelegate.swift` and `ToastWindow.swift`.

- [ ] **Step 4: Commit**

```bash
git add Sources/LearnModeService.swift
git commit -m "feat: update LearnModeService to use SuggestionMatch, map back to Capability for session"
```

---

## Chunk 3: Wiring + Toast Redesign

### Task 5: Update AppDelegate.swift — Combine sink, toast function, canvasForCurrentMode

**Files:**
- Modify: `Sources/AppDelegate.swift`

- [ ] **Step 1: Update the Combine sink subscription (~line 55)**

Find:
```swift
        appState.$detectedCapability
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cap in
                guard let self else { return }
                if let cap {
                    self.showCapabilityToast(cap)
                } else {
                    self.dismissCapabilityToast()
                }
            }
            .store(in: &cancellables)
```

Replace with:
```swift
        appState.$detectedSuggestion
            .receive(on: DispatchQueue.main)
            .sink { [weak self] match in
                guard let self else { return }
                if let match {
                    self.showCapabilityToast(match)
                } else {
                    self.dismissCapabilityToast()
                }
            }
            .store(in: &cancellables)
```

- [ ] **Step 2: Update `showCapabilityToast` signature and body (~line 232)**

Find:
```swift
    private func showCapabilityToast(_ capability: Capability) {
        guard appState.showToasts else { return }
        toastDismissWork?.cancel()

        if toastWindow == nil {
            toastWindow = ToastWindow()
        }
        guard let toast = toastWindow else { return }

        toast.showCapability(capability,
            onTap: { [weak self] in
                guard let self else { return }
                self.appState.executeCapability(capability)
                self.dismissCapabilityToast()
                self.showMainPanel(tab: .agents)
            },
            onDismiss: { [weak self] in
                self?.appState.dismissDetectedCapability()
            }
        )

        // Auto-dismiss after 5 seconds
        let work = DispatchWorkItem { [weak self] in
            self?.appState.dismissDetectedCapability()
        }
        toastDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }
```

Replace with:
```swift
    private func showCapabilityToast(_ match: SuggestionMatch) {
        guard appState.showToasts else { return }
        toastDismissWork?.cancel()

        if toastWindow == nil {
            toastWindow = ToastWindow()
        }
        guard let toast = toastWindow else { return }

        toast.showCapability(match,
            onTap: { [weak self] in
                guard let self else { return }
                self.appState.executeCapability(match.capability)
                self.dismissCapabilityToast()
                self.showMainPanel(tab: .agents)
            },
            onSnooze: { [weak self] in
                guard let self else { return }
                CapabilityStore.shared.snooze(capabilityID: match.capability.id)
                self.appState.dismissDetectedCapability()
            },
            onMarkIrrelevant: { [weak self] in
                guard let self else { return }
                CapabilityStore.shared.markIrrelevant(capabilityID: match.capability.id)
                self.appState.dismissDetectedCapability()
            }
        )

        // Auto-dismiss after 5 seconds (no hover-reset)
        let work = DispatchWorkItem { [weak self] in
            self?.appState.dismissDetectedCapability()
        }
        toastDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }
```

- [ ] **Step 3: Update `canvasForCurrentMode` block (~line 716)**

Find:
```swift
        // ── FUCBC capability suggestion ("Automate now") ──────────────────────────
        if let cap = appState.detectedCapability {
            return AnyView(CapabilitySuggestionCanvasView(
                capability: cap,
                onRun:     { appState.executeCapability(cap) },
                onDismiss: { appState.dismissDetectedCapability() }
            ))
        }
```

Replace with:
```swift
        // ── FUCBC capability suggestion ("Automate now") ──────────────────────────
        if let match = appState.detectedSuggestion {
            return AnyView(CapabilitySuggestionCanvasView(
                capability: match.capability,
                onRun:     { appState.executeCapability(match.capability) },
                onDismiss: { appState.dismissDetectedCapability() }
            ))
        }
```

(`CapabilitySuggestionCanvasView` in `WidgetCanvasViews.swift` takes `let capability: Capability` and does NOT need to change — only this call site changes.)

- [ ] **Step 4: Build — expect only ToastWindow errors**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd/.claude/worktrees/epic-robinson" && make 2>&1 | grep -E "error:" | head -20
```

Expected: errors only in `ToastWindow.swift` about mismatched `showCapability` signature.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppDelegate.swift
git commit -m "feat: update AppDelegate to wire SuggestionMatch through toast and canvas"
```

---

### Task 6: Update ToastWindow.swift — CapabilityToastModel and showCapability

**Files:**
- Modify: `Sources/ToastWindow.swift`

- [ ] **Step 1: Update CapabilityToastModel to hold SuggestionMatch**

Find:
```swift
final class CapabilityToastModel: ObservableObject {
    @Published var capability: Capability?
    var onTap: () -> Void = {}
    var onDismiss: () -> Void = {}
}
```

Replace with:
```swift
final class CapabilityToastModel: ObservableObject {
    @Published var match: SuggestionMatch?
    var onTap: () -> Void = {}
    var onSnooze: () -> Void = {}
    var onMarkIrrelevant: () -> Void = {}
}
```

- [ ] **Step 2: Update CapabilityToastModelView**

Find:
```swift
private struct CapabilityToastModelView: View {
    @ObservedObject var model: CapabilityToastModel

    var body: some View {
        if let cap = model.capability {
            CapabilityToastView(
                capability: cap,
                onTap: model.onTap,
                onDismiss: model.onDismiss
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}
```

Replace with:
```swift
private struct CapabilityToastModelView: View {
    @ObservedObject var model: CapabilityToastModel

    var body: some View {
        if let m = model.match {
            CapabilityToastView(
                match: m,
                onTap: model.onTap,
                onSnooze: model.onSnooze,
                onMarkIrrelevant: model.onMarkIrrelevant
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}
```

- [ ] **Step 3: Update ToastWindow init — resize for new toast dimensions**

In `ToastWindow.init()`, find:
```swift
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 52),
```
Replace with:
```swift
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 110),
```

- [ ] **Step 4: Update `showCapability` signature and body**

Find:
```swift
    func showCapability(_ capability: Capability, onTap: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        capModel.capability = capability
        capModel.onTap = onTap
        capModel.onDismiss = onDismiss
        positionTopRight()
        orderFront(nil)
    }
```

Replace with:
```swift
    func showCapability(_ match: SuggestionMatch, onTap: @escaping () -> Void, onSnooze: @escaping () -> Void, onMarkIrrelevant: @escaping () -> Void) {
        capModel.match = match
        capModel.onTap = onTap
        capModel.onSnooze = onSnooze
        capModel.onMarkIrrelevant = onMarkIrrelevant
        positionTopRight()
        orderFront(nil)
    }
```

- [ ] **Step 5: Update `dismiss()` to clear match**

Find:
```swift
    func dismiss() {
        capModel.capability = nil
        orderOut(nil)
    }
```

Replace with:
```swift
    func dismiss() {
        capModel.match = nil
        orderOut(nil)
    }
```

- [ ] **Step 6: Update `positionTopRight()` for new height**

Find:
```swift
        let x = visibleFrame.maxX - 260 - 16
        let y = visibleFrame.maxY - 52 - 16
        setFrameOrigin(NSPoint(x: x, y: y))
```

Replace with:
```swift
        let x = visibleFrame.maxX - 300 - 16
        let y = visibleFrame.maxY - 110 - 16
        setFrameOrigin(NSPoint(x: x, y: y))
```

- [ ] **Step 7: Build — expect only ToastView.swift error about CapabilityToastView signature**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd/.claude/worktrees/epic-robinson" && make 2>&1 | grep -E "error:" | head -20
```

Expected: one error in `ToastView.swift` about `CapabilityToastView` receiving `capability:` but the caller now passes `match:`.

- [ ] **Step 8: Commit**

```bash
git add Sources/ToastWindow.swift
git commit -m "feat: update ToastWindow to pass SuggestionMatch through to CapabilityToastView"
```

---

### Task 7: Full redesign of CapabilityToastView in ToastView.swift

**Files:**
- Modify: `Sources/ToastView.swift`

This is the largest change — replace the entire `CapabilityToastView` struct.

Layout spec (from design doc):
```
┌──────────────────────────────────────────────── ×  ┐
│  [icon] [icon] [icon] [icon]                        │
│                                                     │
│  Launching a Threads campaign?          (13pt bold) │
│  AutoClawd can automate this · 4 steps  (11pt gray) │
│                                                     │
│                                   [Run now]  👎     │
└─────────────────────────────────────────────────────┘
  width: 300px   height: ~110px   corner radius: 14
```

- [ ] **Step 1a: Add `import AppKit` to the top of the file**

`ToastView.swift` currently starts with `import SwiftUI`. Add `import AppKit` on the line directly below it so `NSWorkspace` and `NSImage` are available:

Find:
```swift
import SwiftUI
```
Replace with:
```swift
import SwiftUI
import AppKit
```

- [ ] **Step 1b: Replace CapabilityToastView entirely**

Replace the entire `CapabilityToastView` struct (lines 1–73). The struct now begins after the two import lines added above, so only replace from the first `///` doc-comment down through the closing `}` of `CapabilityToastView`. The replacement block starts below (no `import` lines — those are handled by Step 1a):

```swift
/// Capability suggestion toast — shown in top-right corner when AppState.detectedSuggestion is set.
struct CapabilityToastView: View {
    let match: SuggestionMatch
    let onTap: () -> Void          // "Run now" button
    let onSnooze: () -> Void       // X button — not now (2h suppress)
    let onMarkIrrelevant: () -> Void // 👎 button — not relevant (session suppress)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ── Top row: icon strip + X ──
            HStack(alignment: .center, spacing: 0) {
                ToolIconStrip(capability: match.capability)
                Spacer()
                Button(action: onSnooze) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Glass.textTertiary)
                }
                .buttonStyle(.plain)
            }

            // ── Headline ──
            Text(match.contextualHeadline)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Glass.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            // ── Subtitle + action row ──
            HStack(alignment: .center) {
                Text("AutoClawd can automate this · \(match.capability.subWorkflows.count) steps")
                    .font(.system(size: 11))
                    .foregroundStyle(Glass.textSecondary)
                    .lineLimit(1)

                Spacer()

                GlassButton("Run now", action: onTap)

                Button(action: onMarkIrrelevant) {
                    Image(systemName: "hand.thumbsdown")
                        .font(.system(size: 12))
                        .foregroundStyle(Glass.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 300)
        .background(glassBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }

    @ViewBuilder
    private var glassBackground: some View {
#if NATIVE_GLASS_AVAILABLE
        if #available(macOS 26, *) {
            Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                LinearGradient(colors: [Color.white.opacity(0.10), Color.clear],
                               startPoint: .top, endPoint: .center)
            }
        }
#else
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
            LinearGradient(colors: [Color.white.opacity(0.10), Color.clear],
                           startPoint: .top, endPoint: .center)
        }
#endif
    }
}

/// Horizontal strip of small app icons derived from a capability's trigger apps and subworkflows.
private struct ToolIconStrip: View {
    let capability: Capability
    private let maxIcons = 4
    private let iconSize: CGFloat = 28
    private let overlap: CGFloat = 8   // each icon offset by 20px (28 - 8 = 20px visible)

    private var appNames: [String] {
        var names: [String] = []
        // From trigger apps
        names.append(contentsOf: capability.triggers.apps)
        // From subworkflow invocations (extract app names from known tools)
        for sw in capability.subWorkflows {
            if let inv = sw.invocation {
                let lower = inv.lowercased()
                if lower.contains("slack") { names.append("Slack") }
                else if lower.contains("sheets") || lower.contains("google") { names.append("Numbers") }
                else if lower.contains("github") { names.append("Xcode") }
            }
        }
        // Deduplicate while preserving order
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    private var displayNames: [String] { Array(appNames.prefix(maxIcons)) }
    private var extraCount: Int { max(0, appNames.count - maxIcons) }

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                ForEach(Array(displayNames.enumerated()), id: \.offset) { index, name in
                    AppIconView(appName: name, size: iconSize)
                        .offset(x: CGFloat(index) * (iconSize - overlap))
                }
                if extraCount > 0 {
                    Text("+\(extraCount)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Glass.textSecondary)
                        .frame(width: iconSize, height: iconSize)
                        .background(Circle().fill(Color.white.opacity(0.15)))
                        .offset(x: CGFloat(displayNames.count) * (iconSize - overlap))
                }
            }
            .frame(width: CGFloat(min(appNames.count, maxIcons + (extraCount > 0 ? 1 : 0))) * (iconSize - overlap) + overlap, height: iconSize)
        }
    }
}

/// Single app icon circle — uses NSWorkspace app icon with SF Symbol fallback.
private struct AppIconView: View {
    let appName: String
    let size: CGFloat

    var body: some View {
        Group {
            if let nsImage = appIcon(for: appName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(Glass.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
    }

    private func appIcon(for name: String) -> NSImage? {
        // Look up installed app by display name
        let workspace = NSWorkspace.shared
        if let url = workspace.urlForApplication(withBundleIdentifier: bundleID(for: name))
            ?? findAppURL(name: name) {
            let icon = workspace.icon(forFile: url.path).copy() as! NSImage  // copy before mutating — NSWorkspace returns a shared cached image
            icon.size = NSSize(width: size * 2, height: size * 2)  // retina
            return icon
        }
        return nil
    }

    private func bundleID(for name: String) -> String {
        switch name.lowercased() {
        case "xcode":    return "com.apple.dt.Xcode"
        case "vs code":  return "com.microsoft.VSCode"
        case "cursor":   return "com.todesktop.230313mzl4w4u92"
        case "figma":    return "com.figma.Desktop"
        case "canva":    return "com.canva.DesktopApp"
        case "linear":   return "com.linear"
        case "notion":   return "notion.id"
        case "slack":    return "com.tinyspeck.slackmacgap"
        case "threads":  return "com.burbn.instagram.Threads"
        case "twitter":  return "com.twitter.twitter-mac"
        case "numbers":  return "com.apple.iWork.Numbers"
        case "excel":    return "com.microsoft.Excel"
        default:         return ""
        }
    }

    private func findAppURL(name: String) -> URL? {
        let paths = ["/Applications", "/System/Applications", "/Applications/Utilities"]
        for path in paths {
            let url = URL(fileURLWithPath: path).appendingPathComponent("\(name).app")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}
```

Keep `ToastView` (the legacy log toast, lines 76–124) unchanged below the new `CapabilityToastView`.

- [ ] **Step 2: Build clean**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd/.claude/worktrees/epic-robinson" && make 2>&1 | tail -30
```

Expected: **clean build — zero errors**. If there are errors, fix them before committing.

**Common errors to expect and fix:**
- `GlassButton` takes different arguments — check `LiquidGlass.swift` for the exact `GlassButton` initialiser. If `GlassButton("Run now", action: onTap)` doesn't match, use `Button("Run now", action: onTap)` styled as `GlassButton` (check AgentsView.swift for usage pattern).
- `NSWorkspace.urlForApplication(withBundleIdentifier:)` — returns `URL?` on macOS 10.15+. If unavailable, use `NSWorkspace.shared.absolutePathForApplication(withBundleIdentifier:)` and wrap in `URL(fileURLWithPath:)`.
- `import AppKit` at the top is needed for `NSWorkspace`, `NSImage`. The file already imports SwiftUI — add AppKit if not present.

- [ ] **Step 3: Verify success criteria manually**

```bash
# Launch the app
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd/.claude/worktrees/epic-robinson" && make run
```

Verify each criterion from the spec:
1. [ ] Toast only appears when OCR has a clear app or URL trigger (score >= 3)
2. [ ] Headline reads like "Launching a Threads campaign?" — never just a capability name
3. [ ] X button (top-right) dismisses and suppresses the same capability; it does not reappear within 2 hours
4. [ ] 👎 button suppresses for the session; same capability doesn't reappear until relaunch
5. [ ] Tool icons render correctly — circles with app icons for all 7 built-in capabilities
6. [ ] `make` build passes — zero errors, zero new warnings
7. [ ] In Learn Mode: `buildCapability()` still correctly populates `session.suggestedCapabilities` after the type change

Quick smoke test for criterion 7:
```swift
// In AppState, test FUCBC path:
// Switch to Learn Mode, wait for a session to exist, then:
// print(learnModeService.session?.suggestedCapabilities.count)
// Expected: 0–5 Capability values (not SuggestionMatch)
```

- [ ] **Step 4: Commit**

```bash
git add Sources/ToastView.swift
git commit -m "feat: redesign CapabilityToastView — contextual headline, icon strip, snooze/irrelevant dismiss"
```

---

## Final Integration Build

- [ ] **Confirm final clean build**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd/.claude/worktrees/epic-robinson" && make 2>&1 | tail -10
```

Expected output ends with: `** BUILD SUCCEEDED **` or equivalent `make` success output.

- [ ] **Summary commit if needed**

If any uncommitted changes remain:
```bash
git status
git add -A
git commit -m "feat: smarter suggestions complete — SuggestionMatch pipeline, score>=3, contextual toasts"
```

---

## Files Changed Summary

| File | What changes |
|------|-------------|
| `Sources/LearnModeModels.swift` | Add `MatchSignal` enum; add `SuggestionMatch` struct; add `contextualQuestionTemplate` field to `Capability` + `CodingKeys` + `init(from:)` + memberwise `init` |
| `Sources/CapabilityStore.swift` | `suggest()` returns `[SuggestionMatch]`; score threshold >= 3; `MatchSignal` collection per capability; `resolveHeadline()` helper; `snooze()` + `markIrrelevant()` + in-memory dismissal dicts; update all 7 `builtinCapabilities` with `contextualQuestionTemplate:` |
| `Sources/AppState.swift` | `detectedCapability: Capability?` → `detectedSuggestion: SuggestionMatch?`; update auto-trigger call site (~line 651); update `executeCapability()` and `dismissDetectedCapability()` |
| `Sources/LearnModeService.swift` | `suggestCapabilities()` return type `[Capability]` → `[SuggestionMatch]`; `buildCapability()` call site maps `[SuggestionMatch]` → `[Capability]` before assigning to `session.suggestedCapabilities` |
| `Sources/AppDelegate.swift` | Update `$detectedCapability` Combine sink → `$detectedSuggestion`; `showCapabilityToast(_ capability:)` → `showCapabilityToast(_ match:)`; update `canvasForCurrentMode` block; `CapabilitySuggestionCanvasView` call site passes `match.capability` — `CapabilitySuggestionCanvasView` itself does **not** change |
| `Sources/ToastWindow.swift` | `CapabilityToastModel` holds `SuggestionMatch?`; `showCapability(_:onSnooze:onMarkIrrelevant:)` new signature; window resized to 300×110 |
| `Sources/ToastView.swift` | Add `import AppKit`; full redesign of `CapabilityToastView` — accepts `SuggestionMatch`; `ToolIconStrip` + `AppIconView`; contextual headline; subtitle with step count; X + 👎 + Run now buttons |
