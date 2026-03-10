# AutoClawd — CLAUDE.md

AutoClawd is a macOS ambient AI agent. It runs as a floating pill widget with an always-on microphone and a background pipeline that listens to conversations, transcribes them with local AI models, extracts tasks, and executes them autonomously via Claude Code — without the user ever typing a prompt.

## Core Concept

- **Always-on mic** → captures 30-second audio chunks continuously with live word-by-word streaming
- **Always-on screen** → OCR + accessibility tree watching for context; detects app switches, URLs, text
- **Always-on intelligence** → local Llama 3.2 cleans and analyzes every transcript
- **Zero-prompt execution** → tasks are created and auto-run based on what was said/seen, not what was asked
- **FUCBC** → Find Use-Case, Build Capability: watches workflows, builds executable SKILL.md automations
- **Agents** → library of built capabilities, one click to run from the Agents panel or the pill suggestion popup
- **Workflows** → chains of capabilities with input specs; user provides context + references → runs end-to-end
- **World model** → persistent per-project knowledge base built from every conversation
- **Mission Control HQ** → live pixel-art visualization of the pipeline

## Build & Run

```bash
# Build (ad-hoc signed, no provisioning needed)
make

# Build + run immediately
make run
```

The Makefile copies the built bundle to `build/AutoClawd.app`. To install permanently: `cp -r build/AutoClawd.app /Applications/`.

The WhatsApp sidecar is a separate Node.js process:
```bash
cd WhatsAppSidecar && npm install && npm start
```

---

## Architecture

### Process Layout
```
AutoClawd.app (Swift/SwiftUI macOS app)
  └── PillWindow            floating NSPanel widget (always on top)
  └── MainPanelWindow       main dashboard (opens on pill tap)
  └── ToastWindow           notification toasts
  └── SetupWindow           first-run dependency setup
  └── PixelWorld (WebKit)   Mission Control HQ canvas overlay

WhatsApp Sidecar (Node.js/Express on localhost:7891)
  └── Baileys WA Web client → buffers messages → polled every 2s

AutoClawd MCP Server (Swift HTTP on localhost:7892)
  └── screen context, cursor context, selection, audio transcript tools
```

### Pipeline Flow
```
[Mic] → AudioRecorder → ChunkManager → PipelineOrchestrator
                               │                   │
                    StreamingLocalTranscriber  ┌────▼──────────────┐
                    (live partials via         │ Stage 1: Cleaning  │  TranscriptCleaningService
                     SFSpeechRecognizer)       │  local Llama 3.2   │  merge chunks, denoise,
                                               │                    │  resolve speaker context
                                               └────────┬───────────┘
                                                        │  fires onTranscriptionCleaned for ALL sources
                                                        │  (transcription mode stops here)
                                               ┌────────▼───────────┐
                                               │ Stage 2: Analysis  │  TranscriptAnalysisService
                                               │  local Llama 3.2   │  project, priority, tags,
                                               │                    │  tasks, world model update
                                               └────────┬───────────┘
                                                        │
                                               ┌────────▼───────────┐
                                               │ Stage 3: Task      │  TaskCreationService
                                               │  Creation          │  mode: auto / ask / user
                                               └────────┬───────────┘
                                                        │  (code mode stops here)
                                               ┌────────▼───────────┐
                                               │ Stage 4: Execution │  TaskExecutionService
                                               │  Claude Code SDK   │  streamed output, auto tasks
                                               └────────────────────┘

[Screen] → ScreenVisionAnalyzer → OCR + AX tree
                                        │
                              CapabilityStore.suggest()
                                        │
                              AppState.detectedCapability
                                        │
                         CapabilitySuggestionCanvasView  ← "Automate Now?" pill popup
```

### FUCBC — Capability Learning Loop
```
[LearnMode active]
  │
  Every 5s: LearnEvent captured
    (app name, window title, detected URLs, OCR snippet, SFSpeech partial)
  │
  User signals "build" (or enough context accumulated)
  │
  LearnModeService.buildCapability()
    │
    buildUserJourney()     ← transforms raw events into coherent narrative
      "T+0s → User opened Threads · Screen: 'New Llama 3.3 from Meta'"
      "T+5s → User navigated to youtube.com · User said: 'I should try this'"
    │
    buildFUCBCPrompt()     ← story + MCP tools + social media API examples
      instructs Claude Code to write executable SKILL.md
    │
    ClaudeCodeRunner.startSession(prompt, in: openClawDir)
      Claude writes: ~/.autoclawd/openclaw-skills/{slug}/SKILL.md
      Claude outputs: JSON manifest
    │
    CapabilityStore.save(capability)
      → posts capabilityStoreDidChange notification
      → AgentsView reloads grid
      → MainPanelView auto-navigates Canvas → Agents tab
```

