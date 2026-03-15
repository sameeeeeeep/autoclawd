// Sources/CanvasWorkspaceView.swift
import SwiftUI

/// AI Canvas panel tab — shown when PanelTab.canvas is active.
///
/// Three modes:
///   • Question active  → QuestionWorkspaceView (full-screen question + voice hint)
///   • History exists   → SuggestionHistoryView (review past suggestions, re-run or dismiss)
///   • Nothing yet      → AICanvasView (FUCBC event canvas + capabilities)
struct CanvasWorkspaceView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Group {
            if let question = appState.activeQuestion {
                QuestionWorkspaceView(question: question, appState: appState)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal:   .opacity
                    ))
            } else if !appState.suggestionHistory.isEmpty {
                SuggestionHistoryView(appState: appState)
                    .transition(.opacity)
            } else {
                AICanvasView(learnService: appState.learnModeService)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.activeQuestion?.id)
        .animation(.easeInOut(duration: 0.2), value: appState.suggestionHistory.count)
    }
}

// MARK: - SuggestionHistoryView

/// Scrollable list of the last 20 suggestions — shown in the Canvas tab idle state.
/// Each entry shows what triggered it, what was suggested, and buttons to re-run or dismiss.
private struct SuggestionHistoryView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ZStack {
            AppTheme.glassAmbientBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Suggestion History")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Glass.textPrimary)
                        Text("\(appState.suggestionHistory.count) suggestions this session")
                            .font(.system(size: 11))
                            .foregroundStyle(Glass.textSecondary)
                    }
                    Spacer()
                    Button("Clear") {
                        appState.suggestionHistory.removeAll()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Glass.textTertiary)
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
                .background(Color.black.opacity(0.2))

                GlassDivider()

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(appState.suggestionHistory) { entry in
                            SuggestionHistoryRow(entry: entry, appState: appState)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
        }
    }
}

// MARK: - SuggestionHistoryRow

private struct SuggestionHistoryRow: View {
    let entry: SuggestionHistoryEntry
    @ObservedObject var appState: AppState
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Type icon
            Image(systemName: typeIcon)
                .font(.system(size: 13))
                .foregroundStyle(typeColor)
                .frame(width: 24, height: 24)
                .background(typeColor.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Glass.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(entry.typeLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(typeColor)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(typeColor.opacity(0.1))
                        .clipShape(Capsule())
                    Text(timeAgo(entry.shownAt))
                        .font(.system(size: 10))
                        .foregroundStyle(Glass.textTertiary)
                }
            }

            Spacer()

            // Re-run button (only for tasks/capabilities)
            if canRerun {
                Button {
                    rerun()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(Glass.textSecondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.06) : Color.white.opacity(0.03))
        )
        .onHover { isHovered = $0 }
    }

    private var typeIcon: String {
        switch entry.item {
        case .capability: return "bolt.fill"
        case .task:       return "checkmark.circle.fill"
        case .question:   return "questionmark.circle.fill"
        }
    }

    private var typeColor: Color {
        switch entry.item {
        case .capability: return .orange
        case .task:       return .blue
        case .question:   return .purple
        }
    }

    private var canRerun: Bool {
        if case .question = entry.item { return false }
        return true
    }

    private func rerun() {
        switch entry.item {
        case .capability(let m): appState.executeCapability(m.capability)
        case .task(let t):       appState.executeSuggestedTask(t)
        case .question:          break
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let s = Int(-date.timeIntervalSinceNow)
        if s < 60  { return "just now" }
        if s < 3600 { return "\(s / 60)m ago" }
        return "\(s / 3600)h ago"
    }
}

// MARK: - QuestionWorkspaceView

/// Full question card for the Canvas tab — richer than the toast, shows live voice hint.
private struct QuestionWorkspaceView: View {
    let question: SuggestionQuestion
    @ObservedObject var appState: AppState

    var body: some View {
        ZStack {
            AppTheme.glassAmbientBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 8) {
                    Label("AutoClawd noticed", systemImage: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.purple)
                    Spacer()
                    Text(timeAgo(question.createdAt))
                        .font(.system(size: 10))
                        .foregroundStyle(Glass.textTertiary)
                    Button {
                        appState.dismissDetectedSuggestion()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Glass.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)

                // Question card
                LiquidGlassCard(tint: .purple) {
                    VStack(alignment: .leading, spacing: 16) {
                        // Question text
                        Text(question.question)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Glass.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        // Context chips
                        if let app = question.context.app {
                            HStack(spacing: 6) {
                                Image(systemName: "app.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Glass.textTertiary)
                                Text(app)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Glass.textSecondary)
                            }
                        }

                        GlassDivider()

                        // Option buttons
                        VStack(spacing: 8) {
                            ForEach(question.options, id: \.self) { option in
                                OptionButton(
                                    option: option,
                                    isRelevant: option.lowercased() != "not relevant"
                                ) {
                                    appState.handleSuggestionQuestionOption(option, question: question)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                .padding(.horizontal, 20)

                // Voice hint
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        if appState.isListening {
                            CanvasPulsingDot(color: .green)
                        }
                        Text(appState.isListening
                             ? "Or speak your answer — Claude is listening"
                             : "Mic off — tap an option above")
                            .font(.system(size: 12))
                            .foregroundStyle(Glass.textSecondary)
                    }

                    // Show live transcript tail while listening
                    if appState.isListening, !appState.liveTranscriptText.isEmpty {
                        let tail = appState.liveTranscriptText
                            .components(separatedBy: .whitespacesAndNewlines)
                            .filter { !$0.isEmpty }.suffix(8).joined(separator: " ")
                        Text("\"\(tail)\"")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Glass.textTertiary)
                            .italic()
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 16)

                Spacer()
            }
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let s = Int(-date.timeIntervalSinceNow)
        if s < 60 { return "just now" }
        return "\(s / 60)m ago"
    }
}

// MARK: - OptionButton

private struct OptionButton: View {
    let option: String
    let isRelevant: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                if isRelevant {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.blue.opacity(0.8))
                }
                Text(option)
                    .font(.system(size: 13, weight: isRelevant ? .medium : .regular))
                    .foregroundStyle(isRelevant ? Glass.textPrimary : Glass.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered
                          ? (isRelevant ? Color.blue.opacity(0.15) : Color.white.opacity(0.06))
                          : (isRelevant ? Color.white.opacity(0.08) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isRelevant ? Color.blue.opacity(0.2) : Color.white.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
