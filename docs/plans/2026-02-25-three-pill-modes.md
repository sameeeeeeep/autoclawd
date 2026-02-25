# Three Pill Modes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Ambient Intelligence / Transcription / AI Search modes to the pill, switchable by tapping the left icon.

**Architecture:** `PillMode` enum in AppState, tap-to-cycle icon on left of pill, ChunkManager routes post-transcription audio to extraction / paste / Ollama-Q&A based on current mode.

**Tech Stack:** Swift 6, CoreGraphics (CGEventPost for paste), NSPasteboard, OllamaService (existing), SwiftUI

**Design doc:** `docs/plans/2026-02-25-three-pill-modes-design.md`

---

## Task 1: PillMode enum + Logger components

**Files:**
- Create: `Sources/PillMode.swift`
- Modify: `Sources/Logger.swift`

**Step 1: Create Sources/PillMode.swift**

```swift
import Foundation

enum PillMode: String, CaseIterable {
    case ambientIntelligence = "ambientIntelligence"
    case transcription       = "transcription"
    case aiSearch            = "aiSearch"

    var displayName: String {
        switch self {
        case .ambientIntelligence: return "Ambient"
        case .transcription:       return "Transcribe"
        case .aiSearch:            return "AI Search"
        }
    }

    var icon: String {
        switch self {
        case .ambientIntelligence: return "brain"
        case .transcription:       return "text.cursor"
        case .aiSearch:            return "magnifyingglass"
        }
    }

    func next() -> PillMode {
        let all = PillMode.allCases
        let idx = all.firstIndex(of: self)!
        return all[(idx + 1) % all.count]
    }
}
```

**Step 2: Add log components to Logger.swift** — add after `case ui`:

```swift
case paste = "PASTE"
case qa    = "QA"
```

Also add them to the Logs tab picker in `MainPanelView.swift` (the array in `LogsTabView`):
```swift
// change the array in LogsTabView from:
[LogComponent.audio, .transcribe, .extract, .world, .todo, .clipboard, .system, .ui]
// to:
[LogComponent.audio, .transcribe, .extract, .world, .todo, .clipboard, .paste, .qa, .system, .ui]
```

**Step 3: Build** — `make` in project root. Expected: `Built build/AutoClawd.app`

**Step 4: Commit** — `git add Sources/PillMode.swift Sources/Logger.swift Sources/MainPanelView.swift && git commit -m "feat: add PillMode enum and paste/qa log components"`

---

## Task 2: Add pillMode to AppState

**Files:**
- Modify: `Sources/AppState.swift`

**Step 1: Add to @Published state (after `audioRetentionDays`):**

```swift
@Published var pillMode: PillMode {
    didSet {
        UserDefaults.standard.set(pillMode.rawValue, forKey: "pillMode")
        chunkManager.pillMode = pillMode
        Log.info(.system, "Pill mode → \(pillMode.rawValue)")
    }
}
```

**Step 2: Add `cyclePillMode()` method:**

```swift
func cyclePillMode() {
    pillMode = pillMode.next()
}
```

**Step 3: In `init()`, initialise pillMode before other properties** (add after `let settings = SettingsManager.shared`):

```swift
let savedMode = UserDefaults.standard.string(forKey: "pillMode")
    .flatMap { PillMode(rawValue: $0) } ?? .ambientIntelligence
pillMode = savedMode
```

**Step 4: Build** — `make`. Expected: `Built build/AutoClawd.app`

**Step 5: Commit** — `git add Sources/AppState.swift && git commit -m "feat: add pillMode to AppState with UserDefaults persistence"`

---

## Task 3: TranscriptionPasteService

**Files:**
- Create: `Sources/TranscriptionPasteService.swift`

**Step 1: Create the file**

```swift
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
```

**Step 2: Build** — `make`. Expected: `Built build/AutoClawd.app`

**Step 3: Commit** — `git add Sources/TranscriptionPasteService.swift && git commit -m "feat: add TranscriptionPasteService (CGEventPost paste)"`

---

## Task 4: QAStore + QAService

**Files:**
- Create: `Sources/QAStore.swift`
- Create: `Sources/QAService.swift`