### Pipeline Sources (PipelineSource enum)
Each transcript carries a source tag that controls which stages run:
- `.ambient` — full pipeline (clean → analyze → task → execute)
- `.transcription` — clean only (merge/denoise; no task creation)
- `.code` — save transcript + Claude Code task; skip LLM analysis
- `.whatsapp` — full pipeline (same as ambient, with QA reply)

### Transcript Session State (AppState)

Three layers of live transcript text accumulate in the widget across ALL modes:

| Property | Source | Opacity |
|----------|--------|---------|
| `liveTranscriptText` | cleaned chunks from Ollama (all sources) | full |
| `pendingRawSegment` | committed audio not yet through Ollama | medium |
| `latestTranscriptChunk` | live SFSpeech streaming partial | faint/italic |

Session lifecycle:
- `onTranscriptionCleaned` fires for ALL pipeline sources, appending to `liveTranscriptText`
- After each chunk cycle, if `Date().timeIntervalSince(lastSpeechTime) >= 10.0`, session ends: `clearSessionTranscript()` is called
- Mode changes do NOT clear the transcript — only silence-end and the manual Clear button do

### Local AI Model Usage

| Stage | Model | Provider | Purpose |
|-------|-------|----------|---------|
| Transcription (streaming) | SFSpeechRecognizer | Apple (local) | Live word-by-word partials |
| Transcription (committed) | Whisper | Groq (cloud) or Apple SFSpeech (local) | Final chunk text |
| Cleaning | Llama 3.2 3B | Ollama (local) | Merge, denoise, resolve context |
| Analysis | Llama 3.2 3B | Ollama (local) | Extract tasks, update world model |
| Task framing | Llama 3.2 3B | Ollama (local) | Clean task titles from README/CLAUDE.md |
| FUCBC story + prompt | Llama 3.2 3B | Ollama (local) | Build user journey narrative |
| Capability building | Claude Code | Anthropic API | Write executable SKILL.md |
| Execution | Claude Code | Anthropic API | Run tasks in project folders |

---

## FUCBC — Capability & Workflow System

### Three-Tier Model

| Tier | Name | Definition | Examples |
|------|------|------------|---------|
| 1 | **Skill** | An atomic unit — often just Claude by itself, or a single CLI tool invocation | "Write a tweet thread", `yt-dlp {url}`, `video2ai {file}`, "Summarise PDF" |
| 2 | **Capability** | One or more Skills **combined with tool access** — built by FUCBC from observed usage | "Post to all platforms" (Threads + Twitter + Buffer), "Ingest reference video" (video2ai + Claude) |
| 3 | **Workflow** | AutoClawd + an ordered sequence of Skills and Capabilities + Claude Code → **delivers a real output** | "Launch Video" (8 capabilities in sequence, 1-click from 10-step manual process) |

**Key insight:** A Skill is something Claude can do alone. A Capability is a Skill that also needs a specific external tool. A Workflow is what AutoClawd assembles from Capabilities (and Skills) automatically — then hands to the user as a repeatable 1-click automation.

### Data Model

```swift
// Tier 1 — Skill (OpenClaw skill library)
// Lives in ~/.autoclawd/openclaw-skills/{slug}/SKILL.md
// Created by: built-in seeding, FUCBC auto-discovery, manual authoring
SKILL.md contents:
  name, description, invocation   // shell command or Claude prompt template
  inputs, outputs                  // what it takes, what it produces
  workflowTags: [String]          // ["video-production", "content-creation"]
  source: github | builtin | observed   // where this skill came from

// Tier 2 — Capability (CapabilityStore)
// Stored in ~/.autoclawd/capabilities/index.json
Capability                    // a FUCBC-built modular automation (Skill + tool access)
  ├── id, name, description, emoji, category
  ├── triggers: CapabilityTriggers
  │     ├── apps: [String]         // e.g. ["Threads", "Safari", "Twitter"]
  │     ├── urlPatterns: [String]  // e.g. ["threads.net", "x.com"]
  │     ├── keywords: [String]     // e.g. ["launch video", "post this"]
  │     └── ocrPatterns: [String]  // e.g. ["New Post", "Create thread"]
  ├── subWorkflows: [SubWorkflow]  // the Skill-level steps inside this capability
  │     └── { name, description, invocation: String? }  // shell cmd or skill slug
  └── skillMDPath: String?         // path to ~/.autoclawd/openclaw-skills/{slug}/SKILL.md

// Tier 3 — Workflow (WorkflowStore) — UPCOMING Phase 3
// Stored in ~/.autoclawd/workflows/index.json
Workflow
  ├── id, name, description
  ├── steps: [WorkflowStep]        // ordered Capability / Skill references
  ├── inputSpec: WorkflowInputSpec
  │     ├── references: [ReferenceField]   // "Target URL", "Reference videos"
  │     ├── contextField: String           // free text ("launch video for AI startup")
  │     └── projectSelection: Bool
  └── createdFrom: .observed | .manual | .prebuilt
```

