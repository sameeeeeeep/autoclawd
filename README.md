<div align="center">
  <img src="Resources/autoclawd-logo.png" width="120" alt="AutoClawd" />

  # AutoClawd

  **The ambient AI layer for your Mac. Zero prompts. Zero friction.**

  [![macOS](https://img.shields.io/badge/macOS-13%2B-black?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/macos/)
  [![Swift](https://img.shields.io/badge/Swift-5.9-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
  [![Local AI](https://img.shields.io/badge/AI-Runs%20Locally-5C6BC0?style=flat-square)](https://ollama.ai)
  [![License: MIT](https://img.shields.io/badge/License-MIT-22c55e?style=flat-square)](LICENSE)

</div>

---

AutoClawd listens to everything spoken around your Mac, figures out what you're working on, and gets things done — without you ever opening a chat window or typing a prompt.

It runs as a floating pill widget. You talk. It handles the rest.

Transcription, analysis, and memory run entirely on your machine using Apple-native frameworks and local models. **Nothing leaves your device unless you explicitly choose it to.**

---

## The Idea

> *"What if Apple and Anthropic decided to collaborate on a product?"*

Models have crossed the intelligence threshold. The bottleneck now is adoption — and adoption has a friction problem.

On the web, solutions like WebMCP are collapsing the gap between AI capability and the browser. On the consumer side, a new wave of apps is trying to close the same gap for everyday users.

But the deeper problem remains: **knowing what to use, when to use it, and how to use it.** Keeping up with every new drop. Trial and error. Context switching. Every interaction still starts with you — opening an app, writing a prompt, describing what you need.

AI has given us an opportunity to fundamentally rethink that UX — to go beyond chat. Instead of AI as something you pick up, it becomes infrastructure that runs alongside you. Ambient intelligence that recognises what needs doing and does it, collapsing the cognitive overhead of using AI to zero.

That's what AutoClawd is. **You never give it a prompt. You just work.**

The logical conclusion of that idea: **AutoClawd improves itself the same way.** Every conversation about what it should do next is captured, batched at the end of the day, and handed to Claude Code — which thinks through specs, designs the flow, writes a tech plan, and ships the change. AutoClawd is a system that builds itself from the conversations happening around it.

---

## What It Does

AutoClawd runs an always-on mic in the background. As you talk — in meetings, to yourself, on calls — it:

1. **Transcribes** everything in real time, live word by word, locally
2. **Understands** what you're working on, who you're talking about, what needs doing
3. **Extracts tasks** and classifies them — auto-run, needs approval, or just captured
4. **Executes** them using Claude Code, or any AI tool or workflow you connect via MCP

Tasks can be anything. Ship a feature. Send an email. Create a design. File an issue. Summarize a document. Whatever your connected tools can do — AutoClawd can trigger it from speech alone.

With **MCP support**, every integration you plug in expands what AutoClawd can act on. Work tasks, life tasks, creative work — all of it.

And when you talk about AutoClawd itself — ideas, bugs, things it should do — it captures those too, and uses them to improve itself overnight.

---

## How It Works

```
You talk
  │
  ├─ Live word-by-word streaming → appears in the pill as you speak
  │
  ├─ Every 30s: committed chunk → local transcription (Apple SFSpeech or Groq)
  │
  ├─ Stage 1: Cleaning      — local Llama 3.2, merges chunks, removes noise
  │
  ├─ Stage 2: Analysis      — local Llama 3.2, extracts tasks, people, decisions,
  │                           updates your per-project world model
  │
  ├─ Stage 3: Task Creation — structured tasks: auto / needs approval / captured
  │
  └─ Stage 4: Execution     — Claude Code runs tasks autonomously in the right
                              project folder, with streamed output
```

**Session-aware.** Text accumulates across all modes for the full duration of your session. Ten seconds of silence = new session. The transcript resets and waits for you to speak again.

**Privacy-first.** Transcription, cleaning, analysis, and memory all run locally — Apple SFSpeechRecognizer + Ollama Llama 3.2 on your own hardware. No data leaves your machine unless you opt in to cloud transcription (Groq) or task execution (Claude Code, MCP tools).

---

## Features

**Ambient Intelligence**
- Always-on mic with live streaming transcript — words appear as you speak, before the chunk is even committed
- Full session transcript accumulates across modes (ambient, transcription, code) — switching never resets it
- World model: a per-project knowledge base that compounds across every conversation
- Interactive world model graph visualization

**Camera Vision**
- Real-time face detection and tracking using Apple Vision framework
- Speaker identification — detects who is talking by tracking mouth movement synced with audio
- Deterministic pixel-art avatars generated from face feature prints — every person gets a unique 5×7 avatar
- Face re-identification — recognizes people when they leave and return to frame using ML embeddings
- Auto face linking — new faces trigger a gesture-based flow to assign them to known people

**Hand Gesture Control**
- Right hand spread open → start session
- Right hand pinch → pause session
- Right hand thumbs up → end session / confirm
- Left hand finger count (1–5) → select options, switch modes, pick projects, choose cleaning levels
- Debounced gesture recognition with cooldown — gestures must be held for 0.5s before firing

**User-Defined Sessions**
- Gesture-driven session lifecycle: start → pause → resume → end, all hands-free
- Pre-session project picker — raise left hand to select which project you're working on
- Session context capture: project, people present, objectives
- Session-level processing — full pipeline runs at session end with accumulated context
- Post-session transcript cleaning with three quality tiers:
  - **Raw** — unprocessed original
  - **Minimal** — grammar fixed, filler removed
  - **Polished** — coherent, well-structured paragraphs
- Gesture-based cleaning level switcher — raise 1–3 fingers to preview each tier

**Autonomous Execution**
- Configurable rules for which tasks run without approval
- Task approval queue for anything that needs a confirm
- Claude Code runs tasks in the correct project folder with streamed output
- MCP server support — plug in any tool or workflow
- Skills system — built-in and custom triggers that fire on specific voice patterns
- **Self-evolution** — ideas about AutoClawd itself are captured, batched end-of-day, and executed as a full specs → design → plan → code cycle

**Context Awareness**
- People tagging — identifies and tracks who you mention across sessions
- Location awareness — knows where you are, ties sessions to places via WiFi SSID
- Now Playing via ShazamKit — captures what's on in the background
- Screenshot context — optional ambient screen capture
- Clipboard monitoring — clipboard changes woven into context
- Structured extraction — facts, decisions, and entities pulled from every transcript

**Integrations**
- WhatsApp self-chat — voice note yourself a task, it runs automatically
- Groq Whisper — optional cloud transcription for lower latency
- Transcription-to-clipboard — paste a cleaned transcript anywhere instantly

**UI**
- Floating pill widget, always on top, snaps to screen edges
- Live camera feed with face bounding boxes, speaker highlighting, and gesture indicators
- Mission Control HQ — live pixel-art room where pipeline agents walk desk-to-desk in real time
- Appearance modes: frosted glass or solid, light/dark/system, custom fonts
- Session timeline, Q&A against your context, structured todo queue

---

## Self-Evolution

AutoClawd is designed to build itself.

When you talk about AutoClawd — what it should do, what's broken, ideas for features — it recognises those as tasks for itself and captures them alongside everything else. At the end of each day, it batches all pending self-improvement tasks and kicks off an autonomous planning and execution cycle:

```
Captured ideas across the day
  │
  ├─ Product thinking    — what problem does this solve, what's the right behaviour
  ├─ Flow + design       — how it fits into the existing UX and pipeline
  ├─ Tech plan           — what files change, what new services are needed
  └─ Execution           — Claude Code implements, builds, and commits the change
```

The result: AutoClawd ships a new version of itself every day, driven entirely by the conversations happening around it. No roadmap meetings. No ticket grooming. Just talk.

This is the recursive form of the core idea — ambient intelligence that removes friction not just from your work, but from its own development.

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
```

On first launch, the setup assistant checks for Ollama and walks through mic + accessibility permissions.

**Optional — Groq transcription (faster, cloud):**
Set `GROQ_API_KEY` in `~/.zshenv` or via the Settings panel.

**Optional — Claude Code execution:**
Set `ANTHROPIC_API_KEY` in `~/.zshenv` or via the Settings panel.

**Optional — WhatsApp:**
```bash
cd WhatsAppSidecar && npm install && npm start
```

---

## Shortcuts

| Shortcut | Action |
|---|---|
| `⌃Z` | Toggle microphone |
| `⌃1` | Ambient Intelligence mode |
| `⌃2` | Transcription-only mode |
| `⌃3` | AI Search mode |
| `⌃4` | Claude Code co-pilot mode |

**Hand Gestures (with camera enabled):**

| Gesture | Hand | Action |
|---|---|---|
| Spread open | Right | Start session |
| Pinch closed | Right | Pause session |
| Thumbs up | Right | End session / confirm |
| 1–5 fingers | Left | Select option / switch mode / pick project |

---

## Architecture

```
AutoClawd.app (Swift/SwiftUI)
│
├── PillWindow              floating NSPanel, always on top
├── MainPanelWindow         dashboard — pipeline, tasks, world model, settings
│
├── AudioRecorder           always-on AVAudioEngine (stays hot between chunks)
│     ├── StreamingLocalTranscriber   live SFSpeech word-by-word partials
│     └── ChunkManager               30s cycles, session end on 10s silence
│
├── CameraService           AVFoundation frame capture (~8 fps)
│     ├── FaceTracker                 Vision-based detection + re-identification
│     └── HandGestureRecognizer       hand pose → session/option gestures
│
├── PipelineOrchestrator
│     ├── Stage 1: TranscriptCleaningService    local Llama 3.2
│     ├── Stage 2: TranscriptAnalysisService    local Llama 3.2
│     ├── Stage 3: TaskCreationService
│     └── Stage 4: TaskExecutionService         Claude Code SDK
│
├── Sessions
│     ├── SessionStore       SQLite persistence, place + project linking
│     └── SessionConfig      pre-session context (project, people, objectives)
│
├── Context (parallel)
│     ├── ScreenshotService · ClipboardMonitor · LocationService
│     ├── ShazamKitService · PeopleTaggingService · ExtractionService
│     └── WorldModelService + WorldModelGraph
│
├── Integrations
│     ├── WhatsAppPoller       polls Node.js sidecar, self-chat only
│     ├── MCPConfigManager     MCP server config for task execution
│     └── QAService            AI search against accumulated context
│
└── PixelWorld (WebKit overlay)
      Live pixel-art pipeline visualization
      Agents queue → walk desk-to-desk as each pipeline stage fires
```

**Pipeline sources:**

| Source | Stages |
|---|---|
| `.ambient` | clean → analyze → task → execute |
| `.transcription` | clean only |
| `.code` | transcript + Claude Code task; skip analysis |
| `.whatsapp` | clean → analyze → task → execute + reply |

**Task modes:**

| Mode | Behaviour |
|---|---|
| `auto` | runs immediately |
| `ask` | surfaces for approval |
| `user` | captured, never auto-run |

---

## Storage

Everything lives in `~/.autoclawd/` — SQLite and markdown, fully local.

```
~/.autoclawd/
  world-model.md        per-project knowledge base
  transcripts.db        raw + cleaned transcripts
  pipeline.db           pipeline stage records
  structured_todos.db   task queue with history
  sessions.db           speaking session timeline
  extractions.db        facts, decisions, entities
  qa.db                 Q&A history
  context.db            clipboard + screenshot context
  skills.db             built-in + custom skills
```

---

## Roadmap

- [ ] Self-evolution — daily batched self-improvement cycle (capture ideas → specs → design → tech plan → execute)
- [ ] Phone call transcription via Bluetooth mic
- [ ] Scheduled tasks and calendar integration
- [ ] Multi-language transcription
- [ ] Shared world model across devices
- [x] Camera vision — real-time face detection, speaker tagging, pixel-art avatars
- [x] Hand gesture control — session lifecycle, mode switching, option selection
- [x] User-defined sessions — gesture-driven start/pause/end with project + people context
- [x] Post-session transcript cleaning — three quality tiers with gesture-based switching
- [x] Live word-by-word streaming transcript
- [x] Session-persistent transcript (accumulates across modes, resets on silence)
- [x] Fully local transcription + analysis (Apple + Ollama)
- [x] Skills system (built-in + custom)
- [x] MCP server configuration
- [x] WhatsApp self-chat integration
- [x] Mission Control HQ visualization
- [x] People tagging, location, ShazamKit, screenshot context
- [x] World model graph visualization
- [x] Q&A against transcript context
- [x] Configurable autonomous task rules

---

## License

MIT — build on it, fork it, ship it.