**Step 1: Create Sources/QAStore.swift**

```swift
import Foundation

// MARK: - QAItem

struct QAItem: Identifiable {
    let id: String
    let question: String
    let answer: String
    let timestamp: Date

    init(question: String, answer: String) {
        self.id        = UUID().uuidString
        self.question  = question
        self.answer    = answer
        self.timestamp = Date()
    }
}

// MARK: - QAStore

@MainActor
final class QAStore: ObservableObject {
    @Published private(set) var items: [QAItem] = []

    func append(question: String, answer: String) {
        items.insert(QAItem(question: question, answer: answer), at: 0)
    }
}
```

**Step 2: Create Sources/QAService.swift**

```swift
import Foundation

// MARK: - QAService

final class QAService: @unchecked Sendable {
    private let ollama: OllamaService

    init(ollama: OllamaService) {
        self.ollama = ollama
    }

    func answer(question: String) async throws -> String {
        let prompt = """
Answer this question concisely in 1-3 sentences. If you don't know, say so.

Question: \(question)
"""
        Log.info(.qa, "Question: \"\(question)\"")
        let t0 = Date()
        let answer = try await ollama.generate(prompt: prompt, numPredict: 512)
        let elapsed = Date().timeIntervalSince(t0)
        Log.info(.qa, "Answer in \(String(format: "%.1f", elapsed))s: \"\(String(answer.prefix(80)))\"")
        return answer
    }
}
```

**Note:** This requires Task 4 from the intelligence pipeline plan (adding `numPredict` to OllamaService). If that isn't done yet, either do that task first or temporarily use `ollama.generate(prompt: prompt)` without numPredict.

**Step 3: Build** — `make`. Expected: `Built build/AutoClawd.app`

**Step 4: Commit** — `git add Sources/QAStore.swift Sources/QAService.swift && git commit -m "feat: add QAStore and QAService"`

---

## Task 5: Wire ChunkManager for mode-based routing

**Files:**
- Modify: `Sources/ChunkManager.swift`

**Step 1: Add mode + new service properties** (after `private var chunkStartTime: Date?`):

```swift
var pillMode: PillMode = .ambientIntelligence
var pasteService: TranscriptionPasteService?
var qaService: QAService?
var qaStore: QAStore?
```

**Step 2: Update `configure()` signature and body** to accept the new services:

```swift
func configure(
    transcriptionService: TranscriptionService,
    extractionService: ExtractionService,
    transcriptStore: TranscriptStore,
    pasteService: TranscriptionPasteService,
    qaService: QAService,
    qaStore: QAStore
) {
    self.transcriptionService = transcriptionService
    self.extractionService    = extractionService
    self.transcriptStore      = transcriptStore
    self.pasteService         = pasteService
    self.qaService            = qaService
    self.qaStore              = qaStore
}
```

**Step 3: In both `runOneChunk()` and `pause()` — capture pillMode and services before dispatching:**

In `runOneChunk()`, add these captures (alongside the existing `capturedTranscriptionService` etc.):
```swift
let capturedPillMode    = pillMode
let capturedPasteService = pasteService
let capturedQAService   = qaService
let capturedQAStore     = qaStore
```

Pass them to `processChunk()`.

Do the same in `pause()`.

**Step 4: Update `processChunk()` signature:**

```swift
private func processChunk(
    index: Int,
    audioURL: URL,
    duration: Int,
    transcriptionService: TranscriptionService?,
    extractionService: ExtractionService?,
    transcriptStore: TranscriptStore?,
    pillMode: PillMode,
    pasteService: TranscriptionPasteService?,
    qaService: QAService?,
    qaStore: QAStore?
) async {
```

**Step 5: Replace the extraction block at the bottom of `processChunk()`** (after `onTranscriptReady` call) with mode routing:

