# AutoClawd World Model & Intelligence Layer Design
**Date:** 2026-02-25
**Status:** Approved

---

## Overview

Eight interconnected features that transform AutoClawd from a transcription tool into a
spatially and temporally aware personal intelligence layer. The core idea: every recording
session is anchored to a place, a time, and the people present — building a growing "world
model" the AI can draw on.

---

## Features In Scope

1. User-provided context (free-form + conversational profile builder)
2. TTS voice output (AVSpeechSynthesizer, ≤10 words)
3. Glass pill appearance modes (frosted / transparent + state-reactive)
4. Global hotkeys (⌃Space = transcribe, ⌃R = toggle mic)
5. Sentence-aware chunk batching (10–30s range)
6. Location awareness via WiFi SSID
7. People tagging (manual hint + AI transcript inference)
8. World model canvas (timeline + mind map)

---

## Section 1: Data Layer

### Storage Location
`~/Library/Application Support/AutoClawd/`
- `autoclawd.db` — SQLite database
- `transcripts/<session-id>.txt` — flat transcript files, one chunk per line with timestamps
- `embeddings/<session-id>.vec` — Ollama embedding vectors (phase 2, not required for v1)

### SQLite Schema

```sql
-- One row per recording session
CREATE TABLE sessions (
  id            TEXT PRIMARY KEY,   -- UUID
  started_at    INTEGER NOT NULL,   -- Unix timestamp
  ended_at      INTEGER,
  wifi_ssid     TEXT,               -- Raw SSID at session start
  place_id      TEXT,               -- FK → places.id
  transcript_path TEXT              -- Relative path to .txt file
);

-- WiFi SSID → user-labeled place
CREATE TABLE places (
  id            TEXT PRIMARY KEY,
  wifi_ssid     TEXT UNIQUE NOT NULL,
  name          TEXT NOT NULL,      -- "Philz Coffee", "Home", "Office"
  created_at    INTEGER NOT NULL
);

-- Known people
CREATE TABLE people (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  aliases       TEXT               -- JSON array: ["Sarah", "S", "Sar"]
);

-- Who was present in each session
CREATE TABLE session_people (
  session_id    TEXT NOT NULL,
  person_id     TEXT NOT NULL,
  source        TEXT NOT NULL,     -- "manual" | "inferred"
  PRIMARY KEY (session_id, person_id)
);

-- AI-extracted topics per session
CREATE TABLE topics (
  id            TEXT PRIMARY KEY,
  session_id    TEXT NOT NULL,
  label         TEXT NOT NULL,     -- "API deadline", "React architecture"
  confidence    REAL NOT NULL
);

-- Singleton user profile
CREATE TABLE user_profile (
  id            INTEGER PRIMARY KEY CHECK (id = 1),
  context_blob  TEXT,              -- Free-form text built by profile chat
  updated_at    INTEGER
);
```

### WiFi Location Detection
- `CNCopyCurrentNetworkInfo` polled every 30 seconds
- On match in `places` table → sets `place_id` for current session
- On unrecognised SSID → one-time prompt toast: *"You're on 'BlueBotWifi' — what should I call this place?"*
- iPhone hotspot (e.g. `"Sameep's iPhone"`) → auto-tagged as `mobile`, place label = `"Mobile"`
- No GPS required; no location permissions beyond WiFi info entitlement

---

## Section 2: Intelligence Pipeline

### Chunk Batching (ChunkBatcher)
New `ChunkBatcher` component sits between `AudioRecorder` and Groq Whisper transcription:

- Accumulates raw audio
- Monitors VAD silence gaps (≥0.8s pause = candidate cut point)
- **Flush rules:**
  - Flush if silence detected AND chunk duration ≥ 10s
  - Force-flush at 30s regardless of silence
- Each flushed chunk sent to Groq Whisper independently
- Appended to `transcripts/<session-id>.txt` with timestamp prefix

### Context Injection
Every LLM call in `AppContextService` prepends a structured context block:

```
[USER CONTEXT]
{user_profile.context_blob}

[CURRENT SESSION]
Location: {place.name} | Time: {formatted datetime}
Present: {people list with source tags}

[RECENT SESSIONS — last 3]
{date} at {place} — {first 80 chars of transcript}
{date} at {place} — {first 80 chars of transcript}
{date} at {place} — {first 80 chars of transcript}
```

