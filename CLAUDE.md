# AutoClawd — CLAUDE.md

AutoClawd is a macOS ambient AI agent. It runs as a floating pill widget, always-on microphone, and background pipeline that listens to conversations, transcribes them, extracts tasks, and executes them autonomously via Claude Code.

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

WhatsApp Sidecar (Node.js/Express on localhost:7891)
  └── Baileys WA Web client → buffers messages → polled every 2s
```

### Pipeline Flow
```
[Mic] → AudioRecorder → ChunkManager → PipelineOrchestrator
                                              │
                                    ┌─────────▼─────────┐
                                    │ Stage 1: Cleaning  │  TranscriptCleaningService
                                    │  merge chunks,     │
                                    │  denoise           │
                                    └─────────┬──────────┘
                                              │  (transcript mode stops here)
                                    ┌─────────▼──────────┐
                                    │ Stage 2: Analysis  │  TranscriptAnalysisService
                                    │  project, priority │
                                    │  tags, tasks       │
                                    └─────────┬──────────┘
                                              │
                                    ┌─────────▼──────────┐
                                    │ Stage 3: Task      │  TaskCreationService
                                    │  Creation          │
                                    └─────────┬──────────┘
                                              │  (code mode stops here — saves transcript+task only)
                                    ┌─────────▼──────────┐
                                    │ Stage 4: Execution │  TaskExecutionService
                                    │  auto tasks via    │
                                    │  Claude Code       │
                                    └────────────────────┘
```

### Pipeline Sources (PipelineSource enum)
Each transcript entering the pipeline carries a source tag controlling which stages run:
- `.ambient` — full pipeline (clean → analyze → task → execute)
- `.transcription` — clean only (merges/denoises speech; no task creation)
- `.code` — save transcript + Claude Code task; skip LLM analysis stages
- `.whatsapp` — full pipeline (same as ambient, with QA reply)

### Key Files

| File | Purpose |
|------|---------|
| `App.swift` | SwiftUI `@main` entry point (headless — no default window) |
| `AppDelegate.swift` | NSApplicationDelegate; creates PillWindow, MainPanelWindow, wires subscriptions |
| `AppState.swift` | Central `ObservableObject` — all shared state, service singletons |
| `PipelineOrchestrator.swift` | Routes transcripts through the 4-stage pipeline |
| `PipelineModels.swift` | Core value types: `CleanedTranscript`, `TranscriptAnalysis`, `PipelineTaskRecord` |
| `PipelineStore.swift` | Persistence layer for pipeline data |
| `ChunkManager.swift` | Buffers audio chunks, calls PipelineOrchestrator |
| `SettingsManager.swift` | All user settings via UserDefaults + API keys |
| `KeychainStorage.swift` | API key storage (Keychain + env var fallback) |
| `TranscriptStore.swift` | SQLite transcript persistence |
| `TaskExecutionService.swift` | Streams Claude Code sessions for auto tasks |
| `ClaudeCodeRunner.swift` | Low-level Claude Code SDK streaming client |
| `WhatsAppPoller.swift` | Polls sidecar, filters to self-chat, routes to pipeline |
| `PillView.swift` | Floating widget SwiftUI view |
| `PillWindow.swift` | NSPanel wrapper with drag, snap-to-edge, height animation |
| `MainPanelView.swift` | Main dashboard shell |
| `LogsPipelineView.swift` | Pipeline stage visualizer (the column view) |
| `SettingsConsolidatedView.swift` | All settings UI |
| `WorkflowRegistry.swift` | Registered execution workflows (e.g. `autoclawd-claude-code`) |

### Pill Modes (PillMode enum)
- `.ambientIntelligence` — always-on mic → full pipeline
- `.transcription` — mic → clean transcript only (copy-paste friendly)
- `.aiSearch` — hotword-triggered QA queries
- `.code` — voice-driven Claude Code co-pilot (streams to CodeWidgetView)

### Task Modes (TaskMode enum)
- `.auto` — executed immediately without approval
- `.ask` — shown to user for approval in LogsPipelineView
- `.user` — created but not executed (manual)

### Task Autonomous Execution
Tasks are auto-executed when `task.mode == .auto`. What qualifies is configurable via `SettingsManager.autonomousTaskRules`. Rules are plain-English descriptions of the category of task that can run autonomously (e.g., "Send emails", "Create GitHub issues"). The analysis LLM uses these rules when assigning task modes.

## API Keys & Environment

API keys are resolved in priority order:
1. Environment variable (`GROQ_API_KEY`, `ANTHROPIC_API_KEY`)
2. macOS Keychain (legacy fallback)

Set env vars in `~/.zshenv` or pass them to the app via launchd/`launchctl setenv`.

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

## Development Conventions

- **SwiftUI + AppKit**: Use SwiftUI for views inside windows; AppKit (NSPanel/NSWindow) for window management
- **MainActor**: All UI state and AppState mutations on `@MainActor`. Services are `@unchecked Sendable` crossing actors.
- **Logging**: Use `Log.info(.pipeline, "…")`, `Log.warn(.system, "…")` — subsystems: `.pipeline`, `.system`, `.audio`, `.ui`
- **No force-unwraps** in production paths. Use `guard let` or default values.
- **Single source of truth**: `AppState` holds all published state. Don't duplicate state across views.
- **Avoid huge files**: If a view exceeds ~300 lines, split into subviews.

## Common Tasks

### Add a new pipeline stage
1. Add service in `Sources/`
2. Inject into `PipelineOrchestrator.init()`
3. Call it in `processTranscript()` after the appropriate stage
4. Update `PipelineSource` routing if the stage should be skipped for certain modes

### Add a new setting
1. Add key constant + computed property in `SettingsManager.swift`
2. Add UI control in `SettingsConsolidatedView.swift`
3. Use `SettingsManager.shared.yourSetting` at call sites

### Add a new workflow
1. Implement `WorkflowExecutor` protocol
2. Register in `WorkflowRegistry.shared`
3. The `workflowID` string in `PipelineTaskRecord` routes to it

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
