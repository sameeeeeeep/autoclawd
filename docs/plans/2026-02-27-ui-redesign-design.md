# UI Redesign — Design Document
**Date:** 2026-02-27
**Status:** Approved for implementation

---

## Vision

Replace the current BrutalistTheme (dark background, neon green, uppercase monospace) with a clean, modern, light-mode interface: white background, black typography, green + cyan accents. The product should feel like a premium ambient intelligence tool — not a terminal emulator.

---

## 1. Navigation Consolidation

### Before: 10 sidebar tabs (160px wide)
Todos · World Model · Transcript · Settings · Logs · Intelligence · AI Search · Timeline · Profile · Projects

### After: 3 icon sidebar tabs (52px wide)

| Icon | Tab | Contains |
|------|-----|---------|
| `globe` | **World** | Past / Today / Future / Unscheduled / AI Search / All transcripts + tagging |
| `brain.head.profile` | **Intelligence** | Extraction results · World model markdown · Logs |
| `gearshape` | **Settings** | Projects · Profile · Hot words · Hot keys · Transcription mode · API keys |

The floating **PillView** remains a separate overlay — it is not part of sidebar navigation.

---

## 2. World View Layout

World is the primary view. It has an internal sub-navigation (Past · Today · Future) rendered as a segmented control at the top — not as sidebar tabs.

```
┌──────────────────────────────────────────────────────────┐
│  ◀  February 2026  ▶          [PAST] [TODAY] [FUTURE]    │
│  ──────────────────────────────────────────────────────  │
│  Mon    Tue    Wed    Thu    Fri    Sat    Sun            │
│   3      4      5  ●  6      7  ●  8      9             │
│  10     11     12     13     14     15     16            │
│  ...                                                     │
│  ──────────────────────────────────────────────────────  │
│  UNSCHEDULED  (4)                              [▼]       │
│    ○  Fix login crash                      [▶ Run]      │
│    ○  Update onboarding copy               [▶ Run]      │
│  ──────────────────────────────────────────────────────  │
│  🔍  Search everything...                                │
└──────────────────────────────────────────────────────────┘
```

**Calendar dots:**
- 🟢 Green dot = scheduled todo on that day
- 🔵 Cyan dot = transcript captured on that day
- ⚫ Black dot = both

**Clicking a day** opens a day detail panel (right side or modal) showing:
- Transcript entries with timestamps
- Scheduled todos at their times
- Location / people tags (if set)

**Unscheduled list** sits below the calendar — collapses/expands. Completed unscheduled todos migrate to the Past calendar day they were completed on.

**AI Search** is a persistent search bar at the bottom — searches across transcripts, todos, world model, intelligence.

**Future sub-tab** shows a forward-looking calendar with:
- Todos assigned to specific future times
- Automations and reminders
- Repeat tasks

---

## 3. Intelligence View

Merged view of what was previously Logs + Intelligence + World Model.

```
┌──────────────────────────────────────────────┐
│  [EXTRACTIONS]  [WORLD MODEL]  [LOGS]         │
│  ─────────────────────────────────────────── │
│  Sub-tab content here                         │
└──────────────────────────────────────────────┘
```

- **Extractions**: Last N extraction results from ChunkManager/ExtractionService
- **World Model**: Editable markdown view of `~/.autoclawd/world-model.md`
- **Logs**: Raw app logs (monospace font, dark surface card within white bg)

---

## 4. Settings View

Reorganised into clear sections. No more separate Projects or Profile tabs.

```
PROJECTS          [+ Add Project]
  ↳ project list with path, tags, links

PROFILE
  ↳ name, preferences

HOT WORDS         [+ Add]
  ↳ configured hot word rules

HOT KEYS
  ↳ keyboard shortcut bindings

TRANSCRIPTION
  ↳ Groq vs Local toggle, API key field

APPEARANCE
  ↳ (future: font/theme picker)
```

---

