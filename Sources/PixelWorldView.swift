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
    case taskExecuting
    case taskDone
    case whatsapp
    case reset

    var jsCall: String {
        switch self {
        case .transcript:
            return "receiveEvent('transcript',{})"
        case .cleaning(let d):
            return "receiveEvent('cleaning',{duration:\(Int(d * 1000))})"
        case .analysis(let d):
            return "receiveEvent('analysis',{duration:\(Int(d * 1000))})"
        case .taskCreated(let title, let mode):
            let safe = title.replacingOccurrences(of: "'", with: "\\'").prefix(40)
            return "receiveEvent('task_created',{title:'\(safe)',mode:'\(mode)'})"
        case .taskExecuting:
            return "receiveEvent('task_executing',{})"
        case .taskDone:
            return "receiveEvent('task_done',{})"
        case .whatsapp:
            return "receiveEvent('whatsapp',{})"
        case .reset:
            return "receiveEvent('reset',{})"
        }
    }
}

// MARK: - PixelWorldCoordinator

/// Bridges JS → Swift messages and holds a weak WKWebView reference for event dispatch.
final class PixelWorldCoordinator: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        switch type {
        case "ready":
            Log.info(.ui, "PixelWorld: web app ready")
        default:
            Log.info(.ui, "PixelWorld: JS message '\(type)'")
        }
    }

    /// Evaluate arbitrary JS on the web view (main thread only).
    @MainActor
    func send(_ js: String) {
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    @MainActor
    func sendEvent(_ event: PixelWorldEvent) {
        send(event.jsCall)
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
        }
        // React to AppState pipeline changes
        .onReceive(appState.$cleanedTranscripts.dropFirst()) { transcripts in
            if transcripts.count > bridge.lastCleanedCount {
                bridge.lastCleanedCount = transcripts.count
                bridge.coordinator.sendEvent(.cleaning(duration: 3.5))
            }
        }
        .onReceive(appState.$transcriptAnalyses.dropFirst()) { analyses in
            if analyses.count > bridge.lastAnalysisCount {
                bridge.lastAnalysisCount = analyses.count
                bridge.coordinator.sendEvent(.analysis(duration: 4.0))
            }
        }
        .onReceive(appState.$pipelineTasks.dropFirst()) { tasks in
            let newTasks = tasks.filter { !bridge.sentTaskIDs.contains($0.id) }
            for task in newTasks {
                bridge.sentTaskIDs.insert(task.id)
                bridge.coordinator.sendEvent(.taskCreated(title: task.title, mode: task.mode.rawValue))
                if task.mode == .auto {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        bridge.coordinator.sendEvent(.taskExecuting)
                    }
                }
            }
            // Detect task completion
            let justDone = tasks.filter {
                bridge.sentTaskIDs.contains($0.id) && $0.status == .completed
                && !bridge.completedTaskIDs.contains($0.id)
            }
            for task in justDone {
                bridge.completedTaskIDs.insert(task.id)
                bridge.coordinator.sendEvent(.taskDone)
            }
        }
        .onReceive(appState.$latestTranscriptChunk.dropFirst()) { chunk in
            if !chunk.isEmpty {
                bridge.coordinator.sendEvent(.transcript)
            }
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: 6) {
            Button {
                bridge.coordinator.send("focusOn(dot)")
            } label: {
                Label("HQ", systemImage: "dot.circle")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)

            Button {
                bridge.coordinator.send("focusOn(clawd)")
            } label: {
                Label("Lab", systemImage: "terminal")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)

            Button {
                bridge.coordinator.send("focusOn(archivist)")
            } label: {
                Label("Archive", systemImage: "archivebox")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)

            Divider().frame(height: 16)

            // Demo event buttons (for testing without live pipeline)
            Button {
                bridge.coordinator.sendEvent(.transcript)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    bridge.coordinator.sendEvent(.cleaning(duration: 3))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    bridge.coordinator.sendEvent(.analysis(duration: 4))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
                    bridge.coordinator.sendEvent(.taskCreated(title: "Demo task", mode: "auto"))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
                    bridge.coordinator.sendEvent(.taskDone)
                }
            } label: {
                Label("Demo", systemImage: "play.circle")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
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
    var lastCleanedCount = 0
    var lastAnalysisCount = 0
    var sentTaskIDs     = Set<String>()
    var completedTaskIDs = Set<String>()
}
