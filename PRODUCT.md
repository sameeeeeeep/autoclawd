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
| FUCBC — capability learning from observed screen+voice | ✅ | LearnModeService, story builder, executable SKILL.md |
| Capability suggestion pill popup (Cofia-style) | ✅ | CapabilitySuggestionCanvasView: "Automate Now?" |
| OCR auto-trigger: detects matching capability from screen | ✅ | CapabilityStore.suggest() with scoring |
| "My Agents" panel: grid of built capabilities, one-click run | ✅ | AgentsView, 3-col grid, ▶ Run → streams on canvas |
| 144+ OpenClaw skills in `~/.autoclawd/openclaw-skills/` | ✅ | yt-dlp, remotion, ffmpeg, github, slack, gdrive, and more |
| video2ai skill: video → frames + transcript + LLM analysis | ✅ | Python CLI + web UI; solves "Claude can't read videos" |
| Built-in MCP server (port 7892) | ✅ | screen/cursor/selection/transcript tools for Claude Code |

### In Progress / Upcoming

| Feature | Priority | Notes |
|---|---|---|
| Workflow Intelligence (Phase 3) | P0 | Chain capabilities into end-to-end workflows; see Phase 3 section |
| WorkflowRecord + WorkflowStore | P0 | Higher-level construct above Capability; `steps`, `inputSpec` |
| WorkflowBuilder | P0 | Infers workflows from sequences of observed capabilities |
| WorkflowExecutor | P0 | Runs workflow steps in sequence, passes context between them |
| WorkflowInputView | P0 | User provides references + context + project at runtime |
| SkillDiscoveryService | P1 | Auto-creates SKILL.md when new tool encountered mid-workflow |
| Batch intelligence engine | P1 | Multi-transcript Llama pass; project/category batching |
| World model v2: PageRank + episodic + diff.md | P1 | See Memory Architecture section |
| Q&A canvas mode | P2 | Open questions in canvas; tagged voice replies |
| Daily/monthly/yearly journal synthesis | P2 | Narrative from episodes + world model |
| WhatsApp proactive engagement | P2 | Morning/evening, Wrapped moments, open questions |
| Idle reprocessing pass | P3 | Re-understand past with updated world model context |
| Silence ambient prompts | P3 | Contextual questions during quiet periods |

### Planned (Roadmap)

- [ ] Phone call transcription (Bluetooth mic capture)
- [ ] Multi-language transcription
- [ ] Location tagging via WiFi SSID → place names
- [ ] People tagging (manual hint + AI inference)
- [ ] Execution history and re-run
- [ ] Workflow marketplace: share/import community workflows

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
| FUCBC story builder | Llama 3.2 3B | Ollama (local) |
| Capability building | Claude Code | Anthropic API |
| Research (planned) | Web search + Llama synthesis | Local synthesis, web fetch |

---

## Phase 3 — Workflow Intelligence

### Three-Tier Model

Everything in AutoClawd's automation layer is built from three primitives:

| Tier | Name | What it is | Who builds it |
|------|------|------------|--------------|
| **1** | **Skill** | An atomic unit — often just Claude alone, or one CLI tool. Does one thing well. | Built-in seed library, FUCBC auto-discovery, user authoring |
| **2** | **Capability** | A Skill (or a few) **combined with tool access**. Runs a specific job with real external tools. | FUCBC — watches screen+voice, builds automatically |
| **3** | **Workflow** | AutoClawd + an ordered sequence of Capabilities and Skills + Claude Code → **delivers a real-world output** | WorkflowBuilder — infers from observed sequences; or pre-built |

**Skill** examples: "Write a tweet thread", `yt-dlp {url}`, `video2ai {file}`, "Summarise PDF with key decisions"

**Capability** examples: "Post to all platforms" (Twitter + Threads + Buffer skills + API access), "Ingest reference video" (video2ai + Claude content strategy)

**Workflow** examples: "Launch Video" (8 capabilities chained: download → ingest → strategy → motion graphic → voice → assemble → upload → share), "Podcast to Blog Post" (audio → transcript → article → publish)

The key shift: **Skills are what Claude can do. Capabilities are what Claude can do with tools. Workflows are what AutoClawd assembles and runs for you automatically.**