This block is injected before the existing app context capture in `AppContextService`.

### User Profile Chat
- New `ProfileChatView` sheet, accessible from Settings
- On first open: greeting prompt *"Tell me about yourself — what do you do, where do you work, who do you work with?"*
- User types free-form response
- Groq LLM asks up to 3 targeted follow-up questions to fill gaps
- After final answer, LLM synthesises a compact `context_blob` (≤300 words) and writes to `user_profile`
- User can re-open anytime to update; new blob replaces old

### People Tagging
- After each session ends, a lightweight async LLM pass over the full transcript
- Extracts proper names → matches against `people` table (fuzzy match on aliases)
- New names → creates `people` row, writes `session_people` with `source = "inferred"`
- Quiet toast notification: *"Tagged: Sarah, John — correct?"* with edit affordance
- Manual pre-session hint: quick text field on recording start sheet

---

## Section 3: UI Layer

### Glass Appearance Modes

**Settings toggle:** `AppearanceMode` enum — `.frosted` / `.transparent`, persisted in `UserDefaults`.

| Mode | NSVisualEffectView material |
|---|---|
| Frosted | `.hudWindow` |
| Transparent | `.underWindowBackground` |

**State-reactive layer (always on regardless of base):**
- Idle → base opacity
- Recording → opacity pulses 0.6→1.0 (0.8s cycle)
- Processing → opacity pulses 0.4→0.8 (1.2s cycle)
- Same animation for both base styles

### Global Hotkeys
Registered via `CGEventTap` at app launch (requires Accessibility permission):

| Key | Action |
|---|---|
| `⌃Space` | Trigger transcribe |
| `⌃R` | Toggle mic on/off |

Both configurable in Settings via key-capture field. Hotkeys are global (fire when AutoClawd is not focused).

### TTS — AVSpeechSynthesizer

New `SpeechService` singleton:
- Voice: `com.apple.voice.compact.en-US.Samantha` (built-in, no download)
- Fires after every Ambient Intelligence response and every Q&A answer
- Response trimmed to ≤10 words before speaking — favour first sentence, cut at word boundary
- Auto-mutes if no audio output device or headphones disconnected mid-session
- No API key, no internet required

### World Model Canvas

New `WorldModelWindow` (⌘W to open from menu bar):

**Phase 1 — Timeline (ships with v1):**
- Vertical scroll rail of session cards
- Each card: place name, time, people chips, first line of transcript
- Tap card → expand to full transcript

**Phase 2 — Mind Map overlay (ships after embeddings):**
- Force-directed graph rendered alongside timeline
- Nodes = sessions, sized by duration
- Edges drawn between sessions sharing topics or people (weight = overlap count)
- Tap node → highlights corresponding timeline card
- Colour-coded by place

---

## Architecture Diagram

```
Mic → AudioRecorder → ChunkBatcher (10-30s)
                           ↓
                    Groq Whisper (per chunk)
                           ↓
                    transcript.txt (append)
                           ↓
                    AppContextService
                    ┌──────────────────────┐
                    │ user_profile blob    │
                    │ current place/people │
                    │ last 3 sessions      │
                    └──────────────────────┘
                           ↓
                    Groq LLM (intelligence)
                           ↓
              ┌────────────┴────────────┐
           Paste to cursor         SpeechService
                                  (≤10 words TTS)
                           ↓
                    SessionStore → SQLite + .txt
                           ↓
                    WorldModelWindow (canvas)
```

---

## Implementation Phases

### Phase 1 (Core — ship first)
- SQLite schema + `SessionStore`
- `ChunkBatcher`
- WiFi location detection + place labeling
- Context injection in `AppContextService`
- Glass appearance modes
- Global hotkeys
- TTS `SpeechService`
- World model timeline view

### Phase 2 (World Model depth)
- User profile chat (`ProfileChatView`)
- People tagging (post-session LLM pass)
- Ollama embeddings per session
- Mind map canvas overlay

---

## Open Questions (deferred)
- Calendar integration for people detection (explicitly deferred to future)
- GPS fallback when no WiFi (deferred)
- Export/backup of world model data (deferred)
- Q&A mode implementation (separate design doc: `2026-02-25-three-pill-modes-design.md`)
