# AutoClawd UI Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Replace the World Model tab with an interactive entity-relationship graph, and overhaul all UI surfaces with a brutalist aesthetic (zero corner radii, JetBrains Mono, neon green `#00FF41` accent, rectangular pill).

**Architecture:** New `BrutalistTheme` enum provides all design tokens (colors, fonts, geometry). Graph pipeline is pure value-type: `WorldModelGraphParser` parses markdown → `GraphModel`, `WorldModelGraphLayout` assigns positions, `WorldModelCanvasView` renders via SwiftUI Canvas API. MainPanelView and PillView are modified in-place to adopt the brutalist look.

**Tech Stack:** Swift 6, SwiftUI (macOS 13+), SwiftUI Canvas API (`TimelineView`-free, pure `Canvas` + `SpatialTapGesture`), no external dependencies, compiled with `swiftc` via `make`.

**Build command:** `make` from project root. All `Sources/*.swift` files compile in one pass.

**No unit test framework** — verification is: (1) `make` succeeds, (2) visual smoke check via `make run`.

---

### Task 1: BrutalistTheme design tokens + button styles

**Files:**
- Create: `Sources/BrutalistTheme.swift`

**Context:**
`BrutalistTheme` is a private enum (namespace only, no instances) used throughout MainPanelView and PillView. It defines all design tokens so downstream tasks don't hardcode values. `BrutalistButtonStyle` is a SwiftUI `ButtonStyle` that gives a rectangular bordered button with neon-on-press. Needs to be `internal` (not `private`) so all files can access it.

**Step 1: Create `Sources/BrutalistTheme.swift`**

```swift
import SwiftUI

// MARK: - Brutalist Design Tokens

enum BrutalistTheme {
    // Colors
    static let neonGreen       = Color(red: 0.0, green: 1.0, blue: 0.255)  // #00FF41
    static let divider         = Color.white.opacity(0.10)
    static let selectedBG      = Color.white.opacity(0.06)
    static let selectedAccent  = neonGreen

    // Typography — JetBrains Mono everywhere
    static let monoSM          = Font.custom("JetBrains Mono", size: 10)
    static let monoMD          = Font.custom("JetBrains Mono", size: 12)
    static let monoLG          = Font.custom("JetBrains Mono", size: 13).weight(.bold)
    static let monoHeader      = Font.custom("JetBrains Mono", size: 11).weight(.bold)

    // Geometry
    static let cornerRadius: CGFloat        = 0    // ZERO everywhere
    static let selectedAccentWidth: CGFloat = 4
    static let borderWidth: CGFloat         = 1
}

// MARK: - Brutalist Button Style

struct BrutalistButtonStyle: ButtonStyle {
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BrutalistTheme.monoMD)
            .foregroundColor(configuration.isPressed
                ? (isDestructive ? .red : BrutalistTheme.neonGreen)
                : .white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black)
            .overlay(
                Rectangle()
                    .stroke(configuration.isPressed
                        ? (isDestructive ? Color.red : BrutalistTheme.neonGreen)
                        : Color.white.opacity(0.35),
                            lineWidth: BrutalistTheme.borderWidth)
            )
    }
}
```

**Step 2: Build**

```bash
make
```

Expected: Successful build, no errors. The file compiles cleanly since it only uses SwiftUI.

**Step 3: Commit**

```bash
git add Sources/BrutalistTheme.swift
git commit -m "feat: add BrutalistTheme design tokens + button style"
```

---

### Task 2: PillMode.shortLabel

**Files:**
- Modify: `Sources/PillMode.swift` (add `shortLabel` computed property)

**Context:**
The brutalist pill will show `[AMB]`, `[TRS]`, or `[SRC]` as the mode button label instead of an SF Symbol icon. PillMode already has `displayName` and `icon`; add `shortLabel` after `icon`.

**Step 1: Add `shortLabel` to `PillMode`**