### Storage

```
~/.autoclawd/
  capabilities/
    index.json              ← all Capability records (CapabilityStore)
  openclaw-skills/
    {slug}/
      SKILL.md              ← executable skill written by Claude Code via FUCBC
  workflows/                ← UPCOMING: WorkflowRecord storage
    index.json
```

### OCR Auto-Trigger (CapabilityStore.suggest)

Every OCR frame in `ScreenVisionAnalyzer` calls:
```swift
CapabilityStore.shared.suggest(screenText: ocr, app: appName, urls: urls)
```
Scoring per capability: +4 app match, +3 URL pattern, +2 OCR pattern, +1 keyword.
If best score ≥ 3: sets `AppState.detectedCapability` → pill shows `CapabilitySuggestionCanvasView`.

### Pill Suggestion Popup (CapabilitySuggestionCanvasView)

"Automate Now?" overlay on the pill widget:
- App icon strip (up to 4 trigger apps, SF Symbol + color-coded)
- Question-form title: `"Post to all platforms?"`
- One-liner: `"AutoClawd can automate this."`
- Full-width "Automate Now" button → `AppState.executeCapability(cap)`
- X dismiss → `AppState.dismissDetectedCapability()`
- Wired into `AppDelegate.canvasForCurrentMode` priority chain (above mode-specific canvas)

### Agents Panel (AgentsView)

"My Agents" — panel-level grid of all built capabilities:
- Accessible via "Agents" tab in MainPanelView sidebar (⚡ bolt.fill)
- 3-column `LazyVGrid` of `AgentCard` views
- Each card: app icon strip, bold title, description, step count, category pill, ▶ Run button
- Run → `AppState.executeCapability()` → streams live on `canvasExecutingTask` canvas
- Auto-navigates Canvas → Agents when `capabilityStoreDidChange` fires
- Empty state: CTA to switch to Canvas and record a session

### Capability Execution (AppState.executeCapability)

```swift
func executeCapability(_ capability: Capability)
```
1. Clears `detectedCapability`
2. Resolves project (`projects.first` fallback)
3. Builds prompt: uses `skillMDPath` if present ("Read and execute SKILL.md"), else constructs from sub-workflow invocations
4. Creates `PipelineTaskRecord` (id: `CAP-{8hex}`)
5. Prepends to `pipelineTasks` (visible in LogsPipelineView)
6. Starts `claudeCodeRunner.startSession()` → streams via `canvasExecutingTask` machinery

---

## Phase 3 Roadmap — Workflow Intelligence

### The Problem

A social media manager builds a launch video manually every time:
1. Goes to YC to find reference videos → downloads them (yt-dlp)
2. Tries to upload to Claude → "I can't read videos" error
3. Uploads to video2ai → gets frames + transcript
4. Asks Claude for content strategy with brand context
5. Builds motion graphics in Canva with Remotion
6. Generates AI voice on Freepik
7. Assembles voice + graphics in Canva, matches segment lengths
8. Downloads final video → uploads to Google Drive
9. Shares Drive link on team WhatsApp

**AutoClawd watches this entire workflow. It should never have to happen manually again.**

### Phase 3 Architecture

