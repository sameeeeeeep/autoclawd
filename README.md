# AutoClawd

**Ambient AI that works without being prompted.**

AutoClawd is a macOS app that runs an always-on microphone in the background, transcribes everything you say, builds a compounding memory of your life and work, and autonomously executes tasks using AI — without you ever needing to open a chat window or type a prompt.

---

## The Idea

The bottleneck in AI adoption isn't capability — it's friction. You have to know what to ask, know which tool to use, and remember to do it. AutoClawd removes all three.

It listens to your day. It figures out what needs to happen. It does it.

The intelligence runs locally (Llama 3.2 3B via Ollama) on an entry-level MacBook. Local models have crossed the threshold where they're smart enough to contextualise conversation and extract structured intent — and since local compute comes at the cost of electricity rather than per-token pricing, it can run continuously without a subscription meter ticking.

This enables a zero-prompt, zero-lag system: no interface to open, no request to formulate, no copy-paste between tools.

---

## How It Works

```
Microphone → Transcription → LLM Extraction → World Model + Todos
                                                        ↓
                                              Claude Code CLI execution
```

**Step 1 — Listen.** Audio is captured in 30-second chunks by an always-on mic. No audio leaves your machine unless you're using Groq mode.

**Step 2 — Transcribe.** Each chunk is transcribed by either:
- **Groq Whisper** (fast, cloud, ~$0 at low volume), or
- **Apple SFSpeechRecognizer** (fully offline, no data leaves device)

**Step 3 — Extract.** A two-pass LLM pipeline runs against recent transcript chunks:
- *Pass 1* classifies each idea as `fact`, `todo`, `world`, `preference`, or `question`
- *Pass 2* synthesises accepted items, updating `world-model.md` and `todos.md`

**Step 4 — Execute.** Extracted todos are stored with priority and assigned to a project. Tapping ▶ runs `claude --print <task>` in the project's local folder with your Anthropic API key — giving Claude Code full context of the codebase.

All data is stored locally at `~/.autoclawd/`.

---

## Features

### Ambient Intelligence
- Always-on microphone with voice activity detection
- 30-second rolling transcript chunks with session continuity labels (A/B/C context carry-over)
- Automatic synthesis when pending items exceed a configurable threshold

### World Model
- Persistent markdown knowledge base (`~/.autoclawd/world-model.md`)
- Accumulates facts about people, projects, plans, preferences, and decisions
- Graph visualisation of entities and relationships

### Structured Todos
- Todos extracted from speech, tagged HIGH / MEDIUM / LOW priority
- Assigned to named **Projects** with local folder paths
- One-tap execution via Claude Code CLI (`claude --print`)
- Streamed output view — watch the agent work in real time

### AI Search
- Ask anything about your own life context
- Answers grounded in your world model and recent transcripts via local Ollama

### Pill Widget
- Floating always-on-top pill (like Dynamic Island on Mac)
- SF Symbol mode icons: 🧠 ambient / ✍️ transcription / 🔍 search
- 6px state dot — neon green (live), amber (processing), dim (paused)
- Appearance modes: Frosted / Transparent / Dynamic (blurs when active)
- Global hotkeys: `⌃Z` toggle mic, `⌃1/2/3` switch mode

### Privacy-First
- All processing is local by default
- Groq transcription is opt-in; key stored in macOS Keychain
- No analytics, no telemetry, no cloud sync
- Audio files auto-purged after configurable retention window (3 / 7 / 30 days)

---

## Requirements

| Requirement | Detail |
|---|---|
| macOS | 13 Ventura or later |
| Architecture | Apple Silicon (M1+) or Intel |
| Ollama | [ollama.ai](https://ollama.ai) with `llama3.2:3b` pulled |
| Transcription | Groq API key (optional) or built-in Apple speech |
| Task execution | `claude` CLI — `npm install -g @anthropic-ai/claude-code` |

---

## Installation

```bash
# 1. Clone
git clone https://github.com/sameeeeeeep/autoclawd.git
cd autoclawd

# 2. Install Ollama and pull the model
brew install ollama
ollama pull llama3.2:3b

# 3. Build
make all

# 4. Run
open build/AutoClawd.app
```

On first launch, the setup assistant checks for Ollama and guides you through permissions (microphone, accessibility for hotkeys).

---

## Configuration

All settings are in the **Settings** tab of the main panel.

| Setting | Default | Notes |
|---|---|---|
| Transcription mode | Groq | Switch to Local for full offline operation |
| Groq API key | — | Stored in Keychain |
| Anthropic API key | — | Required for Claude Code task execution |
| Synthesis threshold | 10 items | Auto-synthesise after N pending todos |
| Audio retention | 7 days | WAV files purged automatically |
| Pill appearance | Frosted | Frosted / Transparent / Dynamic |

---

## Project Structure

```
Sources/
├── AppState.swift              # Central observable state
├── ChunkManager.swift          # Audio chunking + pipeline orchestration
├── ExtractionService.swift     # Two-pass LLM extraction pipeline
├── ProjectStore.swift          # SQLite project registry
├── StructuredTodoStore.swift   # SQLite structured todo list
├── ClaudeCodeRunner.swift      # claude CLI invocation (AsyncThrowingStream)
├── TranscriptStore.swift       # SQLite transcript history
├── ExtractionStore.swift       # SQLite extraction items
├── PillView.swift              # Floating pill widget UI
├── MainPanelView.swift         # Main panel with all tabs
├── WorldModelGraphView.swift   # Entity graph visualisation
├── QAView.swift                # AI search interface
├── SessionTimelineView.swift   # Session history
└── ...
```

---

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `⌃Z` | Toggle microphone on/off |
| `⌃1` | Switch to Ambient Intelligence mode |
| `⌃2` | Switch to AI Search mode |
| `⌃3` | Switch to Transcription mode |
| Right-click pill | Context menu |

---

## Roadmap

- [ ] Phone integration (call transcription via mic)
- [ ] Screen context (optional screen capture for richer extraction)
- [ ] Multi-language transcription
- [ ] MCP server support (connect AutoClawd memory to any AI tool)
- [ ] Execution history and re-run failed tasks
- [ ] Auto-link extracted todos to projects by keyword matching

---

## Philosophy

Current AI systems assume you know what you want and can articulate it clearly. Most people can't — not because they're not capable, but because the cognitive overhead of prompt engineering is a new skill that most haven't developed.

Three things block AI diffusion at scale:
1. **Understanding of use cases** — people don't know what AI can do for their specific situation
2. **Understanding of tools** — people don't know which tool to use for which task
3. **Execution lag** — switching to an AI interface breaks flow

AutoClawd removes all three by making AI ambient. It observes context, infers intent, and executes — the same way a great assistant would. You talk. It listens. Things get done.

---

## License

MIT