In `Sources/PillMode.swift`, after the `icon` computed property (after line 22, before `func next()`), insert:

```swift
    var shortLabel: String {
        switch self {
        case .ambientIntelligence: return "[AMB]"
        case .transcription:       return "[TRS]"
        case .aiSearch:            return "[SRC]"
        }
    }
```

**Step 2: Build**

```bash
make
```

Expected: Successful build.

**Step 3: Commit**

```bash
git add Sources/PillMode.swift
git commit -m "feat: add PillMode.shortLabel for brutalist pill display"
```

---

### Task 3: WorldModelGraph data models

**Files:**
- Create: `Sources/WorldModelGraph.swift`

**Context:**
Pure value-type data model used by the parser, layout engine, and Canvas view. No imports beyond Foundation needed (CGPoint/CGRect come from CoreFoundation which is transitively available via SwiftUI in other files — but this file only needs Foundation for UUID if needed; use plain `String` IDs instead to keep it clean).

**Step 1: Create `Sources/WorldModelGraph.swift`**

```swift
import CoreGraphics

// MARK: - Node Kind

enum NodeKind: Equatable {
    case section
    case fact
}

// MARK: - Edge Kind

enum EdgeKind: Equatable {
    case membership      // section → fact (parent owns child)
    case crossReference  // fact ↔ fact (shared keyword detected)
}

// MARK: - GraphNode

struct GraphNode: Identifiable, Equatable {
    let id: String          // e.g. "section-0", "fact-0-2"
    let label: String       // full display text (heading or bullet content)
    let kind: NodeKind
    var position: CGPoint = .zero   // set by layout
    var frame: CGRect = .zero       // set by layout; used for hit-testing
}

// MARK: - GraphEdge

struct GraphEdge: Identifiable, Equatable {
    let id: String
    let fromID: String
    let toID: String
    let kind: EdgeKind
}

// MARK: - GraphModel

struct GraphModel {
    var nodes: [GraphNode] = []
    var edges: [GraphEdge] = []

    var sectionNodes: [GraphNode] { nodes.filter { $0.kind == .section } }
    var factNodes: [GraphNode]    { nodes.filter { $0.kind == .fact    } }
}
```

**Step 2: Build**

```bash
make
```

Expected: Successful build.

**Step 3: Commit**

```bash
git add Sources/WorldModelGraph.swift
git commit -m "feat: add WorldModelGraph data models (GraphNode, GraphEdge, GraphModel)"
```

---

### Task 4: WorldModelGraphParser

**Files:**
- Create: `Sources/WorldModelGraphParser.swift`

**Context:**
Parses AutoClawd's world-model.md format. The format uses `##` headings for sections and `- ` bullet lines for facts. Cross-references: for each pair of facts from *different* sections, find shared word tokens ≥5 chars long; if any shared token exists, add a cross-reference edge (one edge per pair, regardless of how many shared tokens).

**Step 1: Create `Sources/WorldModelGraphParser.swift`**

