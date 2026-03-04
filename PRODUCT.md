# AutoClawd — Product Bible

**Last updated:** 2026-03-04
**Version:** Phase 1 (shipped) → Phase 2 (in progress)
**Builders:** Sameep + Claude

---

## Vision

AutoClawd is not a tool. It is a twin.

A tool waits. A twin lives with you. It hears what you say, remembers what matters, understands the arc of your life — and acts before you have to ask.

The end state: a presence that runs in parallel with your existence. No prompts. No chat windows. No switching context. You just live — and your twin is already there, already thinking, already doing.

**The test:** Can AutoClawd generate a rich, emotionally accurate journal of a person's day, month, and year — capturing not just their work, but their relationships, moods, recurring thoughts, decisions, and growth — just from passively listening?

If yes, the foundation is right. Everything else is built on that.

---

## Core Philosophy

### 1. Ambient, not reactive
Every AI tool today is reactive. You open it. You type. You wait.
AutoClawd inverts this. It runs continuously. It understands before you ask. It acts without being prompted. This is the shift from *AI as a tool you pick up* to *AI as infrastructure that runs alongside you.*

### 2. Passive engagement, not active prompting
Users should not have to come to AutoClawd. AutoClawd should come to them.
Engagement happens through:
- Proactive WhatsApp messages (morning briefings, evening digests, questions)
- Ambient canvas prompts during silence
- Push notifications with sharp, personal insights
- Monthly/yearly "Wrapped" moments that are shareable and viscerally accurate

### 3. The twin model
AutoClawd should feel like a twin who lives with you — one that has no ego, no agenda, and an uncanny understanding of who you are. It never judges. It just observes, remembers, and synthesises. The goal is to make the user believe: *this thing really knows me.*

### 4. Compounding intelligence
The system should get measurably smarter over time. Each conversation adds to the world model. The model is never wiped. The diff is always growing. The journal is always deepening. This is the long-term lock-in and the core of why this product is hard to replicate.

### 5. Consumer adoption = addictive, sticky, shareable
AutoClawd succeeds as a consumer product when:
- Users recommend it by showing someone their journal or Wrapped
- Users feel anxious leaving AutoClawd off (like not wearing a watch)
- Users derive unexpected value (a mirror held up to their life) they can't get anywhere else

---

## What AutoClawd Is (and Is Not)

| Is | Is Not |
|---|---|
| Ambient, continuous, background | A chat interface |
| A life observer and synthesiser | A task manager |
| A twin that knows you | A voice assistant |
| A compounding intelligence layer | A transcription tool |
| Consumer-grade, emotionally resonant | Enterprise productivity software |

---

## User Flow

### Primary (Ambient Mode)

```
User wakes up → opens WhatsApp
  ↓
AutoClawd morning message:
  "Good morning. Yesterday you had 3 decisions left open.
   You talked about [project] for 45 min and seemed energised.
   Today: Subko or home? Here are your open questions."
  [Answer by voice later] [Reply here]

User goes about their day (AutoClawd is already running)
  ↓
User speaks — to themselves, colleagues, in meetings, on calls
  ↓
Audio captured every 30s → transcribed → cleaned → analysed
  ↓
Tasks extracted, world model updated, journal entry appended
  ↓
Auto tasks fire in the background (no notification unless needed)
  ↓
Evening: WhatsApp digest
  "Today: 2h 14m ambient. 7 tasks extracted. 4 completed.
   You mentioned [person] 3 times. One open decision about [X].
   Here's today's entry → [journal link]"

Monthly:
  Wrapped card — shareable, visceral, accurate
  "This month: 47 conversations, 18 projects, 62 tasks.
   You've started talking about fitness 3× more than last month.
   Top themes: AutoClawd, [person], [city]."
```

### Q&A Canvas (new — see Engagement section)

