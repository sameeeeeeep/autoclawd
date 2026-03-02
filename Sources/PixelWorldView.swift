// Sources/PixelWorldView.swift
//
// Pixel-art world visualization of the AutoClawd pipeline.
// Embeds Resources/PixelWorld/index.html in a WKWebView and bridges
// pipeline events from AppState → JavaScript → animated characters.

import SwiftUI
import WebKit
import Combine

// MARK: - PixelWorldEvent

/// Pipeline events forwarded to the pixel world.
enum PixelWorldEvent {
    case transcript
    case cleaning(duration: Double)
    case analysis(duration: Double)
    case taskCreated(title: String, mode: String)
    case taskExecuting   // auto-mode: auto-approve at Approval desk → Claude Code
    case taskApproved    // ask-mode: user tapped Accept → Approval desk → Claude Code
    case taskDone
    case whatsapp
    case reset

    var jsCall: String {
        // Call game.js window functions directly — no adapter.js indirection.
        // game.js exports: window.assignNextAgent, window.advancePipeline,
        //                  window.returnToQueue, window.resetPipeline
        // Desk indices: 0=Comms 1=Analysis 2=Projects 3=Approval 4=Claude Code 5=Archive
        switch self {
        case .transcript:
            // New transcript → dequeue front agent, send to Comms desk
            return "window.assignNextAgent && window.assignNextAgent()"
        case .cleaning:
            // Cleaning done → advance agent from Comms area → Analysis desk (idx 1)
            return "window.advancePipeline && window.advancePipeline('atComms','toAnalysis',1)"
        case .analysis:
            // Analysis done → advance → Projects desk (idx 2)
            return "window.advancePipeline && window.advancePipeline('atAnalysis','toProjects',2)"
        case .taskCreated:
            // Task created → advance → Approval desk (idx 3)
            return "window.advancePipeline && window.advancePipeline('atProjects','toApproval',3)"
        case .taskExecuting:
            // Auto-mode: immediately advance Approval → Claude Code desk (idx 4)
            return "window.advancePipeline && window.advancePipeline('atApproval','toClaude',4)"
        case .taskApproved:
            // Ask-mode: user approved → Approval desk → Claude Code desk (idx 4)
            return "window.advancePipeline && window.advancePipeline('atApproval','toClaude',4)"
        case .taskDone:
            // Task complete → advance → Archive desk (idx 5)
            return "window.advancePipeline && window.advancePipeline('atClaude','toArchive',5)"
        case .whatsapp:
            // WhatsApp message → treat like a new transcript (dequeue agent)
            return "window.assignNextAgent && window.assignNextAgent()"
        case .reset:
            return "window.resetPipeline && window.resetPipeline()"
        }
    }
}

// MARK: - PixelWorldCoordinator

/// Bridges JS → Swift messages and holds a weak WKWebView reference for event dispatch.
/// Events sent before the page is ready are buffered and replayed once the JS signals
/// `webviewReady` (so nothing is lost during the ~1s page-load window).
final class PixelWorldCoordinator: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?

    // Buffer JS calls that arrive before the page finishes loading.
    private var pendingJS: [String] = []
    private var isReady = false

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        switch type {
        case "webviewReady":
            Log.info(.ui, "PixelWorld: page ready — draining \(pendingJS.count) buffered events")
            // Delay slightly so _initPixelWorld (80 ms setTimeout in adapter.js) finishes
            // setting up agents before we replay queued pipeline events.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.isReady = true
                self?.drainPending()
            }
        default:
            Log.info(.ui, "PixelWorld: JS message '\(type)'")
        }
    }

    /// Evaluate arbitrary JS on the web view. Buffers the call if the page isn't ready yet.
    @MainActor
    func send(_ js: String) {
        guard isReady else {
            Log.info(.ui, "PixelWorld: BUFFERED (not ready) — \(js.prefix(60))")
            pendingJS.append(js)
            return
        }
        Log.info(.ui, "PixelWorld: JS → \(js.prefix(60))")
        webView?.evaluateJavaScript(js) { _, err in
            if let err { Log.warn(.ui, "PixelWorld JS error: \(err)") }
        }
    }

    @MainActor
    func sendEvent(_ event: PixelWorldEvent) {
        send(event.jsCall)
    }

    /// Reset ready state when the WebView navigates to a new page (e.g. on reload).
    @MainActor
    func reset() {
        isReady  = false
        pendingJS = []
    }

    // MARK: Private

    private func drainPending() {
        let queued = pendingJS
        pendingJS = []
        for js in queued {
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}

// MARK: - PixelWorldWebView  (AppKit representable)

struct PixelWorldWebView: NSViewRepresentable {
    @ObservedObject var appState: AppState
    let coordinator: PixelWorldCoordinator

    // Track already-sent pipeline-task IDs so we don't re-fire
    @State private var sentTaskIDs = Set<String>()

    func makeCoordinator() -> PixelWorldCoordinator { coordinator }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "worldBridge")

        // Allow local file access for Resources/PixelWorld/
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.wantsLayer = true
        wv.layer?.backgroundColor = NSColor(red: 0.02, green: 0.02, blue: 0.06, alpha: 1).cgColor
        context.coordinator.webView = wv

        loadWorld(wv)
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        // Sync newly appeared pipeline tasks to the world
        syncNewTasks(context.coordinator)
    }

    // MARK: Private

    private func loadWorld(_ wv: WKWebView) {
        guard let url = Bundle.main.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "PixelWorld"
        ) else {
            Log.error(.ui, "PixelWorld: index.html not found in bundle")
            // Fallback: load an inline error page
            wv.loadHTMLString(
                "<body style='background:#05050f;color:#A78BFA;font:14px monospace;" +
                "display:flex;align-items:center;justify-content:center;height:100vh'>" +
                "<div>⚠️ PixelWorld/index.html not found in app bundle.<br>" +
                "Run <code>make</code> to rebuild.</div></body>",
                baseURL: nil
            )
            return
        }
        wv.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    @MainActor
    private func syncNewTasks(_ coord: PixelWorldCoordinator) {
        // We can't mutate @State here; task sync is done via AppState observation in the view.
    }
}