```swift
import Foundation

struct WorldModelGraphParser {

    static func parse(_ markdown: String) -> GraphModel {
        var model = GraphModel()
        var currentSectionID: String? = nil
        var sectionIndex = 0
        var factIndex = 0

        let lines = markdown.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("## ") {
                // Section heading
                let heading = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                let nodeID = "section-\(sectionIndex)"
                model.nodes.append(GraphNode(id: nodeID, label: heading, kind: .section))
                currentSectionID = nodeID
                sectionIndex += 1

            } else if trimmed.hasPrefix("- "), let sectionID = currentSectionID {
                // Fact bullet
                let content = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                guard !content.isEmpty else { continue }
                let nodeID = "fact-\(factIndex)"
                model.nodes.append(GraphNode(id: nodeID, label: content, kind: .fact))
                // Membership edge: section → fact
                let edgeID = "edge-mem-\(factIndex)"
                model.edges.append(GraphEdge(id: edgeID, fromID: sectionID, toID: nodeID, kind: .membership))
                factIndex += 1
            }
            // Ignore other lines (top-level #, blank lines, etc.)
        }

        // Cross-reference detection
        let facts = model.factNodes
        for i in 0..<facts.count {
            for j in (i+1)..<facts.count {
                let nodeA = facts[i]
                let nodeB = facts[j]
                // Skip if they share the same parent section
                let parentA = parentSectionID(for: nodeA.id, in: model)
                let parentB = parentSectionID(for: nodeB.id, in: model)
                guard parentA != parentB else { continue }
                // Find shared tokens ≥5 chars
                let tokensA = tokens(in: nodeA.label)
                let tokensB = tokens(in: nodeB.label)
                if !tokensA.intersection(tokensB).isEmpty {
                    let edgeID = "edge-xref-\(i)-\(j)"
                    model.edges.append(GraphEdge(id: edgeID, fromID: nodeA.id, toID: nodeB.id, kind: .crossReference))
                }
            }
        }

        return model
    }

    // MARK: - Helpers

    private static func tokens(in text: String) -> Set<String> {
        let words = text.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count >= 5 }
        return Set(words)
    }

    private static func parentSectionID(for factID: String, in model: GraphModel) -> String? {
        model.edges
            .first(where: { $0.toID == factID && $0.kind == .membership })?
            .fromID
    }
}
```

**Step 2: Build**

```bash
make
```

Expected: Successful build.

**Step 3: Commit**

```bash
git add Sources/WorldModelGraphParser.swift
git commit -m "feat: add WorldModelGraphParser (markdown → GraphModel)"
```

---

### Task 5: WorldModelGraphLayout

**Files:**
- Create: `Sources/WorldModelGraphLayout.swift`

**Context:**
"Grid of Stars" layout: section nodes placed in a grid, fact nodes orbit their parent section in a circle. Uses fixed node sizes. The layout mutates the `GraphModel` in-place (sets `node.position` and `node.frame`).

**Step 1: Create `Sources/WorldModelGraphLayout.swift`**

```swift
import CoreGraphics
import Foundation

struct WorldModelGraphLayout {

    // Fixed node sizes
    static let sectionSize = CGSize(width: 120, height: 30)
    static let factSize    = CGSize(width: 100, height: 24)

    // Grid spacing between section centres
    static let gridSpacingX: CGFloat = 260
    static let gridSpacingY: CGFloat = 200

    // Orbit radius for facts around their section
    static let orbitRadius: CGFloat = 90

    static func apply(to model: inout GraphModel, in canvasSize: CGSize) {
        let sections = model.sectionNodes
        guard !sections.isEmpty else { return }

        // Compute grid dimensions
        let cols = max(1, Int(ceil(sqrt(Double(sections.count)))))
        let totalW = CGFloat(cols) * gridSpacingX
        let rows = Int(ceil(Double(sections.count) / Double(cols)))
        let totalH = CGFloat(rows) * gridSpacingY

        // Offset so grid is roughly centred in canvas
        let offsetX = max(gridSpacingX / 2, (canvasSize.width  - totalW) / 2 + gridSpacingX / 2)
        let offsetY = max(gridSpacingY / 2, (canvasSize.height - totalH) / 2 + gridSpacingY / 2)

        // Place section nodes
        var sectionPositions: [String: CGPoint] = [:]
        for (idx, section) in sections.enumerated() {
            let col = idx % cols
            let row = idx / cols
            let centre = CGPoint(
                x: offsetX + CGFloat(col) * gridSpacingX,
                y: offsetY + CGFloat(row) * gridSpacingY
            )
            sectionPositions[section.id] = centre
            setNode(id: section.id, centre: centre, size: sectionSize, in: &model)
        }

        // Place fact nodes in orbit around their parent section
        // Group facts by parent section
        var factsBySection: [String: [GraphNode]] = [:]
        for fact in model.factNodes {
            let parentID = model.edges
                .first(where: { $0.toID == fact.id && $0.kind == .membership })?
                .fromID ?? ""
            factsBySection[parentID, default: []].append(fact)
        }

        for (sectionID, facts) in factsBySection {
            guard let centre = sectionPositions[sectionID] else { continue }
            let count = facts.count
            for (i, fact) in facts.enumerated() {
                // Distribute evenly; start from top (-π/2)
                let angle = -CGFloat.pi / 2 + CGFloat(i) * (2 * CGFloat.pi / CGFloat(max(count, 1)))
                let factCentre = CGPoint(
                    x: centre.x + orbitRadius * cos(angle),
                    y: centre.y + orbitRadius * sin(angle)
                )
                setNode(id: fact.id, centre: factCentre, size: factSize, in: &model)
            }
        }
    }

    // MARK: - Helper

    private static func setNode(id: String, centre: CGPoint, size: CGSize, in model: inout GraphModel) {
        guard let idx = model.nodes.firstIndex(where: { $0.id == id }) else { return }
        model.nodes[idx].position = centre
        model.nodes[idx].frame = CGRect(
            x: centre.x - size.width / 2,
            y: centre.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
```