When AutoClawd has open questions for the user, the ambient canvas inside the widget shifts to Q&A mode:
- Cards showing 3–5 open questions the twin wants answered
- User taps a card → it expands and highlights as "active"
- User speaks → that transcript chunk is tagged `reply_to: questionID`
- For yes/no or option questions: answer chips shown; tap = direct reply (no speech needed)
- Dismissed automatically once answered or after 60s with no interaction

### WhatsApp Mode

```
User sends voice note to self
  ↓
Sidecar captures → transcribes → routes to full pipeline
  ↓
Bot replies with "Dot: [summary / task created / question]"
  ↓
Bot proactively messages (morning, evening, insights, open questions)
```

---

## Features

### Shipped

| Feature | Status | Notes |
|---|---|---|
| Always-on mic → 30s chunks | ✅ | AudioRecorder + ChunkManager |
| Groq Whisper transcription | ✅ | Fallback to Apple SFSpeech |
| Transcript cleaning (Llama 3.2) | ✅ | Local, TranscriptCleaningService |
| Analysis + task extraction (Llama 3.2) | ✅ | Local, TranscriptAnalysisService |
| Serial pipeline queue (FIFO, 1.5s stagger) | ✅ | SerialJobQueue actor |
| Auto-task execution via Claude Code | ✅ | TaskExecutionService |
| Task modes: auto / ask / user | ✅ | Pipeline-wide |
| Task approval queue in dashboard | ✅ | LogsPipelineView |
| World model markdown file | ✅ | Sparse; needs upgrades (see below) |
| WhatsApp self-chat integration | ✅ | WhatsAppPoller + sidecar |
| Multi-mode pill: ambient/transcription/search/code | ✅ | PillMode enum |
| Widget appearance system (frosted/solid/transparent, dark/light) | ✅ | WidgetAppearance token system |
| Apple Intelligence–style edge shimmer (GlowState) | ✅ | EnabledGlow / ThinkingGlow |
| Ambient session tagging canvas | ✅ | AmbientTaggingCanvasView |
| Mission Control HQ pixel world | ✅ | WebKit + game.js |
| Agent queue + desk-to-desk pipeline visualization | ✅ | adapter.js routing |
| Settings: API keys, appearance, autonomous task rules | ✅ | SettingsManager |
| Native Liquid Glass migration (gated on macOS 26 SDK) | ✅ | `#if NATIVE_GLASS_AVAILABLE` |

### In Progress / Next

| Feature | Priority | Notes |
|---|---|---|
| Batch intelligence engine | P0 | Multi-transcript Llama pass; project/category batching |
| World model v2: PageRank + episodic + diff.md | P0 | See Memory Architecture section |
| Q&A canvas mode | P1 | Open questions in canvas; tagged voice replies |
| Daily/monthly/yearly journal synthesis | P1 | Narrative from episodes + world model |
| WhatsApp proactive engagement | P1 | Morning/evening, Wrapped moments, open questions |
| Idle reprocessing pass | P2 | Re-understand past with updated world model context |
| Web research integration (tagged as `source: research`) | P2 | Enriches world model without polluting episodic memory |
| Silence ambient prompts | P2 | Contextual questions during quiet periods |

### Planned (Roadmap)

- [ ] Phone call transcription (Bluetooth mic capture)
- [ ] Screen context — periodic screenshot for visual context
- [ ] MCP server — expose AutoClawd memory to any MCP-compatible tool
- [ ] Scheduled tasks with system calendar
- [ ] Multi-language transcription
- [ ] Location tagging via WiFi SSID → place names
- [ ] People tagging (manual hint + AI inference)
- [ ] Execution history and re-run

---

## Intelligence Architecture

### Pipeline (current)

```
Audio → Transcription → Cleaning → Analysis → Task Creation → Execution
   (30s chunks)  (Groq/Apple)  (Llama 3.2)  (Llama 3.2)  (Llama 3.2)  (Claude Code)
```