```
Observed workflow (FUCBC)
  │
  CapabilityStore: detect + save each atomic capability
    ├── yt-dlp-downloader      (downloads videos by URL)
    ├── video2ai-ingest        (frames + transcript from video, NEW skill discovered → auto-creates SKILL.md)
    ├── claude-content-strategy (Claude with context + references → strategy doc)
    ├── remotion-motion-graphic (React/Remotion animation from script)
    ├── freepik-ai-voice        (TTS from script)
    ├── ffmpeg-video-assembler  (merge voice + video, match segment lengths)
    ├── gdrive-upload           (upload file → get shareable link)
    └── whatsapp-share          (send message with link to group/contact)
  │
  WorkflowBuilder: "these capabilities appeared in sequence with shared context"
    → creates WorkflowRecord: "Launch Video"
    → inputSpec: { references: ["Target URL / topic"], context: "launch video brief", project: true }
  │
  WorkflowRecord saved → "Launch Video" appears in Agents panel
```

### Skill Discovery

When FUCBC encounters a tool AutoClawd hasn't seen before (e.g. `video2ai --web`):
1. Detects usage from OCR + URL + app context
2. Checks `~/.autoclawd/openclaw-skills/` — no matching slug
3. **Web search + GitHub research:** FUCBC prompts Claude Code to search for the tool on GitHub (or its docs), analyse its README, understand its CLI interface and output format
4. Creates new SKILL.md via Claude Code: documents the tool, its CLI args, how to invoke it, input/output spec
5. Tags which workflow patterns this skill could be part of (`workflowTags: ["video-production", "content-creation"]`)
6. Capability appears in `AgentsView` immediately

**GitHub as the canonical source of tools:**
Every tool in the skill library ultimately comes from GitHub. The discovery flow:
```
User is observed using an unfamiliar tool
  │
  FUCBC → "I don't know this tool. Let me research it."
  │
  Web search: "video2ai github" / "yt-dlp github"
  │
  Fetch GitHub README → analyse: CLI args, input/output, install method
  │
  Create ~/.autoclawd/openclaw-skills/{slug}/SKILL.md
  │
  Tag: workflowTags, category, requiredTools (pip/npm/brew install instructions)
  │
  Skill is immediately available for Capability and Workflow assembly
```

Pre-curated categories in the library:
- **Video & Audio** — yt-dlp, video2ai, ffmpeg, whisper-cli, freepik-voice
- **Content & Publishing** — remotion, imagemagick, pandoc, markdownlint
- **Communication** — whatsapp-baileys, slack-bolt, gmail-send, discord-webhook
- **Storage & Files** — gdrive-upload, dropbox-api, s3-upload, notion-create
- **Code & Dev** — gh-cli, git-auto, linear-api, jira-api, vercel-deploy
- **Data & Research** — firecrawl, playwright-scraper, exa-search, tavily-api
- **AI & Processing** — ollama-run, claude-code, openai-api, replicate-api

**video2ai** is the first example: a Python CLI + web UI (`video2ai --web`) that converts any `.mp4` into AI-ingestable format: extracted frames + Whisper transcript + Ollama frame analysis + contact sheets. Lives at `~/.autoclawd/openclaw-skills/video2ai/`.

### Workflow Execution Model (Upcoming)

```
User opens "Launch Video" workflow in Agents panel
  │
  WorkflowInputView: upload references + type context + select project
    "References: [youtube.com/ycombinator...] Context: 'product launch for AI writing tool'"
  │
  WorkflowExecutor runs steps in sequence:
    Step 1: yt-dlp-downloader(urls) → /tmp/references/*.mp4
    Step 2: video2ai-ingest(videos) → frames[], transcript
    Step 3: claude-content-strategy(transcript, context, brand) → strategy.md
    Step 4: remotion-motion-graphic(strategy) → video.mp4
    Step 5: freepik-ai-voice(script) → voice.mp3
    Step 6: ffmpeg-video-assembler(video, voice) → final.mp4
    Step 7: gdrive-upload(final.mp4) → drive_url
    Step 8: whatsapp-share(drive_url, group="Team") → sent
  │
  Each step streams live on canvasExecutingTask
  Outputs flow between steps via WorkflowContext dict
```

### New Files Needed (Phase 3)

| File | Purpose |
|------|---------|
| `WorkflowRecord.swift` | `WorkflowRecord`, `WorkflowStep`, `WorkflowInputSpec` value types |
| `WorkflowStore.swift` | Persists workflows to `~/.autoclawd/workflows/index.json` |
| `WorkflowBuilder.swift` | Infers workflows from sequences of observed capabilities |
| `WorkflowExecutor.swift` | Runs a workflow with inputs, passes context between steps |
| `WorkflowInputView.swift` | UI for collecting workflow inputs (references + context + project) |
| `SkillDiscoveryService.swift` | Detects new tools from OCR/URLs, auto-creates SKILL.md |