// MARK: - PixelWorldView  (SwiftUI shell)

struct PixelWorldView: View {
    @ObservedObject var appState: AppState

    // Stable coordinator for the lifetime of this view
    @StateObject private var bridge = PixelWorldBridge()

    var body: some View {
        ZStack {
            PixelWorldWebView(appState: appState, coordinator: bridge.coordinator)
                .ignoresSafeArea()

            // Controls overlay (top-right corner)
            VStack {
                HStack {
                    Spacer()
                    controlBar
                        .padding(10)
                }
                Spacer()
            }

            // Pending-task approval strip (bottom) — only visible when tasks need action
            let pendingTasks = appState.pipelineTasks.filter {
                $0.status == .pending_approval || $0.status == .needs_input
            }
            if !pendingTasks.isEmpty {
                VStack {
                    Spacer()
                    pendingApprovalStrip(tasks: pendingTasks)
                }
            }
        }
        // ── Pipeline event wiring ────────────────────────────────────────────
        // fetchRecentCleaned/Analyses/Tasks all cap at 100 rows — so .count
        // stays constant once you have 100+ records.  Watch .first?.id instead:
        // each refresh puts the newest record at index 0, so a new ID means a
        // genuinely new item arrived regardless of how large the backlog is.

        // Stage 1: new cleaned transcript → dequeue agent, then advance to Analysis
        .onChange(of: appState.cleanedTranscripts.first?.id) { id in
            guard let id, id != bridge.lastCleanedID else { return }
            bridge.lastCleanedID = id
            Log.info(.ui, "PixelWorld: new cleaned transcript \(id) → assignNextAgent")
            bridge.coordinator.sendEvent(.transcript)
            // Diagnostic: read back agent queue state 200ms after assign
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                bridge.coordinator.webView?.evaluateJavaScript(
                    "window._dbgDump ? window._dbgDump() : 'no_dbgDump'"
                ) { result, err in
                    Log.info(.ui, "PixelWorld dbgDump: \(result ?? err?.localizedDescription ?? "nil")")
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                bridge.coordinator.sendEvent(.cleaning(duration: 3.5))
            }
        }
        // Stage 2: new analysis → advance to Projects
        .onChange(of: appState.transcriptAnalyses.first?.id) { id in
            guard let id, id != bridge.lastAnalysisID else { return }
            bridge.lastAnalysisID = id
            Log.info(.ui, "PixelWorld: new analysis \(id) → advancePipeline to Projects")
            bridge.coordinator.sendEvent(.analysis(duration: 4.0))
        }
        // Stage 3: new task → advance to Claude Code  (seed sentTaskIDs on first run so
        // historical tasks don't re-fire; see .onAppear below)
        .onChange(of: appState.pipelineTasks.first?.id) { _ in
            let newTasks = appState.pipelineTasks.filter { !bridge.sentTaskIDs.contains($0.id) }
            for task in newTasks {
                bridge.sentTaskIDs.insert(task.id)
                Log.info(.ui, "PixelWorld: new task \(task.id) → advancePipeline to Code")
                bridge.coordinator.sendEvent(.taskCreated(title: task.title, mode: task.mode.rawValue))
                if task.mode == .auto {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        bridge.coordinator.sendEvent(.taskExecuting)
                    }
                }
            }
        }
        // Stage 4a: ask-mode task approved → Approval desk → Claude Code desk
        // Stage 4b: task completed → Claude Code desk → Archive
        .onChange(of: appState.pipelineTasks.map { $0.id + $0.status.rawValue }.joined()) { _ in
            // Track tasks that just entered pending_approval
            let newlyPending = appState.pipelineTasks.filter {
                bridge.sentTaskIDs.contains($0.id) &&
                $0.status == .pending_approval &&
                !bridge.pendingApprovalTaskIDs.contains($0.id)
            }
            for task in newlyPending {
                bridge.pendingApprovalTaskIDs.insert(task.id)
            }

            // Detect tasks that were pending_approval and have now been approved
            let justApproved = appState.pipelineTasks.filter {
                bridge.pendingApprovalTaskIDs.contains($0.id) &&
                $0.status != .pending_approval &&
                !bridge.completedTaskIDs.contains($0.id)
            }
            for task in justApproved {
                bridge.pendingApprovalTaskIDs.remove(task.id)
                Log.info(.ui, "PixelWorld: task \(task.id) approved → advancePipeline to Claude Code")
                bridge.coordinator.sendEvent(.taskApproved)
            }

            // Detect completed tasks → walk to Archive
            let justDone = appState.pipelineTasks.filter {
                bridge.sentTaskIDs.contains($0.id) && $0.status == .completed
                && !bridge.completedTaskIDs.contains($0.id)
            }
            for task in justDone {
                bridge.completedTaskIDs.insert(task.id)
                bridge.coordinator.sendEvent(.taskDone)
            }
        }
        .onChange(of: appState.locationName) { name in
            let safe = name.replacingOccurrences(of: "\"", with: "\\\"")
            bridge.coordinator.send("setLocation(\"\(safe)\")")
        }
        .onAppear {
            // Seed bridge with current state so historical records don't re-fire
            bridge.lastCleanedID  = appState.cleanedTranscripts.first?.id
            bridge.lastAnalysisID = appState.transcriptAnalyses.first?.id
            bridge.sentTaskIDs    = Set(appState.pipelineTasks.map { $0.id })
            bridge.completedTaskIDs = Set(appState.pipelineTasks
                .filter { $0.status == .completed }.map { $0.id })
            bridge.pendingApprovalTaskIDs = Set(appState.pipelineTasks
                .filter { $0.status == .pending_approval }.map { $0.id })
            // Send initial location once the web view is ready
            let name = appState.locationName
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let safe = name.replacingOccurrences(of: "\"", with: "\\\"")
                bridge.coordinator.send("setLocation(\"\(safe)\")")
            }
        }
    }

    // MARK: - Pending Approval Strip

    private func pendingApprovalStrip(tasks: [PipelineTaskRecord]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tasks) { task in
                    HStack(spacing: 8) {
                        // Task info
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.id)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(task.title)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.orange)
                                .lineLimit(2)
                                .frame(maxWidth: 180, alignment: .leading)
                        }

                        // Action buttons
                        HStack(spacing: 4) {
                            Button {
                                appState.acceptTask(id: task.id)
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 8, weight: .semibold))
                                    Text("Accept")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                .foregroundColor(.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.green.opacity(0.18)))
                            }
                            .buttonStyle(.plain)

                            Button {
                                appState.dismissTask(id: task.id)
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .semibold))
                                    Text("Dismiss")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                .foregroundColor(.red)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.red.opacity(0.15)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: 6) {
            // Spawn: adds an agent to the queue
            Button {
                bridge.coordinator.send("window.spawnQueueAgent && window.spawnQueueAgent()")
            } label: {
                Label("+Agent", systemImage: "person.badge.plus")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)

            // Assign: pulls front-of-queue agent and sends it to Comms desk
            Button {
                bridge.coordinator.send("window.assignNextAgent && window.assignNextAgent()")
            } label: {
                Label("Send", systemImage: "arrow.right.circle")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)

            // Advance: moves the in-flight agent to the next desk
            Button {
                bridge.coordinator.send("window.advancePipeline && window.advancePipeline('atComms','toAnalysis',1)")
            } label: {
                Label("Next", systemImage: "chevron.right.2")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)

            // Reset
            Button {
                bridge.coordinator.send("window.resetPipeline && window.resetPipeline()")
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - PixelWorldBridge  (ObservableObject for @StateObject lifecycle)

@MainActor
final class PixelWorldBridge: ObservableObject {
    let coordinator = PixelWorldCoordinator()
    // ID of the most-recently-seen first item in each capped fetch array.
    // Watching .first?.id fires even when count stays at the cap (100).
    var lastCleanedID:  String? = nil
    var lastAnalysisID: String? = nil
    var sentTaskIDs           = Set<String>()
    var completedTaskIDs      = Set<String>()
    var pendingApprovalTaskIDs = Set<String>()   // tasks waiting at Approval desk
}