**Step 2: Build**

```bash
make
```

Expected: Successful build.

**Step 3: Commit**

```bash
git add Sources/WorldModelGraphLayout.swift
git commit -m "feat: add WorldModelGraphLayout (Grid of Stars positioning)"
```

---

### Task 6: WorldModelGraphView (Canvas + detail panel + container)

**Files:**
- Create: `Sources/WorldModelGraphView.swift`

**Context:**
Three views in one file:
- `WorldModelCanvasView`: a SwiftUI `Canvas` that renders the `GraphModel`. Black background, rectangular nodes (no rounding), neon green for cross-reference edges and selected node border. `SpatialTapGesture` for hit-testing.
- `WorldModelDetailPanel`: shows the selected node's kind badge + full label.
- `WorldModelGraphView`: the top-level view wired into MainPanelView. Contains a header with "REFRESH" and "EDIT RAW" toggle, then either the canvas or a raw `TextEditor`.

The canvas must be wrapped in a `ScrollView` when the graph exceeds the visible area — use `GeometryReader` to determine available size, then pass `max(available, requiredSize)` as the canvas frame.

**Step 1: Create `Sources/WorldModelGraphView.swift`**

```swift
import SwiftUI

// MARK: - WorldModelGraphView (container)

struct WorldModelGraphView: View {
    @ObservedObject var appState: AppState
    @State private var showRawEditor = false
    @State private var rawContent: String = ""
    @State private var model: GraphModel = GraphModel()
    @State private var selectedNodeID: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(BrutalistTheme.divider)
            if showRawEditor {
                rawEditor
            } else {
                graphArea
            }
        }
        .onAppear { refresh() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("WORLD MODEL")
                .font(BrutalistTheme.monoLG)
                .foregroundColor(.white)
            Spacer()
            Button(showRawEditor ? "SHOW GRAPH" : "EDIT RAW") {
                if showRawEditor {
                    // Save raw edits back to disk before switching to graph
                    appState.saveWorldModel(rawContent)
                    refresh()
                } else {
                    rawContent = appState.worldModelContent
                }
                showRawEditor.toggle()
            }
            .buttonStyle(BrutalistButtonStyle())

            if !showRawEditor {
                Button("REFRESH") { refresh() }
                    .buttonStyle(BrutalistButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Raw Editor

    private var rawEditor: some View {
        TextEditor(text: $rawContent)
            .font(.custom("JetBrains Mono", size: 12))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
            .onChange(of: rawContent) { newVal in
                appState.saveWorldModel(newVal)
            }
    }

    // MARK: - Graph Area

    private var graphArea: some View {
        VStack(spacing: 0) {
            ScrollView([.horizontal, .vertical]) {
                WorldModelCanvasView(
                    model: model,
                    selectedNodeID: $selectedNodeID
                )
                .frame(
                    width: requiredCanvasWidth,
                    height: requiredCanvasHeight
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let nodeID = selectedNodeID,
               let node = model.nodes.first(where: { $0.id == nodeID }) {
                Divider().background(BrutalistTheme.divider)
                WorldModelDetailPanel(node: node)
                    .frame(height: 60)
            }
        }
    }

    // MARK: - Helpers

    private var requiredCanvasWidth: CGFloat {
        let maxX = model.nodes.map { $0.frame.maxX }.max() ?? 400
        return max(600, maxX + 60)
    }

    private var requiredCanvasHeight: CGFloat {
        let maxY = model.nodes.map { $0.frame.maxY }.max() ?? 400
        return max(500, maxY + 60)
    }

    private func refresh() {
        let content = appState.worldModelContent
        var parsed = WorldModelGraphParser.parse(content)
        let size = CGSize(width: max(800, requiredCanvasWidth), height: max(600, requiredCanvasHeight))
        WorldModelGraphLayout.apply(to: &parsed, in: size)
        model = parsed
        selectedNodeID = nil
    }
}

// MARK: - WorldModelCanvasView

struct WorldModelCanvasView: View {
    let model: GraphModel
    @Binding var selectedNodeID: String?

    var body: some View {
        Canvas { ctx, size in
            // Black background
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))

            // Draw edges
            for edge in model.edges {
                guard
                    let fromNode = model.nodes.first(where: { $0.id == edge.fromID }),
                    let toNode   = model.nodes.first(where: { $0.id == edge.toID })
                else { continue }

                var path = Path()
                path.move(to: fromNode.position)
                path.addLine(to: toNode.position)

                let color: Color = edge.kind == .crossReference
                    ? BrutalistTheme.neonGreen
                    : Color.white.opacity(0.20)
                ctx.stroke(path, with: .color(color), lineWidth: 1)
            }

            // Draw nodes
            for node in model.nodes {
                let isSelected = node.id == selectedNodeID
                let nodeColor: Color = isSelected ? BrutalistTheme.neonGreen : Color.white.opacity(0.70)
                let borderWidth: CGFloat = isSelected ? 2 : 1

                // Rectangle fill (black) + border
                let rect = node.frame
                ctx.fill(Path(rect), with: .color(.black))
                ctx.stroke(Path(rect), with: .color(nodeColor), lineWidth: borderWidth)

                // Label — truncate if too long
                let label = String(node.label.prefix(node.kind == .section ? 18 : 15))
                let fontSize: CGFloat = node.kind == .section ? 10 : 9
                let resolvedText = Text(label)
                    .font(.custom("JetBrains Mono", size: fontSize).weight(node.kind == .section ? .bold : .regular))
                    .foregroundColor(nodeColor)

                ctx.draw(resolvedText, at: node.position, anchor: .center)
            }
        }
        .background(Color.black)
        .gesture(
            SpatialTapGesture()
                .onEnded { event in
                    let loc = event.location
                    if let hit = model.nodes.first(where: { $0.frame.contains(loc) }) {
                        selectedNodeID = hit.id == selectedNodeID ? nil : hit.id
                    } else {
                        selectedNodeID = nil
                    }
                }
        )
    }
}

// MARK: - WorldModelDetailPanel

struct WorldModelDetailPanel: View {
    let node: GraphNode

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Kind badge
            Text(node.kind == .section ? "[SECTION]" : "[FACT]")
                .font(BrutalistTheme.monoMD)
                .foregroundColor(BrutalistTheme.neonGreen)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .overlay(Rectangle().stroke(BrutalistTheme.neonGreen, lineWidth: 1))

            // Full label
            Text(node.label)
                .font(BrutalistTheme.monoMD)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black)
    }
}
```