```swift
switch pillMode {
case .ambientIntelligence:
    guard let extractionService else {
        Log.warn(.extract, "No extraction service configured")
        break
    }
    Log.info(.extract, "Chunk \(index): starting extraction")
    await extractionService.process(transcript: transcript)

case .transcription:
    guard let pasteService else { break }
    await MainActor.run { pasteService.paste(text: transcript) }

case .aiSearch:
    guard let qaService, let qaStore else { break }
    do {
        let answer = try await qaService.answer(question: transcript)
        await MainActor.run {
            qaStore.append(question: transcript, answer: answer)
            // Auto-copy answer to clipboard
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(answer, forType: .string)
            Log.info(.qa, "Answer copied to clipboard")
        }
    } catch {
        Log.error(.qa, "QA failed: \(error.localizedDescription)")
    }
}
```

**Step 6: Build** — `make`. Expected: `Built build/AutoClawd.app`

**Step 7: Commit** — `git add Sources/ChunkManager.swift && git commit -m "feat: route ChunkManager output by pillMode (ambient/transcription/aiSearch)"`

---

## Task 6: Wire AppState — create services + configure ChunkManager

**Files:**
- Modify: `Sources/AppState.swift`

**Step 1: Add service properties** (in the services section, after `extractionService`):

```swift
let qaStore = QAStore()
private let pasteService = TranscriptionPasteService()
private let qaService: QAService
```

**Step 2: In `init()`, initialise qaService** (after `extractionService = ...`):

```swift
qaService = QAService(ollama: OllamaService())
```

Also set chunkManager.pillMode right after creating chunkManager:
```swift
chunkManager.pillMode = pillMode
```

**Step 3: Update `reconfigureChunkManager()`** to pass the new services:

```swift
private func reconfigureChunkManager() {
    guard let ts = transcriptionService else { return }
    chunkManager.configure(
        transcriptionService: ts,
        extractionService: extractionService,
        transcriptStore: transcriptStore,
        pasteService: pasteService,
        qaService: qaService,
        qaStore: qaStore
    )
}
```

**Step 4: Build** — `make`. Expected: `Built build/AutoClawd.app`

**Step 5: Commit** — `git add Sources/AppState.swift && git commit -m "feat: wire QAStore/QAService/pasteService into AppState + ChunkManager"`

---

## Task 7: QAView

**Files:**
- Create: `Sources/QAView.swift`

**Step 1: Create the file**

```swift
import SwiftUI

// MARK: - QAView

struct QAView: View {
    @ObservedObject var store: QAStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabHeader("AI Search") { EmptyView() }
            Divider()

            if store.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("Switch to AI Search mode and ask a question out loud")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(store.items) { item in
                    QAItemRow(item: item)
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - QAItemRow

struct QAItemRow: View {
    let item: QAItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.answer, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Text(item.question)
                .font(.custom("JetBrains Mono", size: 10))
                .foregroundStyle(.secondary)

            Text(item.answer)
                .font(.system(size: 12))
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
}
```

**Step 2: Build** — `make`. Expected: `Built build/AutoClawd.app`

**Step 3: Commit** — `git add Sources/QAView.swift && git commit -m "feat: add QAView for AI Search results"`

---

## Task 8: Add Q&A tab to MainPanelView

**Files:**
- Modify: `Sources/MainPanelView.swift`

**Step 1: Add to PanelTab enum** (after `.logs`):

```swift
case qa = "AI Search"
```

**Step 2: Add icon:**

```swift
case .qa: return "magnifyingglass"
```

**Step 3: Add to content switch:**

```swift
case .qa: QAView(store: appState.qaStore)
```

**Step 4: Build** — `make`. Expected: `Built build/AutoClawd.app`

**Step 5: Commit** — `git add Sources/MainPanelView.swift && git commit -m "feat: add AI Search tab to main panel"`

---

## Task 9: Update PillView — tappable mode icon

**Files:**
- Modify: `Sources/PillView.swift`

**Step 1: Add `onCycleMode` callback property** (alongside the other `let` callbacks):

```swift
let onCycleMode: () -> Void
let pillMode: PillMode
```

**Step 2: Replace `stateIcon` with a tappable `modeButton`:**

```swift
private var modeButton: some View {
    Button(action: onCycleMode) {
        Image(systemName: pillMode.icon)
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(state == .paused ? 0.4 : 1.0))
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
}
```

**Step 3: In `fullPillView`, replace `stateIcon` with `modeButton`:**