Most workflows can be **pre-created** — covering common knowledge-worker patterns out of the box — and then personalised as AutoClawd observes how each user actually works.

---

### The Core Shift

Phase 1 was: *listen → transcribe → extract task → run it.*
Phase 2 was: *watch screen → detect pattern → build capability → "Automate Now?"*
**Phase 3 is: *watch a complex multi-step workflow → understand every tool used → build an end-to-end automation that runs with just context + references.***

### The Social Media Manager Story

A social media manager is making a launch video. Watch what she does manually, and then what AutoClawd turns it into.

**She does this manually (every time):**

```
1. Opens YC's YouTube → finds reference launch videos from successful AI startups
   Tries to download → YouTube blocks direct download

2. Installs yt-dlp → downloads 3 reference videos to ~/Downloads

3. Tries to upload videos to Claude → error: "I can't process video files"
   Frustrated. Googles alternative.

4. Finds video2ai → runs `video2ai --web` → uploads videos
   Gets: frames every 1s + Whisper transcript + Ollama frame analysis

5. Opens Claude → pastes transcript + key frames → asks for content strategy
   Gets: brand positioning, hook ideas, visual style guide, script structure

6. Opens Canva → builds motion graphic template
   Tries Remotion (React animations) → exports .mp4

7. Goes to Freepik → generates AI voice from the script
   Downloads voice.mp3

8. Back in Canva → adds voice layer, manually matches segment lengths to voice
   Exports final.mp4

9. Uploads to Google Drive → copies shareable link

10. Opens WhatsApp → pastes Drive link into team group
    Types: "Here's the draft — feedback pls"
```

**AutoClawd watches this. It identifies 8 capabilities:**
- `yt-dlp-downloader` (already in skill library)
- `video2ai-ingest` (NEW — detects new tool, auto-creates SKILL.md)
- `claude-content-strategy` (already in skill library)
- `remotion-motion-graphic` (already in skill library)
- `freepik-ai-voice` (NEW — auto-creates SKILL.md)
- `ffmpeg-video-assembler` (already in skill library)
- `gdrive-upload` (already in skill library)
- `whatsapp-share` (already in skill library)

**WorkflowBuilder sees the sequence → creates "Launch Video" workflow.**

**Next time she needs a launch video:**
```
Opens "Launch Video" in My Agents
  ↓
WorkflowInputView:
  References: [youtube.com/ycombinator/...] [upload brand guide PDF]
  Context: "launch video for AI writing tool, 60s, B2B tone"
  Project: "Product Launch Q2"
  → [Run Workflow]
  ↓
Step 1/8: yt-dlp-downloader → downloading references...
Step 2/8: video2ai-ingest → extracting frames + transcript...
Step 3/8: claude-content-strategy → generating strategy with your brand context...
Step 4/8: remotion-motion-graphic → building animation from script...
Step 5/8: freepik-ai-voice → generating voice...
Step 6/8: ffmpeg-video-assembler → assembling final video...
Step 7/8: gdrive-upload → uploading → drive.google.com/...
Step 8/8: whatsapp-share → sent to "Team" group ✓
```

10-step manual workflow → 1 click + 2 inputs.

### Skill Discovery (Auto-SKILL.md)

When FUCBC encounters a tool AutoClawd hasn't seen before:
1. OCR detects terminal command or browser URL pointing to unfamiliar tool
2. Checks `~/.autoclawd/openclaw-skills/` — no matching slug
3. FUCBC prompt includes: "This appears to be a new tool. Research it, write its SKILL.md, and tag which workflow categories it belongs to."
4. Claude Code creates `~/.autoclawd/openclaw-skills/{slug}/SKILL.md`
5. Tags added: `workflowTags: ["video-production", "content-creation", "media"]`
6. Capability appears in My Agents immediately
7. WorkflowBuilder knows this capability is available for future workflow assembly

**video2ai** is the first example. It's already built:
- `video2ai {input.mp4}` — extract frames (every N seconds) + Whisper transcript + Ollama frame analysis
- `video2ai --web` — local web UI for drag-drop upload + visual review
- Output: frames dir + transcript.txt + analysis.md + contact sheets
- **Solves the core problem**: Claude can't read videos → video2ai converts them into what Claude CAN read