**Step 2: Build**

```bash
make
```

Expected: Successful build. If `SpatialTapGesture` is unavailable (requires macOS 13), verify `TARGET = ...-macosx13.0` in Makefile — it is set, so this should be fine.

**Step 3: Commit**

```bash
git add Sources/WorldModelGraphView.swift
git commit -m "feat: add WorldModelGraphView with Canvas renderer and detail panel"
```

---

### Task 7: Wire WorldModelGraphView into MainPanelView

**Files:**
- Modify: `Sources/MainPanelView.swift` (replace `WorldModelTabView` call in `content` switch)

**Context:**
The `content` switch in `MainPanelView` currently routes `.worldModel` to `WorldModelTabView(appState: appState)`. Replace that with `WorldModelGraphView(appState: appState)`. `WorldModelTabView` struct can remain in the file (it's still used internally by `WorldModelGraphView` as the raw editor fallback — actually no, WorldModelGraphView has its own TextEditor; but keep `WorldModelTabView` to avoid compilation errors in case anything references it. Actually it's only used in the switch — so you can leave the struct but just stop routing to it).

**Step 1: Edit the `content` switch in `MainPanelView`**

In `Sources/MainPanelView.swift`, find the line (around line 116):
```swift
        case .worldModel: WorldModelTabView(appState: appState)
```