---

## Key Files

### Core App
| File | Purpose |
|------|---------|
| `App.swift` | SwiftUI `@main` entry point (headless — no default window) |
| `AppDelegate.swift` | NSApplicationDelegate; creates all windows, wires subscriptions |
| `AppState.swift` | Central `ObservableObject` — all shared state, service singletons |
| `AppFonts.swift` | Custom font registration and font accessors |
| `AppTheme.swift` | Appearance system — frosted/solid modes, color scheme, theme tokens |
| `LiquidGlass.swift` | Glass design system: `LiquidGlassCard`, `GlassButton`, `GlassChip`, `Glass.textPrimary/Secondary/Tertiary` |
| `Logger.swift` | Structured logging with subsystems: `.pipeline`, `.system`, `.audio`, `.ui`, `.camera` |

### Pipeline
| File | Purpose |
|------|---------|
| `PipelineOrchestrator.swift` | Routes transcripts through the 4-stage pipeline |
| `PipelineModels.swift` | Core value types: `CleanedTranscript`, `TranscriptAnalysis`, `PipelineTaskRecord` |
| `PipelineStore.swift` | Persistence layer for pipeline data |
| `PipelineGroup.swift` | Groups related pipeline records for display |
| `ChunkManager.swift` | Buffers audio chunks, manages session lifecycle, calls PipelineOrchestrator |
| `StreamingLocalTranscriber.swift` | Live word-by-word SFSpeechRecognizer streaming; fires `onPartial` callbacks |
| `TranscriptCleaningService.swift` | Stage 1: Ollama Llama 3.2 transcript cleaning |
| `TranscriptAnalysisService.swift` | Stage 2: Ollama Llama 3.2 analysis, task extraction, world model update |
| `TaskCreationService.swift` | Stage 3: structured task creation with mode assignment |
| `TaskExecutionService.swift` | Stage 4: streams Claude Code sessions for auto tasks |
| `ClaudeCodeRunner.swift` | Low-level Claude Code SDK streaming client |
| `WorkflowRegistry.swift` | Registered execution workflows (e.g. `autoclawd-claude-code`) |

### FUCBC — Capability System
| File | Purpose |
|------|---------|
| `LearnModeModels.swift` | `LearnEvent`, `Capability`, `CapabilityCategory`, `CapabilityTriggers`, `SubWorkflow`, `LearnSession`, `CapabilityManifest` |
| `LearnModeService.swift` | FUCBC service: 5s event timer, `buildUserJourney()`, `buildFUCBCPrompt()`, `buildCapability()` |
| `CapabilityStore.swift` | Persists capabilities to `~/.autoclawd/capabilities/index.json`; `suggest()` for auto-trigger scoring |
| `AICanvasView.swift` | Canvas tab: endless node graph + capabilities grid subtabs; `capabilitiesTabView` |
| `AgentsView.swift` | "My Agents" panel: 3-col `LazyVGrid` of `AgentCard`; ▶ Run → `executeCapability()` |

### Audio & Transcription
| File | Purpose |
|------|---------|
| `AudioRecorder.swift` | Always-on AVAudioEngine capture; engine stays hot between chunks |
| `SystemAudioCapturer.swift` | ScreenCaptureKit system audio + screen preview capture; `SystemAudioMixer` for thread-safe mixing |
| `SpeechService.swift` | Groq / Apple SFSpeech transcription of committed audio chunks |
| `TranscriptionService.swift` | Transcription orchestration |
| `TranscriptionPasteService.swift` | Paste cleaned transcript to frontmost app |

### Storage & Persistence
| File | Purpose |
|------|---------|
| `TranscriptStore.swift` | SQLite transcript persistence |
| `PipelineStore.swift` | Pipeline record persistence |
| `StructuredTodoStore.swift` | Task queue with status history |
| `QAStore.swift` | Q&A session persistence |
| `ExtractionStore.swift` | Extraction result persistence |
| `ContextCaptureStore.swift` | Clipboard and screenshot context persistence |
| `SessionStore.swift` | Speaking session timeline persistence |
| `ProjectStore.swift` | Project list and metadata |
| `SkillStore.swift` | Built-in and custom skills persistence |
| `FileStorageManager.swift` | Attachment and file storage management |

