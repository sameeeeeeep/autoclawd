# AutoClawd — CLAUDE.md

AutoClawd is a macOS ambient AI agent. It runs as a floating pill widget with an always-on microphone and a background pipeline that listens to conversations, transcribes them with local AI models, extracts tasks, and executes them autonomously via Claude Code — without the user ever typing a prompt.

## Core Concept

- **Always-on mic** → captures 30-second audio chunks continuously with live word-by-word streaming
- **Always-on intelligence** → local Llama 3.2 cleans and analyzes every transcript
- **Zero-prompt execution** → tasks are created and auto-run based on what was said, not what was asked
- **World model** → persistent per-project knowledge base built from every conversation
- **Mission Control HQ** → live pixel-art visualization of the pipeline (agents queue, walk desk-to-desk, reflect real events)
- **Session-aware transcript** → text accumulates across all modes for the duration of a speaking session; 10s of silence = new session

## Build & Run

```bash
# Build (ad-hoc signed, no provisioning needed)
make

# Build + run immediately
make run

# Rebuild after Swift source changes
swift build && make
```

The Makefile copies the built bundle to `build/AutoClawd.app`. To install permanently: `cp -r build/AutoClawd.app /Applications/`.

The WhatsApp sidecar is a separate Node.js process:
```bash
cd WhatsAppSidecar && npm install && npm start
```

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
- `onTranscriptionCleaned` fires for ALL pipeline sources (not just `.transcription`), appending to `liveTranscriptText`
- `lastSpeechTime` (ChunkManager) is updated whenever a non-empty streaming partial arrives
- After each chunk cycle, if `Date().timeIntervalSince(lastSpeechTime) >= 10.0`, session ends: `clearSessionTranscript()` is called and the chunk cycle pauses waiting for new speech
- Mode changes do NOT clear the transcript — only silence-end and the manual Clear button do

### Local AI Model Usage

| Stage | Model | Provider | Purpose |
|-------|-------|----------|---------|
| Transcription (streaming) | SFSpeechRecognizer | Apple (local) | Live word-by-word partials |
| Transcription (committed) | Whisper | Groq (cloud) or Apple SFSpeech (local) | Final chunk text |
| Cleaning | Llama 3.2 3B | Ollama (local) | Merge, denoise, resolve context |
| Analysis | Llama 3.2 3B | Ollama (local) | Extract tasks, update world model |
| Task framing | Llama 3.2 3B | Ollama (local) | Clean task titles from README/CLAUDE.md |
| Execution | Claude Code | Anthropic API | Run tasks in project folders |

Groq is optional and used only for transcription speed. All analysis runs locally — Ollama must be installed and `llama3.2:3b` pulled.

### Key Files

#### Core App
| File | Purpose |
|------|---------|
| `App.swift` | SwiftUI `@main` entry point (headless — no default window) |
| `AppDelegate.swift` | NSApplicationDelegate; creates all windows, wires subscriptions |
| `AppState.swift` | Central `ObservableObject` — all shared state, service singletons |
| `AppFonts.swift` | Custom font registration and font accessors |
| `AppTheme.swift` | Appearance system — frosted/solid modes, color scheme, theme tokens |
| `Logger.swift` | Structured logging with subsystems: `.pipeline`, `.system`, `.audio`, `.ui` |

#### Pipeline
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

#### Audio & Transcription
| File | Purpose |
|------|---------|
| `AudioRecorder.swift` | Always-on AVAudioEngine capture; engine stays hot between chunks |
| `SpeechService.swift` | Groq / Apple SFSpeech transcription of committed audio chunks |
| `TranscriptionService.swift` | Transcription orchestration |
| `TranscriptionPasteService.swift` | Paste cleaned transcript to frontmost app |

#### Storage & Persistence
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

#### World Model & Intelligence
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

#### Context Capture
| File | Purpose |
|------|---------|
| `ScreenshotService.swift` | Periodic screen capture for ambient context |
| `ClipboardMonitor.swift` | Monitors clipboard changes for context enrichment |
| `LocationService.swift` | Core Location — current place detection |
| `PlaceDetail.swift` | Place value type |

#### Q&A & Skills
| File | Purpose |
|------|---------|
| `QAService.swift` | Handles AI search / Q&A queries against transcript context |
| `QAView.swift` | Q&A results UI |
| `Skill.swift` | Skill value type (built-in + custom) |
| `SkillStore.swift` | Skill persistence, seeding built-in skills on install |

#### Todo & Task Management
| File | Purpose |
|------|---------|
| `TodoService.swift` | Todo list management |
| `TodoFramingService.swift` | Frames task titles using README/CLAUDE.md for context |
| `StructuredTodoStore.swift` | Persists structured task queue |