### GitHub as the Tool Source

Every tool in AutoClawd's skill library ultimately comes from GitHub — analysed, categorised, and structured into executable SKILL.md files.

When a niche skill is needed that doesn't yet exist:
```
FUCBC detects unfamiliar tool from OCR / URL / terminal command
  │
  Web search: "{tool name} github" + README analysis
  │
  Extract: CLI interface, install method, input/output format, use cases
  │
  Claude Code writes: ~/.autoclawd/openclaw-skills/{slug}/SKILL.md
  │
  Tags applied: workflowTags, category, requiredTools (pip/brew/npm install)
  │
  Skill immediately available for Capability + Workflow assembly
```

**Pre-curated categories the library covers:**
- **Video & Audio** — yt-dlp, video2ai, ffmpeg, whisper-cli, freepik-voice
- **Content & Publishing** — remotion, imagemagick, pandoc, markdownlint, ghost-api
- **Communication** — whatsapp-baileys, slack-bolt, gmail-send, discord-webhook, sendgrid
- **Storage & Files** — gdrive-upload, dropbox-api, s3-upload, notion-create, airtable-api
- **Code & Dev** — gh-cli, linear-api, jira-api, vercel-deploy, railway-api
- **Data & Research** — firecrawl, playwright-scraper, exa-search, tavily-api, arxiv-fetch
- **AI & Processing** — ollama-run, claude-code, openai-api, replicate-api, huggingface-cli

The vision: **GitHub is the app store. AutoClawd is the agent that discovers what's on it, installs what's needed, and wires everything together into workflows — automatically.**

### Workflow Data Model

```
WorkflowRecord
  ├── id, name, description, emoji
  ├── steps: [WorkflowStep]
  │     └── { capabilityID | skillSlug, name, inputMapping, outputKey }
  ├── inputSpec: WorkflowInputSpec
  │     ├── references: [{ label, type: url|file|text }]
  │     ├── contextField: String   ("describe what you need")
  │     └── projectSelection: Bool
  └── createdFrom: .observed(sessionID) | .manual

WorkflowContext  (passed between steps at runtime)
  └── [String: Any]  // "video_paths" → [URL], "strategy" → String, "drive_url" → String
```

### The Expanding Library

The goal: a rich, pre-loaded library of workflows and capabilities covering every common knowledge-worker pattern — **shipping out of the box, personalised as AutoClawd learns each user**.

Most workflows are pre-created. The user doesn't have to build them from scratch — AutoClawd ships with the common ones, and FUCBC adds new ones specific to each user's actual patterns.

**Content Creation:**
- Launch Video (as above — 8 capabilities, 1 click)
- Podcast to Blog Post (audio → transcript → article → SEO → publish)
- Screenshot to Documentation (screen record → annotated docs → Notion)
- Tweet Thread from Idea (voice note → thread draft → schedule → post)
- Newsletter from Conversations (week's transcripts → digest → send)

**Research:**
- Competitive Analysis (company name → scrape → strategy brief → slide deck)
- Academic Paper to TL;DR (PDF → structured summary → Notion with key quotes)
- Market Research (keyword → search + synthesis → formatted report)
- Person Research (name → LinkedIn + web → briefing before meeting)

**Engineering:**
- Bug Report to PR (issue description → repo analysis → code fix → PR + description)
- README from Codebase (repo path → analysis → structured README → commit)
- Deploy with Announcement (git push → deploy → Slack + Twitter announcement)
- Code Review Brief (PR URL → diff analysis → summary for non-eng stakeholders)

**Communication:**
- Meeting to Action Items (audio → transcript → tasks → Notion + Slack + calendar)
- Email Digest (inbox → prioritise → summarise → WhatsApp briefing)
- Client Update (project status → tailored email → send + CRM log)
- Async Standup (voice note → structured update → Slack post + Linear sync)

**Philosophy:** Each workflow is a few user inputs + a chain of skills that already exist. The only thing that changes between users is which workflow they need most — AutoClawd figures that out by watching.

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