Replace it with:
```swift
        case .worldModel: WorldModelGraphView(appState: appState)
```

**Step 2: Build**

```bash
make
```

Expected: Successful build.

**Step 3: Commit**

```bash
git add Sources/MainPanelView.swift
git commit -m "feat: route World Model tab to WorldModelGraphView"
```

---

### Task 8: Brutalist MainPanelView sidebar

**Files:**
- Modify: `Sources/MainPanelView.swift` (sidebar styling, TabHeader → struct, [ON]/[OFF] badges)

**Context:**
Three changes to `MainPanelView`:
1. **Selected tab indicator**: replace `Color.primary.opacity(0.12)` filled `RoundedRectangle` with a `ZStack` that has a transparent `Rectangle()` background + a 4pt neon green left border when selected.
2. **Tab labels**: uppercase them (by applying `.textCase(.uppercase)` to the `Label`).
3. **Status footer `[ON]`/`[OFF]` badge**: replace the `Circle()` dots + "Listening"/"Off" text with monospace text badges like `[ON]` / `[OFF]`.
4. **`tabHeader` free function → `TabHeader` struct**: convert the global `func tabHeader<Trailing: View>(...)` to `struct TabHeader<Trailing: View>: View` so it can reference `BrutalistTheme` and be a proper SwiftUI view.

Note: after converting `tabHeader` to a struct, every call site that uses `tabHeader(...)` must become `TabHeader(title: ...) { ... }` — check all usages in the file. The pattern `tabHeader("Logs") { ... }` becomes `TabHeader(title: "LOGS") { ... }`.

**Step 1: Convert `tabHeader` free function to `TabHeader` struct**

Find the free function at the bottom of `Sources/MainPanelView.swift` (around line 388):

```swift
func tabHeader<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
    HStack {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
        Spacer()
        trailing()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
}
```

Replace it with:

```swift
struct TabHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title)
                .font(BrutalistTheme.monoLG)
                .foregroundColor(.white)
                .textCase(.uppercase)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
```

**Step 2: Update all `tabHeader(...)` call sites**

Search for `tabHeader(` in the file — there are occurrences in:
- `TodoTabView` — `tabHeader("To-Do List")`
- `WorldModelTabView` — `tabHeader("World Model")` — already removed from routing, but struct remains; update anyway
- `TranscriptTabView` — `tabHeader("Transcripts")`
- `SettingsTabView` — `tabHeader("Settings")`
- `LogsTabView` — `tabHeader("Logs")`

Replace each one: `tabHeader("Foo") { ... }` → `TabHeader("FOO") { ... }` (ALL CAPS the string).

WorldModelGraphView already uses `TabHeader` (implemented in Task 6 with proper BrutalistTheme). You only need to update the other tab views.

