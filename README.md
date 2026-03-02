<div align="center">
  <img src="Resources/autoclawd-mascot.svg" width="100" alt="Clawd the lobster" />

  # AutoClawd

  **Ambient AI for macOS. Always listening. Never prompted.**

  [![macOS](https://img.shields.io/badge/macOS-13%2B-black?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/macos/)
  [![Swift](https://img.shields.io/badge/Swift-5.9-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
  [![Local AI](https://img.shields.io/badge/AI-Runs%20Locally-5C6BC0?style=flat-square)](https://ollama.ai)
  [![License: MIT](https://img.shields.io/badge/License-MIT-22c55e?style=flat-square)](LICENSE)

</div>

---

AutoClawd runs in the background of your Mac and listens to your day. It understands what you're working on, extracts what needs doing, and executes tasks autonomously — through conversation, voice notes, or WhatsApp messages to yourself.

You never open a chat window. You never type a prompt. You just work — and AutoClawd works in parallel.

All audio processing and analysis runs on-device with local AI models. Nothing leaves your machine unless you choose it to.

---

## Demo

<div align="center">

> 📹 **Demo video coming soon**

</div>

---

## The Idea

Most AI tools are reactive. You come to them with a question. You wait for an answer. You switch back to work.

AutoClawd is different. It runs continuously in the background, listening to your conversations and voice notes. It builds a compounding model of your work, your projects, your decisions, and your intentions. When something actionable emerges from that context, it acts — without you asking.

This is the shift from *AI as a tool you pick up* to *AI as infrastructure that runs alongside you.*

---

## How It Works

```
Mic → Transcription → Cleaning → Analysis → Task Creation → Execution
                         │                        │
                    (local Whisper)         (local Llama 3.2)
```

**1. Listen** — Always-on mic captures audio in 30-second chunks. Processing starts immediately.

**2. Transcribe** — Groq Whisper for low-latency cloud transcription, or Apple SFSpeechRecognizer for fully local operation. Your choice.

**3. Clean** — A local Llama 3.2 pass merges overlapping chunks, removes filler, and resolves speaker context into a clean transcript.

**4. Analyze** — A second local LLM pass classifies content: facts, decisions, tasks, projects, people. Builds and updates your world model.

**5. Create Tasks** — Actionable items become structured tasks with priority, project assignment, and execution mode (`auto` / `ask` / `user`).

**6. Execute** — Auto tasks run immediately via Claude Code in the correct project folder. Ask tasks surface in the dashboard for your approval. Streamed output. No context switching.

---

## Mission Control HQ

AutoClawd includes a live pixel-world visualization of its own pipeline — a Mission Control room where every transcript is a character that walks through the pipeline from desk to desk.

```
[ .1 ] [ .2 ] [ .3 ]   ← queue of agents waiting near the TV wall
         │
    gets a transcript
         │
    ┌────▼────┐    ┌──────────┐    ┌──────────┐    ┌─────────────┐    ┌─────────┐
    │  Comms  │───▶│ Analysis │───▶│ Projects │───▶│ Claude Code │───▶│ Archive │
    └─────────┘    └──────────┘    └──────────┘    └─────────────┘    └─────────┘
                                                                             │
                                                                      task complete
                                                                      agent disappears
```

Each agent waits at a desk until the real pipeline event fires — not a fixed timer. If a stage stalls (transcript with no actionable task, execution failure, timeout), the agent walks back and re-queues at the right end. The queue always fills itself in from the right.

The visualization runs as a WebKit overlay inside the macOS app, powered by a canvas renderer and StandingA character sprites with directional walking animations.

---

## Features

- **Always-on mic** — captures audio continuously in the background; toggle with `⌃Z`
- **Local AI processing** — Llama 3.2 3B for cleaning and analysis; runs on M1+ without internet
- **Multi-source pipeline** — ambient mic, WhatsApp self-chat, voice notes, or direct transcription mode
- **World model** — persistent markdown knowledge base per project, updated from every conversation
- **Auto-execution** — configurable rules for which tasks run autonomously via Claude Code
- **Task approval queue** — tasks requiring confirmation surface in the dashboard with full context
- **WhatsApp integration** — send yourself a voice note or message; it becomes a task
- **Mission Control HQ** — live pixel-art visualization of the pipeline running in real time
- **Hot-word detection** — say `hot <keyword> for project <N> <task>` to create and execute by voice
- **Multi-mode pill** — ambient intelligence, transcription-only, AI search, or voice-driven Claude Code co-pilot

---

## Why Local Models

Entry-level MacBooks have crossed a threshold. Llama 3.2 3B runs comfortably on an M1 Mac Air — fast enough to process 30-second transcript chunks in real time, accurate enough to classify intent and extract structure from natural speech.

The key insight is the cost model. Cloud AI is priced per token, which creates friction. Local inference costs electricity — fixed regardless of how often you run it. That changes the calculus entirely.

When inference is abundant and free, you can run it continuously. Continuously running it means understanding context without being prompted. Understanding context without being prompted is the foundation of ambient intelligence.

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

**Optional — WhatsApp integration:**
```bash
cd WhatsAppSidecar && npm install && npm start
```

**Optional — Groq transcription (faster, cloud):**

Set `GROQ_API_KEY` in `~/.zshenv` or via the Settings panel.

---

## Shortcuts

| Shortcut | Action |
|---|---|
| `⌃Z` | Toggle microphone |
| `⌃1` | Ambient Intelligence mode |
| `⌃2` | Transcription-only mode |
| `⌃3` | AI Search mode |
| `⌃4` | Claude Code co-pilot mode |
| Right-click pill | Full context menu |
| `hot <kw> for project <N> <task>` | Create todo via voice |

---

## Architecture

```
AutoClawd.app (Swift/SwiftUI)
│
├── PillWindow          floating NSPanel (always on top, snap-to-edge)
├── MainPanelWindow     dashboard — pipeline log, tasks, settings
├── ToastWindow         non-intrusive execution feedback
│
├── AudioRecorder       30-second chunks from always-on mic
│        │
│        ▼
├── PipelineOrchestrator
│        │
│        ├── Stage 1: TranscriptCleaningService   (local Llama 3.2)
│        │     merge overlapping chunks, denoise, resolve speakers
│        │
│        ├── Stage 2: TranscriptAnalysisService   (local Llama 3.2)
│        │     project detection, priority, tags, task extraction
│        │
│        ├── Stage 3: TaskCreationService
│        │     structured tasks with mode: auto / ask / user
│        │
│        └── Stage 4: TaskExecutionService        (Claude Code)
│              autonomous execution, streamed output
│
├── WhatsAppPoller      polls local sidecar every 2s, self-chat only
├── TranscriptStore     SQLite persistence
├── PipelineStore       pipeline record persistence
├── SettingsManager     UserDefaults + Keychain API keys
│
└── PixelWorld (WebKit overlay)
      Mission Control HQ — live canvas visualization
      Agents queue at TV wall → walk desk-to-desk as pipeline fires
      Desks: Comms · Analysis · Projects · Claude Code · QA · Archive
```

**Pipeline sources:**

| Source | Stages run |
|---|---|
| `.ambient` | clean → analyze → task → execute |
| `.transcription` | clean only |
| `.code` | save transcript + Claude Code task; skip LLM analysis |
| `.whatsapp` | clean → analyze → task → execute + WhatsApp reply |

**Task modes:**

| Mode | Behaviour |
|---|---|
| `auto` | executes immediately, no approval needed |
| `ask` | surfaces in dashboard for user confirmation |
| `user` | created but never auto-executed |

---

## Storage

All data lives in `~/.autoclawd/` — SQLite databases and markdown files, fully local.

```
~/.autoclawd/
  world-model.md        compounding knowledge base (per project)
  transcripts.db        raw and cleaned transcripts
  pipeline.db           pipeline stage records
  structured_todos.db   task queue with status history
```

---

## Roadmap

- [ ] Phone call transcription via Bluetooth mic
- [ ] Screen context — periodic screenshot for richer extraction
- [ ] MCP server — expose AutoClawd memory to any MCP-compatible tool
- [ ] Multi-language transcription
- [ ] Execution history and re-run support
- [ ] Scheduled tasks — assign times, show on system calendar
- [ ] Location and people tagging in world model
- [x] Auto-project matching
- [x] WhatsApp self-chat integration
- [x] Mission Control HQ pipeline visualization
- [x] Multi-mode pill (ambient / transcription / search / code)
- [x] Configurable autonomous task rules

---

## License

MIT — build on it, fork it, ship it.
