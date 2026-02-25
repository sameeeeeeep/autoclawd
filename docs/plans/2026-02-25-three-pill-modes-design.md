# Three Pill Modes Design
Date: 2026-02-25

## Problem

The pill currently has one mode: ambient intelligence (listen → transcribe → extract). Users need two additional modes — one for direct speech-to-text paste, one for on-the-fly AI questions — all switchable directly from the pill without opening any panel.

## Solution

Add a `PillMode` enum with three cases. A tappable left icon in the pill cycles through modes on each tap. Each mode changes how transcribed audio is routed after Groq returns the text.

---

## Mode Definitions

### 1. Ambient Intelligence (existing)
- Icon: `brain`
- Behavior: unchanged — transcribe → run extraction pipeline (Pass 1/2)
- Label: `LIVE` / `PROC` / `PAUSE` (existing)

### 2. Transcription
- Icon: `text.cursor`
- Behavior: transcribe → paste raw text into the currently focused text field
- Paste method: `CGEventPost` simulating Cmd+V (requires Accessibility permission)
- Fallback: if Accessibility not granted, copy to clipboard and show `COPIED` label flash in pill
- Label: `LIVE` while listening, `PASTE` briefly after paste, then back to `LIVE`

### 3. AI Search
- Icon: `magnifyingglass`
- Behavior: transcribe → send to Ollama with Q&A prompt → display answer in Q&A tab + auto-copy to clipboard
- Ollama prompt: simple, direct — "Answer this question concisely: {transcript}"
- numPredict: 512 (answers should be short)
- Label: `LIVE` while listening, `SRCH` while Ollama running, `DONE` briefly after answer

---

## Mode Switcher UI

**Tap-to-cycle**: tapping the left mode icon cycles Ambient → Transcription → AI Search → Ambient.

Full pill layout (left to right):
```
[modeIcon] [waveformBars+scanLine] [stateLabel] [pausePlayButton]
```

Mode persists to `UserDefaults` key `"pillMode"` so it survives app restarts.

---

## Data Flow per Mode

```
Mic → AudioRecorder → ChunkManager → Groq transcription
                                          ↓
                              switch pillMode
                              ├── .ambientIntelligence → ExtractionService.classifyChunk()
                              ├── .transcription       → TranscriptionPasteService.paste()
                              └── .aiSearch            → QAService.answer() → QAStore.append()
```

---

## New Components

### TranscriptionPasteService
- `paste(text: String)` — sets NSPasteboard, then CGEventPost Cmd+V keydown+keyup
- `isAccessibilityGranted: Bool` — checks AXIsProcessTrustedWithOptions
- If not granted: just copies to clipboard (paste side-effect skipped)

### QAService
- `answer(question: String) async throws -> String`
- Wraps OllamaService with a focused Q&A prompt
- numPredict: 512

### QAStore
- `@MainActor class QAStore: ObservableObject`
- `@Published var items: [QAItem]` (in-memory, no persistence needed v1)
- `struct QAItem: Identifiable { id, question, answer, timestamp }`
- `append(question:, answer:)`

### QAView
- List of QAItems, newest first
- Each row: question in small caption, answer in body text, timestamp, copy button
- Empty state: "Say something in AI Search mode"

---

## Files Changed / Created

| File | Change |
|------|--------|
| `Sources/TranscriptionPasteService.swift` | NEW |
| `Sources/QAService.swift` | NEW |
| `Sources/QAStore.swift` | NEW |
| `Sources/QAView.swift` | NEW |
| `Sources/AppState.swift` | Add `pillMode`, `cyclePillMode()`, wire QAStore + QAService |
| `Sources/PillView.swift` | Add tappable mode icon on left |
| `Sources/ChunkManager.swift` | Route post-transcription by pillMode |
| `Sources/MainPanelView.swift` | Add `.qa` tab |

---

## Logging

```
[SYSTEM] Pill mode changed: ambientIntelligence → transcription
[PASTE]  Pasted 42 chars to frontmost app (Accessibility granted)
[PASTE]  Accessibility not granted — copied to clipboard instead
[QA]     Question: "What is the currency of Thailand?"
[QA]     Answer received in 3.2s: "Thai Baht (THB)..."
```
