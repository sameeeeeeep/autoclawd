<div align="center">
  <img src="Resources/autoclawd-mascot.svg" width="100" alt="Clawd the lobster" />

  # AutoClawd

  **Ambient AI for macOS. Works without being prompted.**

  [![macOS](https://img.shields.io/badge/macOS-13%2B-black?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/macos/)
  [![Swift](https://img.shields.io/badge/Swift-5.9-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
  [![Ollama](https://img.shields.io/badge/Ollama-llama3.2:3b-5C6BC0?style=flat-square)](https://ollama.ai)
  [![License: MIT](https://img.shields.io/badge/License-MIT-22c55e?style=flat-square)](LICENSE)

</div>

---

AutoClawd listens to your day, builds a compounding memory of your work and life, extracts what needs doing, and executes it using AI — without you ever opening a chat window or typing a prompt.

All intelligence runs locally on your Mac. No subscriptions. No prompting. No friction.

---

## Demo

<div align="center">

> 📹 **Demo video coming soon** — being recorded with Remotion

</div>

---

## How It Works

```
Mic → Transcription → LLM Extraction → World Model + Todos → Execution
```

**1. Listen** — Always-on mic captures audio in 30-second chunks. Nothing leaves your machine by default.

**2. Transcribe** — Groq Whisper for speed, or Apple SFSpeechRecognizer for fully offline operation.

**3. Extract** — Local Llama 3.2 3B classifies ideas into facts, todos, preferences, and world model updates across two passes.

**4. Execute** — Todos are tagged with priority, assigned to projects, and run via `claude --print` in the right folder — streamed output, no switching context.

---

## Install

```bash
# 1. Install Ollama and pull the model
brew install ollama && ollama pull llama3.2:3b

# 2. Clone and build
git clone https://github.com/sameeeeeeep/autoclawd.git
cd autoclawd && make all

# 3. Run
open build/AutoClawd.app
```

On first launch, the setup assistant checks for Ollama and walks through mic + accessibility permissions.

---

## Shortcuts

| Shortcut | Action |
|---|---|
| `⌃Z` | Toggle microphone |
| `⌃1 / 2 / 3` | Switch mode (Ambient / Search / Transcription) |
| Right-click pill | Full context menu |

---
<br />

---

## The Problem

Three things block AI adoption at scale — not capability, not cost, not trust.

**1. Understanding of use cases.** Most people can't map their specific situation to an AI tool. They know ChatGPT exists. They don't know what to ask it about the thing they're currently stuck on.

**2. Understanding of tools.** The landscape fragments weekly. Knowing that an AI *could* help doesn't tell you whether to use Claude, Cursor, Perplexity, or a custom workflow. Navigating that is a skill most people haven't developed.

**3. Execution lag.** Switching to an AI interface breaks flow. By the time you've opened a tab, framed a prompt, and waited for output, the context in your head has shifted. The cost of the switch often exceeds the value of the help.

AutoClawd removes all three by making AI ambient. It observes context, infers intent, and acts — without requiring you to know what to ask, which tool to use, or when to stop and ask for help.

---

## Why Local Intelligence

Entry-level MacBooks have crossed a threshold. Llama 3.2 3B runs comfortably on an M1 Mac Air — fast enough to process 30-second transcript chunks in real time, smart enough to classify intent and extract structure from natural speech.

The key insight is the cost model. Cloud AI is priced per token, which creates friction: every inference has a cost, so you gate when you invoke it. Local inference costs electricity, which is effectively fixed regardless of how often you run it. That changes the calculus entirely.

When inference is abundant and cheap, you can run it continuously. Continuously running it means you can understand context without being prompted. Understanding context without being prompted is the foundation of ambient intelligence.

This is the transition from *AI as a tool you pick up* to *AI as infrastructure that runs in parallel with your life.*

---

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                     AutoClawd                        │
│                                                      │
│  AudioRecorder (30s chunks)                          │
│       │                                              │
│       ▼                                              │
│  TranscriptionService  ──── Groq Whisper             │
│       │                └─── Apple SFSpeechRecognizer │
│       ▼                                              │
│  ChunkManager                                        │
│       │                                              │
│       ▼                                              │
│  ExtractionService  (two-pass local LLM)             │
│    Pass 1: classify → ExtractionItems                │
│    Pass 2: synthesise → world-model.md + todos       │
│       │                                              │
│       ├──▶ WorldModelService   (markdown KB)         │
│       ├──▶ StructuredTodoStore (SQLite)              │
│       └──▶ ExtractionStore    (SQLite)               │
│                                                      │
│  ClaudeCodeRunner                                    │
│    claude --print <todo> in project folder           │
│    ANTHROPIC_API_KEY injected, streamed output       │
│                                                      │
│  Storage: ~/.autoclawd/                              │
│    world-model.md  projects.db  structured_todos.db  │
│    transcripts.db  intelligence.db                   │
└──────────────────────────────────────────────────────┘
```

**Key decisions:**

- **SQLite over cloud DB** — all data stays on device, zero latency, works offline
- **Markdown for world model** — LLM reads/writes it directly, human-readable, diffs cleanly in git
- **Two-pass extraction** — Pass 1 is fast classification, Pass 2 is slower synthesis. Decoupled so classification runs on every chunk, synthesis runs on a threshold
- **AsyncThrowingStream for execution** — Claude Code output streams line-by-line into the UI, no blocking
- **Keychain for secrets** — API keys stored via SecItem, encrypted at rest, never in files or env

---

## Roadmap

- [ ] Phone integration — call transcription via Bluetooth mic
- [ ] Screen context — optional periodic screenshot for richer extraction
- [ ] MCP server — expose AutoClawd memory to any MCP-compatible AI tool
- [ ] Auto-project matching — link extracted todos to projects by keyword/path inference
- [ ] Multi-language transcription
- [ ] Execution history and re-run support

---

## License

MIT — build on it, fork it, ship it.