```swift
private var fullPillView: some View {
    HStack(spacing: 8) {
        modeButton        // ← was stateIcon
        ZStack {
            waveformBars
            if state == .processing { scanLine }
        }
        .frame(width: 100, height: 24)
        .clipShape(Rectangle())
        stateLabel
        pausePlayButton
    }
    ...
}
```

**Step 4: Remove the old `stateIcon` computed property** (it's replaced by modeButton).

**Step 5: Update context menu** to show current mode and add mode switch option:

```swift
private var contextMenu: some View {
    Group {
        Button("Open Panel") { onOpenPanel() }
        Button(state == .paused ? "Resume Listening" : "Pause Listening") { onTogglePause() }
        Divider()
        Button("Mode: \(pillMode.displayName) → \(pillMode.next().displayName)") { onCycleMode() }
        Divider()
        Button("View Logs") { onOpenLogs() }
    }
}
```

**Step 6: Build** — `make`. Expected: `Built build/AutoClawd.app`

**Step 7: Commit** — `git add Sources/PillView.swift && git commit -m "feat: replace stateIcon with tappable mode button in PillView"`

---

## Task 10: Wire PillView mode cycling in PillWindow/AppDelegate

**Files:**
- Modify: `Sources/PillWindow.swift` (or wherever PillView is instantiated)

**Step 1: Find where PillView is created** — search for `PillView(` in the codebase.

**Step 2: Add `pillMode` and `onCycleMode` arguments:**

```swift
PillView(
    state: appState.pillState,
    audioLevel: appState.audioLevel,
    pillMode: appState.pillMode,        // ← add
    onOpenPanel: { ... },
    onTogglePause: { appState.toggleListening() },
    onOpenLogs: { ... },
    onToggleMinimal: { ... },
    onCycleMode: { appState.cyclePillMode() }   // ← add
)
```

**Step 3: Build** — `make`. Expected: `Built build/AutoClawd.app`

**Step 4: Commit** — `git add Sources/PillWindow.swift && git commit -m "feat: wire pillMode + onCycleMode in PillWindow"`

---

## Task 11: Smoke Test

**Step 1: Restart app**
```bash
pkill -x AutoClawd; sleep 1
open "/Users/sameeprehlan/Documents/Claude Code/autoclawd/build/AutoClawd.app"
```

**Step 2: Test mode cycling**
- Tap the left icon on the pill
- Expected: icon changes brain → text.cursor → magnifyingglass → brain
- Check log: `[SYSTEM] Pill mode → transcription`

**Step 3: Test Transcription mode**
- Switch to transcription mode (text.cursor icon)
- Click into a text editor (TextEdit, Notes, etc.)
- Speak for 5–10 seconds
- Expected: transcript text pasted into the editor
- If Accessibility not granted: System Settings prompt appears; grant it then retry

**Step 4: Test AI Search mode**
- Switch to AI Search mode (magnifyingglass icon)
- Say "What is the currency of Thailand?"
- Open main panel → AI Search tab
- Expected: question + answer appear, answer copied to clipboard
- Check log: `[QA] Question: "What is the currency of Thailand?"`

**Step 5: Verify Ambient mode still works**
- Switch back to brain icon
- Speak for a chunk
- World model / extraction still runs as before

**Step 6: Final commit**
```bash
git add -A && git commit -m "feat: complete three pill modes (ambient/transcription/aiSearch)"
```

---

## Files Summary

| File | Action |
|------|--------|
| `Sources/PillMode.swift` | NEW |
| `Sources/TranscriptionPasteService.swift` | NEW |
| `Sources/QAStore.swift` | NEW |
| `Sources/QAService.swift` | NEW |
| `Sources/QAView.swift` | NEW |
| `Sources/Logger.swift` | ADD .paste, .qa components |
| `Sources/AppState.swift` | ADD pillMode, cyclePillMode, qaStore, pasteService, qaService |
| `Sources/ChunkManager.swift` | ADD pillMode routing, new service deps |
| `Sources/PillView.swift` | REPLACE stateIcon with modeButton |
| `Sources/PillWindow.swift` | WIRE pillMode + onCycleMode |
| `Sources/MainPanelView.swift` | ADD .qa tab + log filter update |