**Step 3: Update sidebar tab button styling**

In the `sidebar` computed property (around line 63-77), replace the button label background:

```swift
// BEFORE:
.background(
    RoundedRectangle(cornerRadius: 5)
        .fill(selectedTab == tab
              ? Color.primary.opacity(0.12)
              : Color.clear)
)
```

Replace with:

```swift
.background(
    ZStack(alignment: .leading) {
        Rectangle()
            .fill(selectedTab == tab
                  ? BrutalistTheme.selectedBG
                  : Color.clear)
        if selectedTab == tab {
            Rectangle()
                .fill(BrutalistTheme.neonGreen)
                .frame(width: BrutalistTheme.selectedAccentWidth)
        }
    }
)
```

Also apply `.textCase(.uppercase)` to the `Label` inside the button, and change `Label(tab.rawValue, systemImage: tab.icon)` to use `BrutalistTheme.monoMD` font:

```swift
Label(tab.rawValue.uppercased(), systemImage: tab.icon)
    .font(BrutalistTheme.monoMD)
    .frame(maxWidth: .infinity, alignment: .leading)
    // ...rest unchanged
```

**Step 4: Update status footer to [ON]/[OFF] badges**

In the `sidebar` status footer (around line 82-98), replace:

```swift
HStack {
    Circle()
        .fill(appState.micEnabled ? Color.green : Color.gray)
        .frame(width: 6, height: 6)
    Text(appState.micEnabled ? "Listening" : "Off")
        .font(.caption)
        .foregroundStyle(.secondary)
    Spacer()
    Text(appState.transcriptionMode == .groq ? "Groq" : "Local")
        .font(.caption2)
        .foregroundStyle(.tertiary)
}
```

With:

```swift
HStack {
    Text(appState.micEnabled ? "[ON]" : "[OFF]")
        .font(BrutalistTheme.monoSM)
        .foregroundColor(appState.micEnabled ? BrutalistTheme.neonGreen : .white.opacity(0.4))
    Spacer()
    Text(appState.transcriptionMode == .groq ? "[GROQ]" : "[LOCAL]")
        .font(BrutalistTheme.monoSM)
        .foregroundColor(.white.opacity(0.35))
}
```

**Step 5: Build**

```bash
make
```

Expected: Successful build. Fix any call-site compilation errors if `tabHeader` references were missed.

**Step 6: Commit**

```bash
git add Sources/MainPanelView.swift
git commit -m "feat: brutalist MainPanelView (neon tab accent, [ON]/[OFF] badges, TabHeader struct)"
```

---

### Task 9: Brutalist PillView

**Files:**
- Modify: `Sources/PillView.swift`

**Context:**
Four changes:
1. **Rectangular container** — replace `RoundedRectangle(cornerRadius: 6)` background/border with `Rectangle()`.
2. **Neon waveform bars** — change `barColor(index:)` to return `BrutalistTheme.neonGreen` when listening, `Color.white.opacity(0.20)` when not, and use `Rectangle()` (not `RoundedRectangle`) for each bar.
3. **Mode button** — replace `Image(systemName: pillMode.icon)` with `Text(pillMode.shortLabel)` in JetBrains Mono 10pt.
4. **Pause/play button** — replace SF Symbol images with `Text(state == .paused ? "[▶]" : "[⏸]")` in JetBrains Mono 10pt.

**Step 1: Update `pillBackground` and `pillBorder`**

Find (around line 175-183):
```swift
    private var pillBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.black)
    }

    private var pillBorder: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(Color.white.opacity(0.18), lineWidth: 1)
    }
```

Replace with:
```swift
    private var pillBackground: some View {
        Rectangle().fill(Color.black)
    }

    private var pillBorder: some View {
        Rectangle().stroke(Color.white.opacity(0.25), lineWidth: 1)
    }
```

**Step 2: Update `modeButton`**