#### UI — Windows & Shell
| File | Purpose |
|------|---------|
| `PillView.swift` | Floating widget SwiftUI view |
| `PillWindow.swift` | NSPanel wrapper with drag, snap-to-edge, height animation |
| `PillMode.swift` | `PillMode` enum and transitions |
| `MainPanelView.swift` | Main dashboard shell |
| `MainPanelWindow.swift` | NSWindow wrapper for dashboard |
| `ToastView.swift` | Non-intrusive execution feedback toast |
| `ToastWindow.swift` | Floating NSPanel for toasts |
| `SetupView.swift` | First-run dependency setup UI |

#### UI — Panel Views
| File | Purpose |
|------|---------|
| `LogsPipelineView.swift` | Pipeline stage visualizer (column view) |
| `SettingsConsolidatedView.swift` | All settings UI |
| `IntelligenceView.swift` | Intelligence/context dashboard |
| `IntelligenceConsolidatedView.swift` | Consolidated intelligence panel |
| `SkillsView.swift` | Skills management UI |
| `QAView.swift` | Q&A results panel |
| `CodeWidgetView.swift` | Voice-driven Claude Code co-pilot widget |
| `SessionTimelineView.swift` | Session history timeline |
| `UserProfileChatView.swift` | User profile and chat context view |
| `TagView.swift` | Tag display component |

#### UI — Widget Canvas
| File | Purpose |
|------|---------|
| `WidgetView.swift` | Pill widget root view |
| `WidgetCanvasViews.swift` | Per-mode canvas content (AmbientCanvasView, TranscriptCanvasView, etc.) |
| `WidgetPanelViews.swift` | Expanded pill panel views |

#### Integrations & System
| File | Purpose |
|------|---------|
| `WhatsAppPoller.swift` | Polls sidecar, filters to self-chat, routes to pipeline |
| `WhatsAppService.swift` | WhatsApp message handling and reply logic |
| `WhatsAppSidecar.swift` | Sidecar connection management |
| `ShazamKitService.swift` | ShazamKit audio fingerprinting for now-playing detection |
| `MCPConfigManager.swift` | MCP server configuration management |
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

### PixelWorld — Mission Control HQ

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

**Agent queue system:**
```
[ .1 ] [ .2 ] [ .3 ]   ← queue, left-to-right, near TV wall
                                agent at front gets the next transcript
                                queue always refills from the right
         │
    transcript arrives
         │
    ┌────▼────┐   ┌──────────┐   ┌──────────┐   ┌─────────────┐   ┌─────────┐
    │  Comms  │──▶│ Analysis │──▶│ Projects │──▶│ Claude Code │──▶│ Archive │
    └─────────┘   └──────────┘   └──────────┘   └─────────────┘   └─────────┘
                                                                         │
                                                             success: disappears
                                                             failure: re-queues right
```

**Event → desk mapping (adapter.js → game.js):**

| Pipeline event | Game action |
|---|---|
| `agentToolStart id=1` (transcript) | `assignNextAgent()` — dequeue front, walk to Comms |
| `agentToolStart id=2` (cleaning) | advance `atComms → toAnalysis` |
| `agentToolStart id=3` (analysis) | advance `atAnalysis → toProjects` |
| `agentToolStart id=4` (task created) | advance `atProjects → toCode` |
| `agentStatus id=4 status='waiting'` (task done) | advance `atCode → toArchive` |
| Stall timeout (600 ticks ≈ 10s) | `returnToQueue()` — re-queue at right end |

**Agent state machine:**
```
inQueue → toComms → atComms → toAnalysis → atAnalysis → toProjects
       → atProjects → toCode → atCode → toArchive → atArchive → leaving → (removed)
```

**Rendering:**
- `perspScale(y)` → 0.58–1.0 scale based on y position (perspective depth)
- Draw list sorted back-to-front by y each frame
- StandingA sprites: 640×1120 RGBA, directional (back/front/left/right × walk1/walk2 + stand)
- Desk labels (Comms, Analysis, Projects, Claude Code, QA, Archive) rendered in cyan above monitors

### Pill Modes (PillMode enum)
- `.ambientIntelligence` — always-on mic → full pipeline; shows three-layer session transcript
- `.transcription` — mic → clean transcript only (copy-paste friendly); same three-layer display
- `.aiSearch` — hotword-triggered QA queries
- `.code` — voice-driven Claude Code co-pilot (streams to CodeWidgetView)

### Task Modes (TaskMode enum)
- `.auto` — executed immediately without approval
- `.ask` — shown to user for approval in LogsPipelineView
- `.user` — created but not executed (manual)

### Task Autonomous Execution
Tasks are auto-executed when `task.mode == .auto`. What qualifies is configurable via `SettingsManager.autonomousTaskRules`. Rules are plain-English descriptions of the category of task that can run autonomously (e.g., "Send emails", "Create GitHub issues"). The analysis LLM uses these rules when assigning task modes.

