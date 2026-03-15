# Suggestion Intelligence Architecture
## Where We Are vs. Where We Need to Be

---

## Current State (after this session)

### What's Built
1. **Phase 1 — Sync capability scoring** (`evaluate()`)
   - Every OCR frame: keyword / URL / app matching against CapabilityStore
   - Zero inference. Zero RAM. Instant.
   - Returns `.capability` or nil. 30s cooldown on repeat.

2. **Phase 2a — Session-end Haiku pass** (`sessionEndSuggest()`)
   - Fires once after 10s voice silence
   - Full context: transcript + full OCR + clipboard + world model + URLs
   - Returns `.task` (≥0.80), `.question` (0.65–0.79), or nil
   - Model: Claude Haiku via `claude --print` (OAuth)

3. **Phase 2b — Screen-triggered Haiku** (`scheduleScreenSuggestion()`)
   - Fires on OCR change with 3-min debounce
   - Same rich context as 2a
   - Fills gap for silent screen work (no voice session → was getting nothing)

4. **Interactive question toast** (`.question` SuggestionItem)
   - When Haiku is medium-confidence, surfaces a question with 2–3 option buttons
   - User taps → `handleSuggestionQuestionOption()` → executes chosen action
   - Stays on screen 10s (vs 5s for tasks)