### World Model & Intelligence
| File | Purpose |
|------|---------|
| `WorldModelService.swift` | Builds and updates per-project markdown world model |
| `WorldModelGraph.swift` | Graph data model parsed from world model markdown |
| `WorldModelGraphParser.swift` | Parses markdown world model into graph nodes/edges |
| `WorldModelGraphLayout.swift` | Force-directed layout for world model graph |
| `WorldModelGraphView.swift` | SwiftUI canvas graph visualization |
| `ExtractionService.swift` | Extracts structured facts, decisions, people from transcripts |
| `ExtractionItem.swift` | Extraction result value type |
| `Episode.swift` | A discrete event (song, place, person) captured in context |
| `NowPlayingService.swift` | ShazamKit song detection; creates Episodes |
| `PeopleTaggingService.swift` | Identifies and tags people mentioned in transcripts |
| `Person.swift` | Person value type |

### Context Capture
| File | Purpose |
|------|---------|
| `ScreenshotService.swift` | Periodic screen capture for ambient context |
| `ScreenVisionAnalyzer.swift` | OCR + accessibility tree analysis; feeds CapabilityStore.suggest() |
| `ClipboardMonitor.swift` | Monitors clipboard changes for context enrichment |
| `LocationService.swift` | Core Location — current place detection |
| `PlaceDetail.swift` | Place value type |

### Q&A & Skills
| File | Purpose |
|------|---------|
| `QAService.swift` | Handles AI search / Q&A queries against transcript context |
| `QAView.swift` | Q&A results UI |
| `Skill.swift` | Skill value type (built-in + custom) |
| `SkillStore.swift` | Skill persistence, seeding built-in skills on install |

### Todo & Task Management
| File | Purpose |
|------|---------|
| `TodoService.swift` | Todo list management |
| `TodoFramingService.swift` | Frames task titles using README/CLAUDE.md for context |
| `StructuredTodoStore.swift` | Persists structured task queue |

### UI — Windows & Shell
| File | Purpose |
|------|---------|
| `PillView.swift` | Floating widget SwiftUI view |
| `PillWindow.swift` | NSPanel wrapper with drag, snap-to-edge, height animation |
| `PillMode.swift` | `PillMode` enum and transitions |
| `MainPanelView.swift` | Main dashboard shell; tabs: World / Agents / Canvas / Projects / Logs / Settings |
| `MainPanelWindow.swift` | NSWindow wrapper for dashboard |
| `ToastView.swift` | Non-intrusive execution feedback toast |
| `ToastWindow.swift` | Floating NSPanel for toasts |
| `SetupView.swift` | First-run dependency setup UI |
| `OnboardingView.swift` | Onboarding flow (first launch) |

### UI — Panel Views
| File | Purpose |
|------|---------|
| `LogsPipelineView.swift` | Pipeline stage visualizer (column view) |
| `AgentsView.swift` | "My Agents" agents grid — 3-col capability cards, one-click run |
| `AICanvasView.swift` | Canvas + capabilities grid (Learn Mode / FUCBC) |
| `SettingsConsolidatedView.swift` | All settings UI |
| `IntelligenceView.swift` | Intelligence/context dashboard |
| `IntelligenceConsolidatedView.swift` | Consolidated intelligence panel |
| `SkillsView.swift` | Skills management UI |
| `QAView.swift` | Q&A results panel |
| `CodeWidgetView.swift` | Voice-driven Claude Code co-pilot widget |
| `SessionTimelineView.swift` | Session history timeline |
| `UserProfileChatView.swift` | User profile and chat context view |
| `TagView.swift` | Tag display component |

### UI — Widget Canvas
| File | Purpose |
|------|---------|
| `WidgetView.swift` | Pill widget root view |
| `WidgetCanvasViews.swift` | Per-mode canvas content + `CapabilitySuggestionCanvasView` ("Automate Now?" popup) |
| `WidgetPanelViews.swift` | Expanded pill panel views |

