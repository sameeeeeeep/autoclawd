# AutoClawd UI Redesign: World Model Graph + Brutalist Overhaul

## Goal

Redesign the AutoClawd UI with two interrelated changes:
1. Replace the plain-text World Model tab with an interactive entity-relationship **graph** rendered on a SwiftUI Canvas
2. Apply a **brutalist aesthetic** across all UI surfaces — zero corner radii, JetBrains Mono everywhere, neon green (`#00FF41`) accent, ALL CAPS labels, rectangular pill

---

## Part 1: World Model Graph

### Data Model

```swift
// Sources/WorldModelGraph.swift (NEW)

struct GraphNode: Identifiable, Equatable {
    let id: String          // e.g. "section-Projects", "fact-0-0"
    let label: String       // display text (full line content)
    let kind: NodeKind      // .section or .fact
    var position: CGPoint   // set by layout algorithm
    var frame: CGRect       // set by layout algorithm
}

enum NodeKind { case section, fact }

struct GraphEdge: Identifiable {
    let id: String
    let fromID: String
    let toID: String
    let kind: EdgeKind      // .membership (section→fact) or .crossReference
}

enum EdgeKind { case membership, crossReference }

struct GraphModel {
    var nodes: [GraphNode]
    var edges: [GraphEdge]
}
```

### Parser: `WorldModelGraphParser`

**Algorithm:**
1. Split markdown on `##` headings — each creates a `.section` node
2. Bullet lines (`- …`) under a heading create `.fact` nodes owned by that section
3. Cross-reference detection: for each pair of fact nodes in *different* sections, extract word tokens ≥5 chars; if they share ≥1 token, add a `.crossReference` edge

```swift
// Sources/WorldModelGraphParser.swift (NEW)
struct WorldModelGraphParser {
    static func parse(_ markdown: String) -> GraphModel
}
```

### Layout: `WorldModelGraphLayout`

**"Grid of Stars" algorithm:**
- Section nodes arranged in a grid (ceil(sqrt(N)) columns)
- Fact nodes orbit their parent section in a circle (radius proportional to count)
- Fixed node sizes: sections `110 × 28 pt`, facts `90 × 22 pt`
- Minimum canvas size: `800 × 600 pt`

```swift
// Sources/WorldModelGraphLayout.swift (NEW)
struct WorldModelGraphLayout {
    static func apply(to model: inout GraphModel, in size: CGSize)
}
```

### Canvas View: `WorldModelCanvasView`

**Rendering:**
- Black background (`Color.black`)
- Edges first: membership edges = `Color.white.opacity(0.25)` 1pt lines; cross-reference edges = `BrutalistTheme.neonGreen` 1pt lines
- Nodes: `Rectangle()` (no rounding), fill `Color.black`, stroke white 1pt (selected: neon green 2pt)
- Labels: `ctx.draw(Text(node.label))` in JetBrains Mono 10pt, white
- `SpatialTapGesture` on the Canvas for hit-testing (iterate nodes, check `node.frame.contains(location)`)
- `@State var selectedNodeID: String?`
- Shows `WorldModelDetailPanel` below or beside canvas when selection is non-nil

```swift
// Sources/WorldModelGraphView.swift (NEW)
struct WorldModelCanvasView: View
struct WorldModelDetailPanel: View   // shows [SECTION] or [FACT] badge + full label in neon green
```

### Integration

Replace `WorldModelTabView` body with `WorldModelGraphView(appState: appState)` which hosts:
- A `WorldModelCanvasView` (scrollable if needed)
- Refresh/Edit toggle: "EDIT RAW" button in header switches back to the plain `TextEditor` for editing

The graph re-parses from `appState.worldModelContent` on each refresh.

---

## Part 2: Brutalist Design System

### Design Tokens

```swift
// Sources/BrutalistTheme.swift (NEW)
private enum BrutalistTheme {
    // Colors
    static let neonGreen    = Color(red: 0.0, green: 1.0, blue: 0.255)   // #00FF41
    static let divider      = Color.white.opacity(0.10)
    static let selectedBG   = Color.white.opacity(0.12)

    // Typography (JetBrains Mono everywhere)
    static let monoSM       = Font.custom("JetBrains Mono", size: 10)
    static let monoMD       = Font.custom("JetBrains Mono", size: 12)
    static let monoLG       = Font.custom("JetBrains Mono", size: 13).weight(.bold)
    static let monoHeader   = Font.custom("JetBrains Mono", size: 12).weight(.bold)

    // Geometry
    static let cornerRadius: CGFloat = 0      // ZERO everywhere
    static let selectedAccentWidth: CGFloat = 4
    static let borderWidth: CGFloat = 1
}
```

### Button Styles

```swift
// Also in BrutalistTheme.swift
struct BrutalistButtonStyle: ButtonStyle
// Rectangle border, neon green on press, ALL CAPS label, 1pt border

struct BrutalistDestructiveButtonStyle: ButtonStyle
// Same but red accent
```

### Sidebar Changes (`MainPanelView`)

- Selected tab: 4px neon green left border rectangle instead of filled background
- Tab labels: ALL CAPS (`"TO-DO"`, `"WORLD MODEL"`, etc.)
- `TabHeader` free function → converted to `struct TabHeader<Trailing: View>: View` to allow use of `BrutalistTheme` inside
- Status footer: `[ON]` / `[OFF]` text badges instead of colored circle dots

### Pill View Changes (`PillView`)

- Container: `Rectangle()` borders, `cornerRadius: 0` — rectangular pill chip
- Waveform bars: neon green when `isListening`, grey otherwise
- Mode button: text label showing `pillMode.shortLabel` → `[AMB]` / `[TRS]` / `[SRC]`
- Pause/play button: `[▶]` / `[⏸]` monospace text button

### `PillMode.shortLabel` Addition

```swift
// Sources/PillMode.swift (MODIFY)
var shortLabel: String {
    switch self {
    case .ambientIntelligence: return "[AMB]"
    case .transcription:       return "[TRS]"
    case .aiSearch:            return "[SRC]"
    }
}
```

---

## Affected Files

| File | Change |
|------|--------|
| `Sources/BrutalistTheme.swift` | NEW — design tokens + button styles |
| `Sources/WorldModelGraph.swift` | NEW — GraphNode, GraphEdge, GraphModel, NodeKind, EdgeKind |
| `Sources/WorldModelGraphParser.swift` | NEW — markdown → GraphModel |
| `Sources/WorldModelGraphLayout.swift` | NEW — "Grid of Stars" layout |
| `Sources/WorldModelGraphView.swift` | NEW — WorldModelCanvasView + WorldModelDetailPanel |
| `Sources/MainPanelView.swift` | MODIFY — TabHeader struct, brutalist sidebar, WorldModelGraphView integration |
| `Sources/PillView.swift` | MODIFY — rectangular chip, neon bars, [AMB]/[TRS]/[SRC] text |
| `Sources/PillMode.swift` | MODIFY — add shortLabel |

---

## Out of Scope (YAGNI)

- Zoom/pan on the graph (no pinch gesture — scroll only if canvas overflows)
- Animated edge transitions
- Graph editing (drag nodes) — read-only graph, edit via raw text toggle
- Dark/light mode toggle — app is always dark
- Accessibility labels on Canvas nodes