### Planned: Batch Intelligence

The current pipeline processes each transcript one-by-one. The upgrade adds a second pass:

**Immediate pass** (existing):
Single transcript → clean + extract tasks → serial queue (1 Ollama call per transcript)

**Batch pass** (new, runs every N minutes or on idle):
```
[Buffer of unprocessed transcripts]
        │
        ├── Group by: same project / same session / same time window
        │
        ├── One Llama call per group:
        │   "Here are 5 transcripts from [project]. What's the big picture?
        │    What decisions were made? What patterns emerge? What's unresolved?"
        │
        └── Output: world model patch (not a rewrite) → diff.md entry appended
```

**Idle reprocessing** (new, triggers after 15min silence):
Take last 50 episodes not yet batch-processed → run "big picture" Llama pass
with current world model as context → extract patterns, update entities
→ never modify past episodes; only update the model.

**Why this matters:** A single 30s transcript is a fragment. Ten fragments from the same
project meeting reveal a decision arc, a recurring blocker, an evolving opinion.
The batch pass sees what single-transcript processing misses.

---

## Memory Architecture

AutoClawd's memory system mirrors the architecture of human memory:

| Human brain | AutoClawd equivalent |
|---|---|
| Sensory register (< 1s) | Raw audio chunks (ephemeral, not stored) |
| Working memory (seconds → minutes) | Current session context |
| **Episodic memory** (hippocampus) | `transcripts.db` — first-person, timestamped experiences |
| **Semantic memory** (neocortex) | `world-model.md` — slow-learned facts, entity graph |
| Procedural memory | Behavioral patterns extracted over time |
| Emotional memory | Affect tags per episode (tone, energy, mood) |
| Sleep consolidation | Idle batch reprocessing |
| Spreading activation | PageRank traversal over entity graph |
| Reading / external knowledge | Research memory (`source: research` tagged) |

### World Model v2 (planned)

**Current state:** A sparse markdown file with a few facts. Not structured for retrieval.

**v2 structure:**

```
world-model/
  entities.db        — people, projects, topics, places, decisions
                        each with: PageRank weight, first_seen, last_seen, mention_count
  relations.db       — entity-to-entity edges (person↔project, topic↔emotion, etc.)
  world-model.md     — human-readable current state (auto-generated from entities.db)
  diff.md            — append-only log of every model change
                        format: [2026-03-04] 'fitness' mentions: 2→8; new relation: fitness↔morning
```

**Retrieval:**
1. PageRank gives top N most connected/mentioned entities (fast lookup)
2. Given a query entity, fetch top-K episodes from `transcripts.db` by relevance
3. Combine: "what do I know about X" + "when did X come up most"

**Research memory:**
When web search is available, findings are tagged `source: research`:
- Treated as "things read", not "things experienced"
- Lower certainty weight than episodic facts
- Still updates world model entities (with `research_confirmed` flag)
- Prevents hallucination: retrospective reprocessing can say
  "I found news about [X]'s competitor — does that change how you think about [decision]?"
- Keeps episodic truth clean: never overwrites what was actually said

**diff.md:**
Auto-appended on every world model update. Never rewritten. Format:
```
[2026-03-04 09:12] fitness: 2→8 mentions (+300%). new relation: fitness↔morning routine
[2026-03-04 09:12] project: 'AutoClawd' — updated priority: medium→high
[2026-03-04 09:12] person: 'Subko' tagged as location (was: unknown entity)
[2026-03-04 11:30] RESEARCH: competitor 'X' found (source: web) — tagged as research_confirmed
```

---

## The Journal

The journal is the product's most powerful consumer feature. It is the proof that AutoClawd
understands you — not just your tasks, but your life.

### Daily Journal (generated ~10pm or on demand)

