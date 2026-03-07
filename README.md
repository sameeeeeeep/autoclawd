<div align="center">
  <img src="Resources/autoclawd-logo.png" width="140" alt="AutoClawd" />

  # AutoClawd

  **Ambient AI for macOS — sees, hears, understands, acts.**

  [![macOS](https://img.shields.io/badge/macOS-13%2B-black?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/macos/)
  [![Swift](https://img.shields.io/badge/Swift-5.9-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
  [![Local AI](https://img.shields.io/badge/AI-Runs%20Locally-5C6BC0?style=flat-square)](https://ollama.ai)
  [![License: MIT](https://img.shields.io/badge/License-MIT-22c55e?style=flat-square)](LICENSE)

  100 source files &nbsp;·&nbsp; ~27K lines of Swift &nbsp;·&nbsp; entirely self-built with Claude Code

</div>

---

AutoClawd is a macOS app that runs as a floating pill widget with an always-on microphone and camera. It listens to your conversations, watches who's in the room, understands what you're working on, and autonomously executes tasks — all without you ever typing a prompt.

You talk. You gesture. It handles the rest.

Everything runs locally on your machine — Apple SFSpeechRecognizer for transcription, Apple Vision for face detection and hand tracking, Ollama Llama 3.2 for intelligence. **Nothing leaves your device unless you explicitly opt in.**

---

## The Idea

> *"What if Apple and Anthropic decided to collaborate on a product?"*

The AI adoption gap isn't intelligence — it's friction. Every interaction starts with you: opening an app, writing a prompt, describing what you need. Context switching. Trial and error. Keeping up with every new model drop.

AutoClawd removes all of that. It's not a chat interface. It's ambient infrastructure that runs alongside you — recognising what needs doing and doing it, reducing the cognitive overhead of using AI to zero.

**You never give it a prompt. You just work.**

And the recursive form of that idea: AutoClawd builds itself the same way. Every conversation about what it should do next is captured, batched, and shipped as code by Claude Code overnight.

---

## Five Modes

AutoClawd operates through five pill modes, switchable via keyboard shortcuts or left-hand gestures:

| Mode | Tag | What it does |
|---|---|---|
| **Ambient** | `[AMB]` | Full pipeline — mic → transcribe → analyze → extract tasks → execute autonomously |
| **Transcribe** | `[TRS]` | Clean transcription only — real-time denoising, multi-level polish, paste anywhere |
| **AI Search** | `[SRC]` | Voice-triggered Q&A against your accumulated context and world model |
| **Tasks** | `[TSK]` | Todo management — view, approve, and manage extracted tasks |
| **Code** | `[COD]` | Voice-driven Claude Code co-pilot — speak your intent, watch it build |

The session transcript persists across mode switches. Only 10 seconds of silence or an explicit end-session gesture resets it.

---

## Pipeline

Every spoken word flows through a four-stage local intelligence pipeline:

```
Microphone
  │
  ├─ Live streaming ──── SFSpeechRecognizer word-by-word partials (appears instantly)
  │
  ├─ 30s committed chunk ── Apple SFSpeech or Groq Whisper
  │
  ├─ Stage 1: Cleaning ──── Ollama Llama 3.2 ── merge chunks, remove noise,
  │                          resolve speakers, session context enrichment
  │
  ├─ Stage 2: Analysis ──── Ollama Llama 3.2 ── extract tasks, tag people,
  │                          identify decisions, update world model
  │
  ├─ Stage 3: Task Creation ── classify: auto / ask / captured
  │                             frame titles from project README/CLAUDE.md
  │
  └─ Stage 4: Execution ──── Claude Code SDK ── stream output in project folder
```

Pipeline routing depends on the source:

| Source | Stages run |
|---|---|
| Ambient | clean → analyze → task → execute |
| Transcription | clean only (with multi-level polish) |
| Code | transcript + Claude Code task, skip LLM analysis |
| WhatsApp | full pipeline + auto-reply |

---

## Camera Vision

AutoClawd uses your Mac's camera (built-in, external, or Continuity) to see who's in the room.

**Face detection and tracking** — Apple Vision framework detects faces in real time, tracks them across frames using IoU matching, and re-identifies people who leave and return using ML feature-print embeddings.

**Speaker identification** — mouth movement is tracked per face and correlated with audio activity to determine who is currently speaking. The active speaker is highlighted in the camera feed.

**Pixel-art avatars** — every detected face gets a unique, deterministic 5x7 pixel avatar generated from their feature print. Mirrored symmetry, randomized traits (skin tone, hair, glasses, eye position) — all derived from the face data itself.

**Auto face linking** — when an unrecognized face appears, AutoClawd prompts you to link it to a known person using hand gestures. Once linked, that person is tracked across all future sessions.

---

## Hand Gesture Control

With the camera enabled, AutoClawd recognizes hand poses for fully hands-free control. Gestures require a 0.5-second hold to fire, with a 1-second cooldown between actions.

**Right hand — session control:**

| Gesture | Action |
|---|---|
| Spread open (all fingers) | Start session |
| Pinch (thumb + index) | Pause session |
| Thumbs up | End session / confirm |

**Left hand — selection:**

| Gesture | Action |
|---|---|
| 1–5 fingers raised | Select option, pick project, switch mode, choose cleaning level |

During idle (no active session), left-hand finger count maps directly to the five modes: 1 = Ambient, 2 = Transcribe, 3 = Search, 4 = Tasks, 5 = Code.

---

## Sessions

Sessions are user-driven recording units that give the pipeline richer context.

**Lifecycle:** `start → configure → record → pause → resume → end`

Before recording begins, you configure the session:
- **Project** — gesture-select from your project list (auto-selects if only one)
- **People** — link detected faces to known people
- **Context** — add bullet points about what you're working on

All session context (project name, people present, objectives) is injected into the LLM prompts during cleaning and analysis, producing significantly better results.

**Post-session cleaning** (Transcription mode) offers three quality tiers:

| Level | What it does |
|---|---|
| **1 — Raw** | Unprocessed transcript |
| **2 — Minimal** | Grammar fixed, fillers removed — runs automatically on session end |
| **3 — Polished** | Coherent, well-structured paragraphs — computed on demand |

Switch between levels with a left-hand gesture (1–3 fingers). Each level is cached after first computation. Thumbs up to confirm and paste.

---

## World Model

AutoClawd builds a persistent, per-project knowledge base from every conversation. Facts, decisions, people, and context compound over time into a markdown world model stored locally.

The world model is visualized as an interactive force-directed graph — nodes for people, projects, decisions, and facts, connected by the relationships extracted from your transcripts.

This context feeds back into the pipeline: when AutoClawd analyzes a new transcript, it has the full history of what you've discussed about that project.

---

## Skills and OpenClaw

**Built-in skills** ship with AutoClawd and cover common categories: development, analysis, communication, creative, marketing, automation, and more. Each skill has a prompt template and optional workflow binding.

**Custom skills** are stored as JSON in `~/.autoclawd/skills/` — create them in the UI or edit the files directly.

**OpenClaw compatibility** — AutoClawd loads skills from `SKILL.md` files (YAML frontmatter + markdown instructions), the same format used by the OpenClaw ecosystem. Drop a `SKILL.md` into `~/.autoclawd/openclaw-skills/` and it's available immediately. Skills can declare required binaries and environment variables; AutoClawd checks availability before offering them.

---

## Autonomous Execution

Tasks extracted from your conversations are classified into three modes:

| Mode | Behaviour |
|---|---|
| **Auto** | Executed immediately by Claude Code — no approval needed |
| **Ask** | Shown in the approval queue — you confirm or dismiss |
| **User** | Captured for reference — never auto-executed |

What qualifies as `auto` is fully configurable. You define plain-English rules like *"Send emails"*, *"Create GitHub issues"*, *"Update documentation"* — the analysis LLM uses these when assigning task modes.

Tasks run in the correct project directory with streamed output. An embedded MCP server lets Claude Code read and write AutoClawd data mid-task.

---

## Context Awareness

AutoClawd weaves ambient context from multiple sources into every pipeline run:

- **People** — identifies who you mention, tracks them across sessions, links faces to names
- **Location** — Core Location + WiFi SSID; sessions are tied to places for recall
- **Now Playing** — ShazamKit identifies music in the background and creates episodes
- **Screenshots** — optional periodic screen capture for visual context
- **Clipboard** — monitors changes and weaves copied content into the context graph
- **Structured extraction** — facts, decisions, action items, and entities pulled from every transcript

---

## Mission Control HQ

A live pixel-art visualization of the pipeline, rendered as a WebKit canvas overlay.

Agents spawn in a queue by the wall, pick up transcripts, and walk desk-to-desk through the pipeline stages: **Comms → Analysis → Projects → Claude Code → Archive**. Each desk lights up as the corresponding pipeline stage fires. Failed agents re-queue. Successful ones walk off-screen.

The sprites are 640x1120 RGBA with 12 directional frames (walk/stand x front/back/left/right). Perspective scaling places agents deeper in the room as they move up the canvas.

---

## Self-Evolution

When you talk about AutoClawd — what it should do, what's broken, ideas for new features — it recognises those as tasks for itself. At the end of each day, it batches all pending self-improvement tasks and runs a full autonomous cycle:

```
Captured ideas
  │
  ├─ Product thinking    — what problem does this solve
  ├─ Flow + design       — how it fits the existing UX
  ├─ Tech plan           — which files change, what services are needed
  └─ Execution           — Claude Code implements, builds, and commits
```

AutoClawd ships a new version of itself every day, driven entirely by the conversations happening around it.

---

## Install

```bash
# 1. Install Ollama and pull the local model
brew install ollama && ollama pull llama3.2:3b

# 2. Clone and build
git clone https://github.com/sameeeeeeep/autoclawd.git
cd autoclawd && make

# 3. Run
open build/AutoClawd.app

# Or build + run in one step
make run
```

First launch walks through mic, camera, and accessibility permissions.

**Optional extras:**

| Feature | Setup |
|---|---|
| Groq transcription (faster, cloud) | Set `GROQ_API_KEY` in `~/.zshenv` or Settings |
| Claude Code execution | Set `ANTHROPIC_API_KEY` in `~/.zshenv` or Settings |
| WhatsApp self-chat | `cd WhatsAppSidecar && npm install && npm start` |
| DMG packaging | `make dmg` |

---

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `⌃Z` | Toggle microphone |
| `⌃A` | Ambient Intelligence mode |
| `⌃X` | Transcription mode |
| `⌃S` | AI Search mode |
| `⌃D` | Code co-pilot mode |

---

## Architecture

```
AutoClawd.app (Swift / SwiftUI / AppKit)
│
├── Windows
│     ├── PillWindow (NSPanel)          floating widget, always on top, snap-to-edge
│     ├── MainPanelWindow               dashboard — pipeline, tasks, world model, settings
│     ├── ToastWindow                   non-intrusive execution feedback
│     └── SetupWindow                   first-run dependency wizard
│
├── Audio
│     ├── AudioRecorder                 always-on AVAudioEngine (stays hot between chunks)
│     ├── StreamingLocalTranscriber     live SFSpeech word-by-word partials
│     └── ChunkManager                 30s buffer cycles, session lifecycle
│
├── Camera
│     ├── CameraService                AVFoundation capture (~8 fps, throttled)
│     ├── FaceTracker                  Vision detection + feature-print re-identification
│     └── HandGestureRecognizer        Vision hand pose → debounced state machine
│
├── Pipeline (serial job queue, 1.5s stagger)
│     ├── TranscriptCleaningService    Ollama Llama 3.2 — merge, denoise, multi-level polish
│     ├── TranscriptAnalysisService    Ollama Llama 3.2 — tasks, tags, world model
│     ├── TaskCreationService          structured tasks with mode assignment
│     └── TaskExecutionService         Claude Code SDK streaming
│
├── Sessions
│     ├── SessionConfig                pre-session context (project, people, objectives)
│     └── SessionStore                 SQLite — place/project/time linking
│
├── Intelligence
│     ├── WorldModelService            per-project markdown knowledge base
│     ├── WorldModelGraph              force-directed graph visualization
│     ├── ExtractionService            facts, decisions, entities
│     └── PeopleTaggingService         person tracking across sessions
│
├── Context
│     ├── LocationService              Core Location + WiFi SSID place binding
│     ├── ShazamKitService             audio fingerprinting → episodes
│     ├── ScreenshotService            periodic ambient screen capture
│     └── ClipboardMonitor             clipboard change monitoring
│
├── Skills
│     ├── SkillStore                   built-in + custom skill persistence
│     └── OpenClawSkillLoader          SKILL.md file discovery and parsing
│
├── Integrations
│     ├── WhatsAppPoller/Service       Node.js sidecar, self-chat only
│     ├── MCPConfigManager             MCP server config for execution
│     ├── ClaudeCodeRunner             low-level SDK streaming client
│     └── QAService                    AI search against context
│
└── PixelWorld (WebKit)
      adapter.js                       pipeline event → game action routing
      game.js                          canvas renderer — perspective, sprites, desks
      sprites/                         12-directional walk/stand (640×1120 RGBA)
```

### Local AI Stack

| Stage | Model | Provider | Purpose |
|---|---|---|---|
| Streaming transcription | SFSpeechRecognizer | Apple (on-device) | Live word-by-word partials |
| Committed chunks | Whisper / SFSpeech | Groq (optional) or Apple | Final chunk text |
| Cleaning + Analysis | Llama 3.2 3B | Ollama (on-device) | All intelligence — merging, task extraction, world model |
| Task execution | Claude Code | Anthropic API | Autonomous task execution via SDK |

### Storage

Everything lives in `~/.autoclawd/` — SQLite databases and markdown files, fully local.

```
~/.autoclawd/
  world-model.md         per-project knowledge base
  transcripts.db         raw + cleaned transcripts
  pipeline.db            pipeline stage records
  structured_todos.db    task queue with status history
  sessions.db            session timeline + place/project links
  extractions.db         facts, decisions, entities
  qa.db                  Q&A history
  context.db             clipboard + screenshot context
  skills/                individual skill JSON files
  openclaw-skills/       OpenClaw SKILL.md directories
```

### UI Stack

- **SwiftUI** for all views inside windows
- **AppKit** (NSPanel/NSWindow) for window management — drag, snap, floating
- **WebKit** (WKWebView) for PixelWorld canvas rendering
- **Liquid Glass** support on macOS 26 (Tahoe) — falls back to `ultraThinMaterial` on older SDKs
- Custom fonts, frosted/solid appearance modes, light/dark/system theming

---

## Roadmap

- [ ] Self-evolution — daily batched self-improvement cycle
- [ ] Phone call transcription via Bluetooth mic
- [ ] Scheduled tasks and calendar integration
- [ ] Multi-language transcription
- [ ] Shared world model across devices
- [x] Camera vision — face detection, speaker tagging, pixel-art avatars
- [x] Hand gesture control — session lifecycle, mode switching, option selection
- [x] User-defined sessions — gesture-driven with project + people context
- [x] Post-session cleaning — three quality tiers with gesture switching
- [x] Live word-by-word streaming transcript
- [x] Session-persistent transcript across all modes
- [x] Fully local transcription + analysis (Apple + Ollama)
- [x] Skills system with OpenClaw compatibility
- [x] MCP server support
- [x] WhatsApp self-chat integration
- [x] Mission Control HQ pixel-art visualization
- [x] People tagging, location, ShazamKit, screenshot context
- [x] World model graph visualization
- [x] Q&A against transcript context
- [x] Configurable autonomous task rules
- [x] Voice-driven Claude Code co-pilot mode
- [x] DMG packaging

---

## License

MIT — build on it, fork it, ship it.