### Integrations & System
| File | Purpose |
|------|---------|
| `WhatsAppPoller.swift` | Polls sidecar, filters to self-chat, routes to pipeline |
| `WhatsAppService.swift` | WhatsApp message handling and reply logic |
| `WhatsAppSidecar.swift` | Sidecar connection management |
| `ShazamKitService.swift` | ShazamKit audio fingerprinting for now-playing detection |
| `MCPConfigManager.swift` | MCP server configuration management |
| `MCPServer.swift` | Built-in HTTP MCP server (port 7892): screen/cursor/selection/transcript tools |
| `GlobalHotkeyMonitor.swift` | System-wide keyboard shortcut monitoring |
| `HotWordDetector.swift` | Real-time hotword detection in audio stream |
| `HotWordConfig.swift` | Hotword configuration |
| `ClipboardMonitor.swift` | Clipboard change monitoring |
| `UserProfileService.swift` | User profile and preferences |
| `SettingsManager.swift` | All user settings via UserDefaults + API keys |
| `KeychainStorage.swift` | API key storage (Keychain + env var fallback) |
| `DependencyInstaller.swift` | First-run Ollama/dependency setup |
| `CleanupService.swift` | Audio file retention cleanup |
| `Attachment.swift` | File attachment value type for tasks |
| `PixelWorldView.swift` | WebKit wrapper for Mission Control HQ |

---

## OpenClaw Skill Library

144+ skills live in `~/.autoclawd/openclaw-skills/`. Each is a directory with `SKILL.md`:

```
~/.autoclawd/openclaw-skills/
  video2ai/        ← convert video → frames + transcript + LLM analysis (Python CLI + web UI)
  yt-dlp/          ← download videos from YouTube, YC, etc.
  remotion/        ← React-based motion graphics / programmatic video
  ffmpeg/          ← video/audio processing, segment assembly
  github/          ← GitHub issues, PRs, releases
  slack/           ← send messages, post to channels
  discord/         ← send messages, webhooks
  gdrive/          ← upload files, get shareable links
  whatsapp/        ← send messages via WhatsApp
  canvas/          ← Canva automation (screenshot + text extraction)
  coding-agent/    ← Claude Code sub-agent for code tasks
  ... 130+ more
```

When FUCBC discovers a new tool it hasn't seen, it auto-creates a new skill directory and SKILL.md.

---

## PixelWorld — Mission Control HQ

A live canvas visualization of the pipeline, rendered as a pixel-art room inside a WebKit `WKWebView`.

**Files:**
```
Resources/PixelWorld/
  index.html          WebKit container, loads bg + scripts
  background.png      960×648 perspective room artwork
  adapter.js          AutoClawd → PixelWorld bridge (pipeline event routing)
  game.js             Canvas renderer — perspective, sprites, agents, desks
  sprites/
    StandingA-*.png   12 directional walk/stand sprites (640×1120 RGBA)
```

**Event → desk mapping:**

| Pipeline event | Game action |
|---|---|
| `agentToolStart id=1` (transcript) | `assignNextAgent()` — dequeue front, walk to Comms |
| `agentToolStart id=2` (cleaning) | advance `atComms → toAnalysis` |
| `agentToolStart id=3` (analysis) | advance `atAnalysis → toProjects` |
| `agentToolStart id=4` (task created) | advance `atProjects → toCode` |
| `agentStatus id=4 status='waiting'` (task done) | advance `atCode → toArchive` |
| Stall timeout (600 ticks ≈ 10s) | `returnToQueue()` — re-queue at right end |

---

## Pill Modes (PillMode enum)
- `.ambientIntelligence` — always-on mic → full pipeline; shows three-layer session transcript
- `.transcription` — mic → clean transcript only (copy-paste friendly)
- `.aiSearch` — hotword-triggered QA queries
- `.code` — voice-driven Claude Code co-pilot (streams to CodeWidgetView)
- `.learn` — FUCBC mode: watches screen+voice, builds capabilities

## Panel Tabs (PanelTab enum)
- `.world` — Mission Control HQ pixel world (or Call Mode room)
- `.agents` — "My Agents" grid of built capabilities (AgentsView)
- `.canvas` — Learn Mode canvas + capabilities subtab (AICanvasView)
- `.projects` — Project list (ProjectsListView)
- `.logs` — Pipeline stage visualizer (LogsPipelineView)
- `.settings` — All settings (SettingsConsolidatedView)

## Task Modes (TaskMode enum)
- `.auto` — executed immediately without approval
- `.ask` — shown to user for approval in LogsPipelineView
- `.user` — created but not executed (manual)

---

## API Keys & Environment

API keys are resolved in priority order:
1. Environment variable (`GROQ_API_KEY`, `ANTHROPIC_API_KEY`)
2. macOS Keychain (legacy fallback)

Set env vars in `~/.zshenv` or pass them to the app via launchd/`launchctl setenv`.