Find (around line 68-77):
```swift
    private var modeButton: some View {
        Button(action: onCycleMode) {
            Image(systemName: pillMode.icon)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(state == .paused ? 0.4 : 1.0))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
```

Replace with:
```swift
    private var modeButton: some View {
        Button(action: onCycleMode) {
            Text(pillMode.shortLabel)
                .font(.custom("JetBrains Mono", size: 10).weight(.bold))
                .foregroundColor(state == .paused
                    ? .white.opacity(0.4)
                    : BrutalistTheme.neonGreen)
                .frame(width: 36, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
```

**Step 3: Update `pausePlayButton`**

Find (around line 80-90):
```swift
    private var pausePlayButton: some View {
        Button(action: onTogglePause) {
            Image(systemName: state == .paused ? "play.fill" : "pause.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white.opacity(state == .paused ? 0.9 : 0.5))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
```

Replace with:
```swift
    private var pausePlayButton: some View {
        Button(action: onTogglePause) {
            Text(state == .paused ? "[▶]" : "[⏸]")
                .font(.custom("JetBrains Mono", size: 10).weight(.bold))
                .foregroundColor(.white.opacity(state == .paused ? 0.9 : 0.5))
                .frame(width: 28, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
```

**Step 4: Update `waveformBars` to use neon color and rectangular bars**

Find (around line 103-111):
```swift
    private var waveformBars: some View {
        HStack(spacing: 3) {
            ForEach(0..<16, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor(index: i))
                    .frame(width: 3, height: barHeight(index: i))
                    .animation(.easeOut(duration: 0.08), value: audioLevel)
            }
        }
    }
```

Replace `RoundedRectangle(cornerRadius: 1)` with `Rectangle()`:
```swift
    private var waveformBars: some View {
        HStack(spacing: 3) {
            ForEach(0..<16, id: \.self) { i in
                Rectangle()
                    .fill(barColor(index: i))
                    .frame(width: 3, height: barHeight(index: i))
                    .animation(.easeOut(duration: 0.08), value: audioLevel)
            }
        }
    }
```

**Step 5: Update `barColor` to use neon green**

Find (around line 123-125):
```swift
    private func barColor(index: Int) -> Color {
        state == .listening ? .white : .white.opacity(0.3)
    }
```

Replace with:
```swift
    private func barColor(index: Int) -> Color {
        state == .listening ? BrutalistTheme.neonGreen : Color.white.opacity(0.20)
    }
```

**Step 6: Build**

```bash
make
```

Expected: Successful build.

**Step 7: Smoke test**

```bash
make run
```

Visual checks:
- Pill is now rectangular (sharp corners), neon green bars when mic is active
- Mode button shows `[AMB]`, `[TRS]`, or `[SRC]` text
- Pause shows `[⏸]`, play shows `[▶]`
- Main panel sidebar has neon left border on selected tab
- World Model tab shows graph (nodes + edges) on black canvas
- Tapping a node shows detail panel below

**Step 8: Commit**

```bash
git add Sources/PillView.swift
git commit -m "feat: brutalist PillView (rectangular, neon bars, text mode/pause buttons)"
```

---

## Summary of All New/Modified Files

| # | File | Change |
|---|------|--------|
| 1 | `Sources/BrutalistTheme.swift` | NEW |
| 2 | `Sources/PillMode.swift` | +`shortLabel` |
| 3 | `Sources/WorldModelGraph.swift` | NEW |
| 4 | `Sources/WorldModelGraphParser.swift` | NEW |
| 5 | `Sources/WorldModelGraphLayout.swift` | NEW |
| 6 | `Sources/WorldModelGraphView.swift` | NEW |
| 7 | `Sources/MainPanelView.swift` | route `.worldModel` → `WorldModelGraphView` |
| 8 | `Sources/MainPanelView.swift` | brutalist sidebar + `TabHeader` struct |
| 9 | `Sources/PillView.swift` | brutalist rectangular pill |