## 5. Color System

```swift
// Light mode only (for now)
static let background     = Color(hex: "#FFFFFF")  // panels, cards
static let surface        = Color(hex: "#F7F7F7")  // sidebar, row hover, input bg
static let textPrimary    = Color(hex: "#0A0A0A")  // headings, body
static let textSecondary  = Color(hex: "#6B6B6B")  // timestamps, meta, placeholder
static let accent1        = Color(hex: "#16C172")  // green — active, todos, run buttons
static let accent2        = Color(hex: "#06B6D4")  // cyan — transcripts, links, search
static let border         = Color(hex: "#E4E4E4")  // dividers, card outlines
static let destructive    = Color(hex: "#EF4444")  // delete, error
static let sidebarBG      = Color(hex: "#F7F7F7")  // icon sidebar background
```

Replace all uses of `BrutalistTheme.*` with the new `AppTheme.*` constants.

---

## 6. Typography

**Font — TBD by user.** Two candidate options flagged by frontend-design skill:
- **Option A: [Geist](https://vercel.com/font)** — clean, modern, slightly geometric. Geist + Geist Mono pair perfectly (mono for logs/code).
- **Option B: [DM Sans](https://fonts.google.com/specimen/DM+Sans) + DM Mono** — slightly more humanist, still sharp.

For now, fall back to `.system(.body)` and `.system(.body, design: .monospaced)` for logs. Swap once font is decided.

**Scale:**
```swift
static let caption  = Font.system(size: 11, weight: .regular)
static let body     = Font.system(size: 13, weight: .regular)
static let label    = Font.system(size: 13, weight: .medium)
static let heading  = Font.system(size: 15, weight: .semibold)
static let title    = Font.system(size: 18, weight: .bold)
static let mono     = Font.system(size: 12, design: .monospaced)
```

**8px grid — spacing constants:**
```swift
static let xs  : CGFloat = 4
static let sm  : CGFloat = 8
static let md  : CGFloat = 12
static let lg  : CGFloat = 16
static let xl  : CGFloat = 24
static let xxl : CGFloat = 32
```

---

## 7. Button System

| Variant | Fill | Text | Border | Use |
|---------|------|------|--------|-----|
| Primary | `#0A0A0A` black | White | — | Main CTA |
| Run | `#16C172` green | `#0A0A0A` black | — | Execute todo |
| Secondary | White | `#0A0A0A` black | 1px `#E4E4E4` | Cancel, back |
| Ghost | Transparent | `#6B6B6B` | — | Icon actions |
| Destructive | White | `#EF4444` red | 1px `#EF4444` | Delete |

All buttons: 6px corner radius, 32px min height, 12px horizontal padding.

---

## 8. Sidebar

```
Width:    52px
BG:       #F7F7F7
Icons:    20px SF Symbol, color #6B6B6B inactive / #0A0A0A active
Active:   3px left accent bar in #16C172 (green)
Hover:    #EBEBEB background fill
Spacing:  8px between icons
Top:      16px padding, no logo text (logo moves to World header)
Bottom:   status dot (green = recording, grey = paused)
```

---

## 9. README Updates

The README must be updated to reflect all features added since the last README update:

- Hot-word detection (`hot <keyword> for project <N> <task>`)
- AI todo framing via Ollama (project-aware, uses README + CLAUDE.md)
- Execute All — parallel and series modes
- Transcript → Todo with project assignment
- Per-project world model read/write
- New How It Works pipeline diagram (updated with hot-words + framing step)
- Updated Architecture diagram (new services: HotWordDetector, TodoFramingService)
- Updated Shortcuts table (new hot-word syntax)
- Roadmap: tick off completed items, add new ones

---

## 10. Out of Scope (this PR)

- Dark mode
- Custom font bundling (font choice TBD)
- Location/people tagging UI (data model exists, UI deferred)
- Automation/reminder scheduling UI
- Repeat task configuration