### Known Gaps
- No vision input (OCR text only — misses visual layout, images, progress bars)
- No real-time event detection (polling OCR, not reacting to events)
- Voice answers to questions not yet wired (buttons only)
- No feedback loop (dismissed suggestions don't teach the system)
- World model not project-scoped before Haiku call (sends all of it, not the relevant project)

---

## What Cofia Does Differently

Cofia-quality ambient suggestions require three things we're partially missing:

### 1. Event-Driven, Not Timer-Driven

**Current:** OCR fires every 30s, Haiku fires every 3 min on OCR change.
**Cofia-level:** React to meaningful events — new message, app focus change, content scroll-stop.

**Gap:** We poll. They react.

**Fix:**
- Detect message arrival via OCR diff (previous vs. current OCR — new content detected)
- App-switch already triggers OCR (`captureOnAppSwitch`) — wire this to also check for Haiku trigger
- Dwell detection: user has been on same content >15s → fire Haiku (they're reading/thinking)

### 2. Vision Input

**Current:** OCR text → Haiku text prompt. Claude sees words, not layout.
**Cofia-level:** Screenshot → vision model → structured understanding.

**Gap:** We strip visual context. A screenshot shows whether a Slack message is urgent (red dot),
whether a form is half-filled, whether a progress bar is stuck. OCR text doesn't.

**Fix (two paths):**

**Path A — Haiku Vision via Anthropic API** (higher quality)
```
screenshot (PNG/JPEG) → base64 → Anthropic API (haiku, vision=true)
→ structured JSON suggestion
```
Cost: ~$0.003/call (haiku input tokens for image ≈ 1000 tokens at 1.5px/token)
Requires: direct API call (not `claude --print`), ANTHROPIC_API_KEY

**Path B — Haiku Vision via `claude --print` with image attachment**
The Claude CLI may support `--image` flag or similar. Less tested.

**Recommended:** Path A. We already have ANTHROPIC_API_KEY in SettingsManager.
Build `ClaudeVisionService` that makes direct API calls with screenshot + OCR text.

### 3. Corrections Feed the System

**Current:** "Not relevant" → dismiss. System learns nothing.
**Cofia-level:** Every dismissal + selection teaches the model what this user cares about.

**Fix:**
- On `handleSuggestionQuestionOption("Not relevant", question)` → log to WorldModel:
  `"[context snippet] → user dismissed as not relevant"`
- On positive selection → log to WorldModel:
  `"[context snippet] → user selected: [option]"`
- Next Haiku call includes recent feedback from world model → personalizes over time

---

## Suggested Architecture Roadmap

### Phase A: Event-Driven Triggers (highest ROI, no new services)
```
AppSwitch event → immediate Haiku trigger (debounce: 60s)
OCR diff > 30% change → Haiku trigger (debounce: 90s)
Dwell: same OCR for 20s → Haiku trigger (debounce: 5 min)
```
Implementation: Add `screenDiff()` comparison in ScreenVisionAnalyzer, fire callbacks.

### Phase B: Vision Input (biggest quality jump)
```swift
// ClaudeVisionService.swift
struct ClaudeVisionService {
    func analyze(screenshot: CGImage, ocrText: String, context: SuggestionContext) async -> SuggestionItem?
    // POST to api.anthropic.com/v1/messages with image + text
    // model: claude-haiku-4-5-20251001 (supports vision)
    // Returns same SuggestionItem types
}
```
Replace Haiku text prompt with vision prompt when screenshot is available.
ScreenVisionAnalyzer already has `captureNow()` → pass CGImage directly.

### Phase C: Voice Answers to Questions
```
Question toast appears: "Should I reply to Alice or fix the bug?"
User speaks: "reply to Alice"
SFSpeech transcribes → matches against question options
→ auto-selects option without button tap
```
Implementation: When `pendingQuestion` is set, monitor `liveTranscriptText` for option matches.
First ~10s of next speech chunk → check if it matches an option label fuzzy.

### Phase D: Corrections → World Model
```swift
// In AppState.handleSuggestionQuestionOption():
if option.lowercased() == "not relevant" {
    worldModelService.appendFeedback(
        context: "User dismissed suggestion about: \(question.question)",
        app: question.context.app ?? "unknown"
    )
}
// In SuggestionPipeline.buildPrompt():
// Include recent feedback section from world model
```

### Phase E: Project-Scoped World Model in Prompts
Currently: sends first 1500 chars of global world model.
Better: detect active project from OCR/app, extract only that project's world model section.
```swift
let relevantWorldModel = worldModelService.excerpt(forProject: detectedProject, maxChars: 2000)
```

---

## OCR Improvement: OCR Diff Detection

The 30-char "last OCR hash" check is too coarse. Better:

```swift
struct OCRDiff {
    let addedLines: [String]     // new text not in previous OCR
    let removedLines: [String]
    let changeFraction: Double   // 0.0–1.0
}

func diff(previous: String, current: String) -> OCRDiff {
    let prevLines = Set(previous.components(separatedBy: .newlines))
    let currLines = Set(current.components(separatedBy: .newlines))
    let added   = currLines.subtracting(prevLines)
    let removed = prevLines.subtracting(currLines)
    let fraction = Double(added.count + removed.count) / Double(max(prevLines.count, 1))
    return OCRDiff(addedLines: Array(added), removedLines: Array(removed), changeFraction: fraction)
}
```

Pass `diff.addedLines` (the NEW content) to Haiku instead of full OCR → much higher signal/noise.

---

## AI Canvas Integration

The user requested: "leverage AI canvas to ask qs users can answer with voice/selecting options"

### Current: Toast-only questions
Question appears in top-right toast, user taps a button.

### Target: AI Canvas as context workspace
When a question is pending, open AI Canvas and show:
```
┌─────────────────────────────────────────────┐
│ ✦ AutoClawd noticed                         │
│                                              │
│ "Should I reply to Alice's message           │
│  about the Q3 report or open the            │
│  report in Numbers?"                         │
│                                              │
│  [Reply to Alice]  [Open in Numbers]         │
│  [Not relevant]                             │
│                                              │
│  Or speak your answer...                    │
│  ▶ "open the report"                        │← live voice match
└─────────────────────────────────────────────┘
```

Implementation:
1. Add `pendingQuestion: SuggestionQuestion?` to AppState
2. When question fires: open AI Canvas tab via `appState.activeTab = .canvas`
3. AICanvasView shows question card at top when `pendingQuestion != nil`
4. Voice: monitor `liveTranscriptText` changes while question visible

---

## Summary: Priority Order

| Priority | Feature | Impact | Effort |
|---|---|---|---|
| 1 | App-switch → immediate Haiku trigger | High | Low |
| 2 | OCR diff → pass new content only | High | Medium |
| 3 | Vision input (ClaudeVisionService) | Very High | Medium |
| 4 | Voice answers to questions | High | Medium |
| 5 | Corrections → World Model | Medium | Low |
| 6 | AI Canvas question workspace | Medium | High |
| 7 | Project-scoped world model | Medium | Low |
| 8 | Dwell detection (20s pause) | Medium | Medium |

The single biggest improvement available is **#3 Vision Input** — going from OCR text
to actual screenshots means Claude sees what the user sees, not just the words.
