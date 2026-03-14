import SwiftUI
import AppKit

// MARK: - AI Canvas View (Panel)
//
// Two tabs:
//
// [Canvas]        — Endless 2D workflow canvas. Event nodes laid out in a staggered
//                   grid connected by bezier curves. Each node: app context card
//                   with OCR snippet + voice transcript summary. Below the node field:
//                   AI use-case analysis panel and built/suggested capabilities.
//
// [Capabilities]  — FUCBC capability grid. Tapping a card shows sub-workflows.

struct AICanvasView: View {
    @ObservedObject var learnService: LearnModeService
    @State private var selectedTab: CanvasTab = .canvas
    @State private var allCapabilities: [Capability] = []
    @State private var canvasOffset: CGSize = .zero   // pan offset for the endless canvas
    @GestureState private var dragState: CGSize = .zero

    enum CanvasTab: String, CaseIterable {
        case canvas       = "Canvas"
        case capabilities = "Capabilities"
    }

    var body: some View {
        ZStack {
            AppTheme.glassAmbientBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                headerBar
                tabBar
                tabContent
            }
        }
        .onAppear { allCapabilities = CapabilityStore.shared.all() }
        .onChange(of: learnService.session?.builtCapability?.id) { _ in
            allCapabilities = CapabilityStore.shared.all()
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("AI Canvas")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Glass.textPrimary)
                Text("Workflow canvas · FUCBC capabilities")
                    .font(.system(size: 11))
                    .foregroundStyle(Glass.textSecondary)
            }
            Spacer()
            if learnService.isActive {
                HStack(spacing: 6) {
                    CanvasPulsingDot(color: .red)
                    Text("Recording")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                }
                Button("Stop") { learnService.stopSession() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.red.opacity(0.8))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.red.opacity(0.1))
                    .overlay(Capsule().stroke(Color.red.opacity(0.3), lineWidth: 1))
                    .clipShape(Capsule())
            } else {
                GlassButton("Record", icon: "record.circle", tint: .red) {
                    learnService.startSession()
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(Color.black.opacity(0.25))
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(CanvasTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
                } label: {
                    VStack(spacing: 4) {
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? Glass.textPrimary : Glass.textTertiary)
                        Rectangle()
                            .fill(selectedTab == tab ? Color.cyan : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
        }
        .background(Color.black.opacity(0.15))
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .canvas:      endlessCanvasView
        case .capabilities: capabilitiesTabView
        }
    }

    // =========================================================================
    // MARK: - ENDLESS CANVAS TAB
    // =========================================================================
    //
    // Layout:
    //   • Nodes are arranged in a staggered two-row layout, connected by bezier curves
    //   • The canvas is pannable via drag gesture
    //   • Below the node field (fixed at bottom): AI analysis strip + build controls
    // =========================================================================

    @ViewBuilder
    private var endlessCanvasView: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // ── Pannable node field ──
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    nodefield
                        .frame(
                            width: max(geo.size.width, nodeFieldWidth),
                            height: max(geo.size.height * 0.65, 320)
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: geo.size.height * 0.65)

                // ── Bottom analysis + build strip ──
                VStack(spacing: 0) {
                    GlassDivider()
                    bottomStrip
                }
                .frame(height: geo.size.height * 0.35)
            }
        }
    }

    // MARK: - Node Field (the actual canvas)

    private var nodeFieldWidth: CGFloat {
        let count = max(4, (learnService.session?.events.count ?? 0) + 1)
        return CGFloat(count) * (nodeWidth + connectorLength)
    }

    private let nodeWidth: CGFloat = 160
    private let nodeHeight: CGFloat = 180
    private let connectorLength: CGFloat = 48

    @ViewBuilder
    private var nodefield: some View {
        let session = learnService.session
        let events = session?.events ?? []
        ZStack(alignment: .topLeading) {
            // ── Bezier connector lines (drawn beneath nodes) ──
            connectorOverlay(nodeCount: max(events.count, 1))

            // ── Placeholder nodes when no events yet ──
            if events.isEmpty {
                HStack(spacing: connectorLength) {
                    ForEach(0..<4, id: \.self) { i in
                        placeholderNode(index: i)
                            .offset(y: i % 2 == 0 ? 0 : 30)
                    }
                }
                .padding(24)
            }

            // ── Real event nodes ──
            HStack(spacing: connectorLength) {
                ForEach(Array(events.enumerated()), id: \.offset) { idx, event in
                    eventNode(event: event, index: idx)
                        .offset(y: idx % 2 == 0 ? 0 : 30)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
                // Live recording node
                if learnService.isActive {
                    recordingNode
                        .offset(y: events.count % 2 == 0 ? 0 : 30)
                }
            }
            .padding(24)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: events.count)
        }
    }

    // MARK: - Bezier Connectors

    private func connectorOverlay(nodeCount: Int) -> some View {
        Canvas { ctx, size in
            let count = max(nodeCount, 1)
            let stepX = nodeWidth + connectorLength
            let yBase: CGFloat = 24 + nodeHeight / 2

            for i in 0..<count {
                let x0 = 24 + CGFloat(i) * stepX + nodeWidth
                let y0 = yBase + (CGFloat(i % 2) * 30)
                let x1 = x0 + connectorLength
                let y1 = yBase + (CGFloat((i + 1) % 2) * 30)

                var path = Path()
                path.move(to: CGPoint(x: x0, y: y0))
                path.addCurve(
                    to: CGPoint(x: x1, y: y1),
                    control1: CGPoint(x: x0 + connectorLength * 0.5, y: y0),
                    control2: CGPoint(x: x1 - connectorLength * 0.5, y: y1)
                )

                ctx.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color.cyan.opacity(0.35),
                            Color.cyan.opacity(0.15)
                        ]),
                        startPoint: CGPoint(x: x0, y: y0),
                        endPoint: CGPoint(x: x1, y: y1)
                    ),
                    lineWidth: 1.5
                )

                // Arrow head
                let arrowSize: CGFloat = 5
                let angle: CGFloat = atan2(y1 - y0, x1 - x0)
                let arrowPath = arrowHead(at: CGPoint(x: x1, y: y1), angle: angle, size: arrowSize)
                ctx.fill(arrowPath, with: .color(Color.cyan.opacity(0.4)))
            }
        }
    }

    private func arrowHead(at point: CGPoint, angle: CGFloat, size: CGFloat) -> Path {
        var path = Path()
        path.move(to: point)
        path.addLine(to: CGPoint(
            x: point.x - size * cos(angle - 0.4),
            y: point.y - size * sin(angle - 0.4)
        ))
        path.addLine(to: CGPoint(
            x: point.x - size * cos(angle + 0.4),
            y: point.y - size * sin(angle + 0.4)
        ))
        path.closeSubpath()
        return path
    }

    // MARK: - Event Node Card

    private func eventNode(event: LearnEvent, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                // Glass card background
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(nodeFill(for: event.appName))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Glass.borderGradient, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 8) {
                    // ── App label row ──
                    HStack(spacing: 6) {
                        if let app = event.appName {
                            Text(appInitial(app))
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.black.opacity(0.7))
                                .frame(width: 20, height: 20)
                                .background(appColor(for: app))
                                .clipShape(Circle())
                            Text(app)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(appColor(for: app))
                                .lineLimit(1)
                        }
                        Spacer()
                        Text("#\(index + 1)")
                            .font(.system(size: 8))
                            .foregroundStyle(Glass.textTertiary)
                    }

                    // ── OCR text snippet ──
                    if !event.ocrSnippet.isEmpty {
                        Text(String(event.ocrSnippet.prefix(100)))
                            .font(.system(size: 9))
                            .foregroundStyle(Glass.textSecondary)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // ── Speech snippet ──
                    if !event.speechSnippet.isEmpty {
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(Color.cyan.opacity(0.6))
                            Text(String(event.speechSnippet.prefix(70)))
                                .font(.system(size: 9, design: .serif))
                                .foregroundStyle(Color.cyan.opacity(0.75))
                                .lineLimit(2)
                                .italic()
                        }
                        .padding(6)
                        .background(Color.cyan.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cyan.opacity(0.12)))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    // ── URL badge ──
                    if let url = event.detectedURLs.first {
                        HStack(spacing: 3) {
                            Image(systemName: "link")
                                .font(.system(size: 7))
                                .foregroundStyle(.blue.opacity(0.6))
                            Text(urlDomain(url))
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(.blue.opacity(0.7))
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)

                    // ── Timestamp ──
                    Text(event.timestamp.formatted(.dateTime.hour().minute().second()))
                        .font(.system(size: 7))
                        .foregroundStyle(Glass.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(10)
            }
            .frame(width: nodeWidth, height: nodeHeight)
        }
    }

    // MARK: - Placeholder Node

    private func placeholderNode(index: Int) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(learnService.isActive ? 0.04 : 0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            Color.white.opacity(learnService.isActive ? 0.10 : 0.05),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                )
            VStack(spacing: 8) {
                if learnService.isActive {
                    CanvasPulsingDot(color: .cyan.opacity(0.4))
                    Text("~\(index * 5)s")
                        .font(.system(size: 9))
                        .foregroundStyle(Glass.textTertiary)
                } else {
                    Image(systemName: "square.dashed")
                        .font(.system(size: 20))
                        .foregroundStyle(Glass.textTertiary)
                    Text("Event \(index + 1)")
                        .font(.system(size: 9))
                        .foregroundStyle(Glass.textTertiary)
                }
            }
        }
        .frame(width: nodeWidth, height: nodeHeight)
    }

    // MARK: - Recording Node

    private var recordingNode: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.red.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.red.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
                )
            VStack(spacing: 8) {
                CanvasPulsingDot(color: .red)
                Text("Recording…")
                    .font(.system(size: 10))
                    .foregroundStyle(.red.opacity(0.7))
            }
        }
        .frame(width: nodeWidth, height: nodeHeight)
    }

    // MARK: - Bottom Strip (analysis + build)

    @ViewBuilder
    private var bottomStrip: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let session = learnService.session {
                    // ── Analysis panel ──
                    if session.events.count >= 2 {
                        analysisPanel(session: session)
                    }

                    // ── Build / progress / result ──
                    buildSection(session: session)
                } else {
                    canvasBottomEmptyState
                }
            }
            .padding(14)
        }
        .background(Color.black.opacity(0.2))
    }

    // MARK: - Analysis Panel

    private func analysisPanel(session: LearnSession) -> some View {
        LiquidGlassCard(tint: .purple) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    GlassIconBadge("brain.head.profile", size: 28, tint: .purple)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Use-Case Analysis")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Glass.textPrimary)
                        Text("\(session.events.count) events · \(Int(session.events.count * 5))s recorded")
                            .font(.system(size: 9))
                            .foregroundStyle(Glass.textSecondary)
                    }
                    Spacer()
                    if session.hasEnoughContext {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.green)
                            Text("Ready to build")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.green.opacity(0.8))
                        }
                    }
                }

                GlassDivider()

                // App journey
                let apps = orderedApps(from: session.events)
                if !apps.isEmpty {
                    HStack(spacing: 4) {
                        Text("Journey:")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Glass.textTertiary)
                        ForEach(Array(apps.enumerated()), id: \.offset) { i, app in
                            Text(app)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(appColor(for: app))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(appColor(for: app).opacity(0.10))
                                .clipShape(Capsule())
                            if i < apps.count - 1 {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 7))
                                    .foregroundStyle(Glass.textTertiary)
                            }
                        }
                    }
                }

                // Speech summary
                let speech = session.events.compactMap { e -> String? in
                    e.speechSnippet.isEmpty ? nil : e.speechSnippet
                }.joined(separator: " · ")
                if !speech.isEmpty {
                    Text(String(speech.prefix(180)))
                        .font(.system(size: 10, design: .serif))
                        .foregroundStyle(Glass.textSecondary)
                        .italic()
                        .lineLimit(2)
                }
            }
        }
    }

    // MARK: - Build Section

    @ViewBuilder
    private func buildSection(session: LearnSession) -> some View {
        switch session.phase {
        case .collecting:
            if session.hasEnoughContext {
                GlassButton("Build Capability", icon: "wand.and.stars", tint: .green, isLarge: true) {
                    Task { await learnService.buildCapability() }
                }
                .frame(maxWidth: .infinity)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }

        case .building:
            buildProgressCard(output: session.buildOutput)
                .transition(.move(edge: .bottom).combined(with: .opacity))

        case .done:
            VStack(spacing: 10) {
                if let cap = session.builtCapability {
                    newCapabilityCard(cap)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
                if !session.suggestedCapabilities.isEmpty {
                    relatedCapabilitiesCard(session.suggestedCapabilities)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

        case .failed(let msg):
            failureCard(msg)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }

    private func buildProgressCard(output: String) -> some View {
        let isBuilding: Bool
        if case .building = learnService.session?.phase { isBuilding = true }
        else { isBuilding = false }

        return LiquidGlassCard(tint: .orange) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    GlassIconBadge("terminal.fill", size: 28, tint: .orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("FUCBC Running")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Glass.textPrimary)
                        Text("Claude is analyzing your session pattern…")
                            .font(.system(size: 9))
                            .foregroundStyle(Glass.textSecondary)
                    }
                    Spacer()
                    if isBuilding { ProgressView().scaleEffect(0.6).tint(.orange) }
                }
                if !output.isEmpty {
                    Text(output.suffix(400).description)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Glass.textSecondary)
                        .lineLimit(8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func newCapabilityCard(_ cap: Capability) -> some View {
        LiquidGlassCard(tint: .green) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(cap.emoji).font(.system(size: 28))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("New Capability Unlocked")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.green.opacity(0.8))
                        Text(cap.name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Glass.textPrimary)
                    }
                    Spacer()
                    GlassChip(cap.category.label, icon: cap.category.icon)
                }
                Text(cap.description)
                    .font(.system(size: 11))
                    .foregroundStyle(Glass.textSecondary)
                    .lineLimit(2)

                if !cap.subWorkflows.isEmpty {
                    GlassDivider()
                    HStack(spacing: 6) {
                        ForEach(cap.subWorkflows.prefix(4)) { sw in
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.green.opacity(0.6))
                                Text(sw.name.replacingOccurrences(of: "_", with: " "))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(Glass.textPrimary)
                            }
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.green.opacity(0.08))
                            .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }

    private func relatedCapabilitiesCard(_ caps: [Capability]) -> some View {
        LiquidGlassCard(tint: .cyan) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Related capabilities")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Glass.textTertiary)
                ForEach(caps.prefix(3)) { cap in
                    HStack(spacing: 8) {
                        Text(cap.emoji).font(.system(size: 16))
                        Text(cap.name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Glass.textPrimary)
                        Spacer()
                        Text(cap.category.label)
                            .font(.system(size: 9))
                            .foregroundStyle(Glass.textTertiary)
                    }
                }
            }
        }
    }

    private func failureCard(_ msg: String) -> some View {
        LiquidGlassCard(tint: .red) {
            HStack(spacing: 10) {
                GlassIconBadge("xmark.circle.fill", size: 28, tint: .red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Build Failed")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Glass.textPrimary)
                    Text(msg)
                        .font(.system(size: 10))
                        .foregroundStyle(Glass.textSecondary)
                }
                Spacer()
                Button("Retry") {
                    learnService.session?.phase = .collecting
                    learnService.session?.buildOutput = ""
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.red)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.red.opacity(0.1))
                .overlay(Capsule().stroke(Color.red.opacity(0.3), lineWidth: 1))
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - Bottom Empty State

    private var canvasBottomEmptyState: some View {
        VStack(spacing: 12) {
            GlassIconBadge("rectangle.3.group.fill", size: 48, tint: .cyan)
            Text("Workflow Canvas")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Glass.textPrimary)
            Text("Record a session to see your workflow\nas connected events on the canvas above")
                .font(.system(size: 12))
                .foregroundStyle(Glass.textSecondary)
                .multilineTextAlignment(.center)
            GlassButton("Start Recording", icon: "record.circle", tint: .red, isLarge: true) {
                learnService.startSession()
            }
        }
        .padding()
    }

    // =========================================================================
    // MARK: - CAPABILITIES TAB
    // =========================================================================

    @ViewBuilder
    private var capabilitiesTabView: some View {
        if allCapabilities.isEmpty {
            capabilitiesEmptyState
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(allCapabilities) { cap in
                        capabilityCard(cap)
                    }
                }
                .padding(16)
            }
        }
    }

    private func capabilityCard(_ cap: Capability) -> some View {
        LiquidGlassCard(tint: categoryColor(cap.category)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(cap.emoji).font(.system(size: 28))
                    Spacer()
                    GlassChip(cap.category.label, icon: cap.category.icon)
                }
                Text(cap.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Glass.textPrimary)
                    .lineLimit(2)
                Text(cap.description)
                    .font(.system(size: 11))
                    .foregroundStyle(Glass.textSecondary)
                    .lineLimit(3)

                GlassDivider()

                // Sub-workflow steps
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(cap.subWorkflows.prefix(3)) { sw in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(categoryColor(cap.category).opacity(0.5))
                                .frame(width: 4, height: 4)
                            Text(sw.name.replacingOccurrences(of: "_", with: " "))
                                .font(.system(size: 10))
                                .foregroundStyle(Glass.textTertiary)
                        }
                    }
                }

                // Trigger chips
                if !cap.triggers.apps.isEmpty || !cap.triggers.urlPatterns.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(cap.triggers.apps.prefix(2), id: \.self) { app in
                                triggerChip(app, icon: "app.fill", color: appColor(for: app))
                            }
                            ForEach(cap.triggers.urlPatterns.prefix(2), id: \.self) { url in
                                triggerChip(url, icon: "link", color: .blue)
                            }
                        }
                    }
                }
            }
        }
    }

    private func triggerChip(_ label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 8))
            Text(label).font(.system(size: 9))
        }
        .foregroundStyle(color.opacity(0.8))
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(color.opacity(0.08))
        .overlay(Capsule().stroke(color.opacity(0.2), lineWidth: 1))
        .clipShape(Capsule())
    }

    private var capabilitiesEmptyState: some View {
        VStack(spacing: 20) {
            GlassIconBadge("sparkles", size: 64, tint: .purple)
            Text("No Capabilities Yet")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Glass.textPrimary)
            Text("Record a session and tap Build to unlock your first capability")
                .font(.system(size: 13))
                .foregroundStyle(Glass.textSecondary)
                .multilineTextAlignment(.center)
            GlassButton("Go Record", icon: "record.circle", tint: .red, isLarge: true) {
                withAnimation { selectedTab = .canvas }
                learnService.startSession()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Helpers

    private func appColor(for app: String?) -> Color {
        guard let app else { return .cyan }
        let l = app.lowercased()
        if l.contains("safari") || l.contains("chrome") || l.contains("firefox") { return .blue }
        if l.contains("code") || l.contains("xcode") || l.contains("cursor") { return .purple }
        if l.contains("mail") || l.contains("outlook") || l.contains("fastmail") { return .red }
        if l.contains("slack") || l.contains("discord") || l.contains("teams") { return .indigo }
        if l.contains("terminal") || l.contains("iterm") || l.contains("warp") { return .green }
        if l.contains("figma") || l.contains("sketch") || l.contains("framer") { return .orange }
        if l.contains("thread") || l.contains("instagram") || l.contains("twitter") { return .pink }
        if l.contains("notion") || l.contains("obsidian") || l.contains("bear") { return .yellow }
        return .cyan
    }

    private func appInitial(_ app: String) -> String {
        String(app.prefix(1)).uppercased()
    }

    private func nodeFill(for app: String?) -> Color {
        appColor(for: app).opacity(0.07)
    }

    private func urlDomain(_ url: String) -> String {
        if let host = URL(string: url)?.host { return host }
        return url.count > 28 ? String(url.prefix(28)) + "…" : url
    }

    private func categoryColor(_ cat: CapabilityCategory) -> Color {
        switch cat {
        case .research:      return .purple
        case .automation:    return .green
        case .communication: return .blue
        case .development:   return .orange
        case .discovery:     return .cyan
        case .organization:  return .indigo
        case .creative:      return .pink
        case .search:        return .teal
        case .analysis:      return .mint
        case .marketing:     return .red
        case .system:        return .gray
        }
    }

    private func orderedApps(from events: [LearnEvent]) -> [String] {
        var seen = Set<String>()
        return events.compactMap { $0.appName }.filter { seen.insert($0).inserted }
    }
}

// MARK: - Canvas Pulsing Dot

struct CanvasPulsingDot: View {
    let color: Color
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.4), lineWidth: pulsing ? 6 : 0)
                    .scaleEffect(pulsing ? 2.5 : 1)
                    .opacity(pulsing ? 0 : 1)
                    .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: pulsing)
            )
            .onAppear { pulsing = true }
    }
}