### Skills System
Built-in skills are seeded into `SkillStore` on first launch (`isBuiltin = true`). Each skill has a trigger, prompt template, and execution mode. Custom skills can be created via `SkillsView`. On updates, built-in skills are re-seeded (overwriting by ID) so changes propagate to existing installs.

## API Keys & Environment

API keys are resolved in priority order:
1. Environment variable (`GROQ_API_KEY`, `ANTHROPIC_API_KEY`)
2. macOS Keychain (legacy fallback)

Set env vars in `~/.zshenv` or pass them to the app via launchd/`launchctl setenv`.

Groq is optional — if absent, transcription falls back to Apple SFSpeechRecognizer (fully local).
Anthropic key is required only for Claude Code execution (Stage 4).

## WhatsApp Integration

- Sidecar runs on `localhost:7891`
- Only messages from the **self-chat** JID (`myNumber@s.whatsapp.net`) are processed
- Group messages (JID ends with `@g.us`) are filtered at the sidecar level
- Voice notes are transcribed then routed through the pipeline
- Bot replies are sent back with `"Dot: "` prefix

## Settings

All settings live in `SettingsManager.shared`:

| Setting | Key | Type |
|---------|-----|------|
| `transcriptionMode` | `.groq` / `.local` | Enum |
| `audioRetentionDays` | 7 / 30 | Int |
| `groqAPIKey` | env / keychain | String |
| `anthropicAPIKey` | env / keychain | String |
| `whatsAppEnabled` | — | Bool |
| `whatsAppMyJID` | phone number | String |
| `autonomousTaskRules` | free text per rule | [String] |
| `fontSizePreference` | `.small` / `.medium` / `.large` | Enum |
| `colorSchemeSetting` | `.system` / `.light` / `.dark` | Enum |
| `appearanceMode` | `.frosted` / `.solid` | Enum |
| `mcpServers` | list of MCP server configs | [MCPServer] |
| `locationEnabled` | — | Bool |
| `screenshotContextEnabled` | — | Bool |
| `shazamEnabled` | — | Bool |

## Development Conventions

- **SwiftUI + AppKit**: Use SwiftUI for views inside windows; AppKit (NSPanel/NSWindow) for window management
- **MainActor**: All UI state and AppState mutations on `@MainActor`. Services are `@unchecked Sendable` crossing actors.
- **Logging**: Use `Log.info(.pipeline, "…")`, `Log.warn(.system, "…")` — subsystems: `.pipeline`, `.system`, `.audio`, `.ui`
- **No force-unwraps** in production paths. Use `guard let` or default values.
- **Single source of truth**: `AppState` holds all published state. Don't duplicate state across views.
- **Avoid huge files**: If a view exceeds ~300 lines, split into subviews.
- **PixelWorld events**: Emit pipeline events from Swift via `WKWebView.evaluateJavaScript("receiveEvent('type', data)")` — do not bypass the adapter.js routing layer.
- **Session transcript**: Use `appState.clearSessionTranscript()` to reset. Never directly nil `liveTranscriptText` outside `AppState`.
- **Streaming transcriber**: `StreamingLocalTranscriber` is started/stopped by `ChunkManager`. Do not start it elsewhere.

## Common Tasks

### Add a new pipeline stage
1. Add service in `Sources/`
2. Inject into `PipelineOrchestrator.init()`
3. Call it in `processTranscript()` after the appropriate stage
4. Update `PipelineSource` routing if the stage should be skipped for certain modes
5. Add a corresponding desk in `adapter.js` and wire the event in `game.js`

### Add a new setting
1. Add key constant + computed property in `SettingsManager.swift`
2. Add UI control in `SettingsConsolidatedView.swift`
3. Use `SettingsManager.shared.yourSetting` at call sites

### Add a new workflow
1. Implement `WorkflowExecutor` protocol
2. Register in `WorkflowRegistry.shared`
3. The `workflowID` string in `PipelineTaskRecord` routes to it

### Add a built-in skill
1. Add the skill definition in `SkillStore.seedBuiltinSkills()`
2. Give it a stable UUID and `isBuiltin = true`
3. On next launch it will be seeded (and overwritten on existing installs to pick up changes)

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
// Simulate a full pipeline run
receiveEvent('transcript', {})          // agent dequeues, walks to Comms
receiveEvent('cleaning', {})            // agent walks to Analysis
receiveEvent('analysis', {})            // agent walks to Projects
receiveEvent('task_created', { title: 'Send email', mode: 'auto' })  // walks to Claude Code
receiveEvent('task_done', {})           // walks to Archive, disappears

// Force-advance a stalled agent
advancePipeline('atComms', 'toAnalysis', 1)

// Manually spawn a queue agent
spawnQueueAgent()
```

### Test session transcript accumulation
Speak for >30s and verify `liveTranscriptText` grows continuously. Stop speaking for 10s and verify `clearSessionTranscript()` fires (all three text layers reset). Resume speaking and verify a fresh session begins.