- Synthesised from all day's episodes + world model state
- Narrative prose, not bullet points
- Covers: what you worked on, who you mentioned, what you decided, emotional arc, open questions
- Example: *"Today started energised — you spent the first two hours deep in AutoClawd's pipeline. After lunch the tone shifted; you mentioned [person] three times and the word 'blocked' came up twice in the afternoon session. By evening you were circling back to the question of whether to launch in April or wait."*

### Monthly Synthesis

- Aggregated from daily journals
- Pattern extraction: what grew, what faded, what shifted
- Shareable metrics: top people, top projects, mood arc, decision-making patterns
- Example insight: *"You've mentioned fitness 3× more than last month. You used the word 'tired' 18 times in February vs 7 in January."*

### Yearly (Wrapped)

- Life chapters: what mattered, what changed, who appeared and disappeared
- Major decisions and their outcomes
- Unexpected patterns AutoClawd noticed that you didn't

### Wrapped Moments (monthly push)

A shareable card with sharp, specific, surprising stats:
```
This month with AutoClawd:
47 conversations · 18 projects · 62 tasks created · 48 completed
You talked about your ex 12 times ↓ from 31 last month
Fitness mentions: ↑ 300%
Top emotion: energised (morning), uncertain (after 2pm)
Most mentioned person: [X]
One decision you keep postponing: [Y]
```

---

## Consumer Engagement (The Sticky Layer)

### Proactive WhatsApp touchpoints

**Morning (7:30am):**
```
"Hey twin. ☀️ Yesterday: 3 hours of AutoClawd, 5 tasks done, 2 still open.
 You seemed most energised between 9–11am.
 Today's open question: have you decided about [X]?
 Working from Subko today?"
→ [Yes, Subko] [Home] [Reply by voice later]
```

**Evening (9pm):**
```
"Day recap → 2h 14m captured, 7 tasks, 1 new project detected.
 Today's journal is ready.
 One thing I noticed: you mentioned [Y] 4 times but haven't made a move yet.
 Want me to create a task for it?"
→ [Yes, create task] [Dismiss] [Not yet]
```

**Silence prompts (ambient mode, >60s quiet):**
- Contextual, low-frequency, never annoying
- "You mentioned [X] earlier — have you made a decision?"
- "Quick thought: you've been working on [project] for 3 weeks. Biggest blocker?"
- Taps into the canvas (Q&A mode) when opened

**Open question cycling (Q&A canvas):**
- When the twin has questions, they surface as cards in the widget canvas
- User cycles through, taps one to activate, speaks or taps an answer chip
- The reply is tagged to the question and feeds back into the world model

### What makes it addictive

- **Accuracy shock** — when the journal is right about your emotional state, you can't stop reading
- **Mirror effect** — people share Wrapped not because it's cool but because it's *true*
- **FOMO when off** — after a few weeks of use, turning off the mic feels like missing a day
- **The twin loop** — proactive questions get you talking, which makes the twin smarter, which makes the questions sharper

---

## Technical Architecture (current)

```
AutoClawd.app (Swift/SwiftUI, macOS 13+)
│
├── PillWindow (NSPanel, always-on-top, snap-to-edge)
│     └── PillView — minimal floating indicator
│     └── WidgetView — expandable panel (5 collapse levels)
│           ├── WidgetAppearance — colour token system (base × style)
│           ├── GlowState — shimmer (off / breathing / Apple Intelligence rotate)
│           └── AmbientTaggingCanvasView — session project tagging
│
├── MainPanelWindow — dashboard
│     ├── LogsPipelineView — pipeline column visualiser
│     ├── SettingsConsolidatedView — all settings
│     └── [CodeWidgetView, MapEditorView, ...]
│
├── Pipeline
│     ├── AudioRecorder — 30s chunks from always-on mic
│     ├── ChunkManager — buffers + routes to PipelineOrchestrator
│     ├── PipelineOrchestrator
│     │     ├── SerialJobQueue (actor) — FIFO, 1.5s stagger between Ollama calls
│     │     ├── TranscriptCleaningService — Llama 3.2, merge/denoise/speaker
│     │     ├── TranscriptAnalysisService — Llama 3.2, extract tasks/facts/world model
│     │     ├── TaskCreationService — structured tasks (auto/ask/user)
│     │     └── TaskExecutionService — Claude Code SDK, streamed output
│     └── PipelineModels — core value types
│
├── Persistence
│     ├── TranscriptStore (SQLite)
│     ├── PipelineStore (SQLite)
│     └── world-model.md (append-updated markdown)
│
├── WhatsAppPoller — polls sidecar every 2s, self-chat only
├── SettingsManager — UserDefaults + Keychain
├── KeychainStorage — API key resolution (env var → keychain)
│
└── PixelWorld (WebKit overlay — Mission Control HQ)
      └── game.js + adapter.js + StandingA sprites
```