Groq is optional — if absent, transcription falls back to Apple SFSpeechRecognizer (fully local).
Anthropic key is required for Claude Code execution (Stage 4) and FUCBC capability building.

---

## WhatsApp Integration

- Sidecar runs on `localhost:7891`
- Only messages from the **self-chat** JID (`myNumber@s.whatsapp.net`) are processed
- Group messages (JID ends with `@g.us`) are filtered at the sidecar level
- Voice notes are transcribed then routed through the pipeline
- Bot replies are sent back with `"Dot: "` prefix

---

## Development Conventions

- **SwiftUI + AppKit**: Use SwiftUI for views inside windows; AppKit (NSPanel/NSWindow) for window management
- **MainActor**: All UI state and AppState mutations on `@MainActor`. Services are `@unchecked Sendable` crossing actors.
- **Logging**: Use `Log.info(.pipeline, "…")`, `Log.warn(.system, "…")` — subsystems: `.pipeline`, `.system`, `.audio`, `.ui`, `.camera`
- **No force-unwraps** in production paths. Use `guard let` or default values.
- **Single source of truth**: `AppState` holds all published state. Don't duplicate state across views.
- **Avoid huge files**: If a view exceeds ~300 lines, split into subviews.
- **Glass design system**: Use `LiquidGlassCard(tint:)`, `GlassButton`, `GlassIconBadge`, `GlassDivider`, `GlassChip`, `Glass.textPrimary/Secondary/Tertiary` — not raw `Color`.
- **PixelWorld events**: Emit via `WKWebView.evaluateJavaScript("receiveEvent('type', data)")` — do not bypass adapter.js.
- **Session transcript**: Use `appState.clearSessionTranscript()` to reset. Never directly nil `liveTranscriptText` outside `AppState`.
- **Capability notifications**: `CapabilityStore.save()` posts `capabilityStoreDidChange` — observe this in views instead of polling.

---

## Common Tasks

### Add a new pipeline stage
1. Add service in `Sources/`
2. Inject into `PipelineOrchestrator.init()`
3. Call it in `processTranscript()` after the appropriate stage
4. Update `PipelineSource` routing if stage should be skipped for certain modes
5. Add a corresponding desk in `adapter.js` and wire the event in `game.js`

### Add a new OpenClaw skill
1. Create directory: `~/.autoclawd/openclaw-skills/{slug}/`
2. Write `SKILL.md` with: what the tool does, how to invoke it, input/output, workflow tags
3. Skill appears automatically in `SkillStore.refreshOpenClawSkills()`

### Add a new capability manually
1. Create `Capability` with triggers, subWorkflows, skillMDPath
2. Call `CapabilityStore.shared.save(capability)`
3. Notification fires → AgentsView reloads → card appears immediately

### Add a new workflow (Phase 3)
1. Define `WorkflowRecord` with ordered `WorkflowStep` array
2. Each step references a `capabilityID` or `skillSlug`
3. Define `inputSpec` — what the user provides at run time
4. Save via `WorkflowStore.shared.save(workflow)`
5. `WorkflowExecutor` chains steps, passing outputs as inputs to subsequent steps

### Add a new setting
1. Add key constant + computed property in `SettingsManager.swift`
2. Add UI control in `SettingsConsolidatedView.swift`
3. Use `SettingsManager.shared.yourSetting` at call sites

### Add a panel tab
1. Add case to `PanelTab` enum in `MainPanelView.swift`
2. Add icon to `var icon: String` switch
3. Add view to the `ZStack` in `content` with matching `.opacity`/`.allowsHitTesting`

### Trigger a pipeline manually (testing)
```swift
await appState.pipelineOrchestrator.processTranscript(
    text: "test transcript",
    transcriptID: 0,
    sessionID: "test",
    sessionChunkSeq: 0,
    durationSeconds: 5,
    speakerName: "Test",
    source: .ambient
)
```

### Test PixelWorld pipeline animation (browser console)
```javascript
receiveEvent('transcript', {})
receiveEvent('cleaning', {})
receiveEvent('analysis', {})
receiveEvent('task_created', { title: 'Send email', mode: 'auto' })
receiveEvent('task_done', {})
```

### Test FUCBC capability popup
```swift
// Simulate a detected capability on the pill
appState.detectedCapability = CapabilityStore.shared.all().first
// → CapabilitySuggestionCanvasView springs up on the pill
// Tap "Automate Now" → executeCapability() → canvasExecutingTask streams live
```