**Pipeline sources:**

| Source | Stages |
|---|---|
| `.ambient` | clean → analyse → task → execute |
| `.transcription` | clean only |
| `.code` | save + Claude Code task; skip LLM analysis |
| `.whatsapp` | full pipeline + WhatsApp reply |

**Model usage:**

| Stage | Model | Where |
|---|---|---|
| Transcription | Whisper | Groq (cloud) or Apple SFSpeech (local) |
| Cleaning | Llama 3.2 3B | Ollama (local) |
| Analysis | Llama 3.2 3B | Ollama (local) |
| Task framing | Llama 3.2 3B | Ollama (local) |
| Execution | Claude Code | Anthropic API |
| Research (planned) | Web search + Llama synthesis | Local synthesis, web fetch |

---

## Development Conventions

- **SwiftUI + AppKit**: SwiftUI inside windows; AppKit (NSPanel) for window management
- **MainActor**: All UI state and AppState mutations on `@MainActor`. Services are `@unchecked Sendable`
- **Logging**: `Log.info(.pipeline, "…")` — subsystems: `.pipeline`, `.system`, `.audio`, `.ui`
- **No force-unwraps** in production paths
- **Single source of truth**: `AppState` holds all published state
- **Avoid huge files**: >300 lines → split into subviews
- **PixelWorld events**: emit via `WKWebView.evaluateJavaScript("receiveEvent('type', data)")` — never bypass adapter.js
- **Native Liquid Glass**: gated on `#if NATIVE_GLASS_AVAILABLE` (auto-set by Makefile when SDK >= 26). The custom `LiquidGlass` modifier is the legacy fallback.

---

## Storage Layout

```
~/.autoclawd/
  transcripts.db          raw + cleaned transcripts (SQLite)
  pipeline.db             pipeline stage records (SQLite)
  structured_todos.db     task queue with status history
  intelligence.db         analysis results (SQLite)
  projects.db             project registry (SQLite)
  sessions.db             session records (SQLite)
  world-model.md          human-readable entity knowledge base
  todos.md                current task list (markdown)
  audio/                  retained audio chunks (7 or 30 day window)
  logs/                   pipeline logs
```

**Planned additions:**
```
  world-model/
    entities.db           structured entity graph (PageRank weights)
    relations.db          entity-to-entity edges
    diff.md               append-only world model change log
    journal/
      YYYY-MM-DD.md       daily journal entries
      YYYY-MM.md          monthly synthesis
      YYYY.md             yearly Wrapped
```

---

## Metrics for Success

| Signal | Target |
|---|---|
| Journal accuracy test | User says "that's exactly right" on first read |
| Twin recognition test | User shares journal or Wrapped without being prompted |
| Stickiness test | User notices when AutoClawd is off (like a watch) |
| Intelligence compounding test | World model entries grow meaningfully over 30 days |
| Consumer adoption test | User recommends AutoClawd by showing their own data |

---

*This document is updated with every major PR. It is the product bible — vision, strategy, technical state, user flow, and roadmap in one place.*
