import SwiftUI

// MARK: - Code Widget (Container)

struct CodeWidgetView: View {
    @ObservedObject var appState: AppState

    private let widgetWidth: CGFloat = 220

    var body: some View {
        ZStack(alignment: .top) {
            WidgetGlassBackground(isActive: appState.codeIsStreaming)

            switch appState.codeWidgetStep {
            case .projectSelect:
                CodeProjectSelectView(appState: appState)
            case .copilot:
                CodeCopilotView(appState: appState)
            }
        }
        .frame(width: widgetWidth)
        .animation(.easeInOut(duration: 0.22), value: appState.codeWidgetStep)
    }
}

// MARK: - Step 1: Project + Permissions Select

struct CodeProjectSelectView: View {
    @ObservedObject var appState: AppState

    private let widgetWidth: CGFloat = 220
    private let widgetHeight: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 5) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.accentColor)

                Text("CODE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentColor.opacity(0.8))

                Spacer()
            }

            if appState.projects.isEmpty {
                VStack(spacing: 4) {
                    Spacer()
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 16, weight: .thin))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("No projects")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("Add projects in the panel")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.3))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                // Project picker
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)

                    Picker("", selection: $appState.codeSelectedProject) {
                        Text("Select project…")
                            .tag(nil as Project?)
                        ForEach(appState.projects, id: \.id) { project in
                            Text(project.name)
                                .tag(project as Project?)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .font(.system(size: 10, design: .monospaced))
                    .frame(maxWidth: .infinity)
                }

                // Permissions toggle + start
                HStack(spacing: 6) {
                    Button(action: { appState.codeSkipPermissions.toggle() }) {
                        HStack(spacing: 3) {
                            Image(systemName: appState.codeSkipPermissions ? "lock.open" : "lock")
                                .font(.system(size: 8, weight: .medium))
                            Text(appState.codeSkipPermissions ? "Auto" : "Ask")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(appState.codeSkipPermissions ? .orange : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(appState.codeSkipPermissions
                                      ? Color.orange.opacity(0.12)
                                      : Color.secondary.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(action: { appState.startCodeSession() }) {
                        HStack(spacing: 3) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8))
                            Text("Start")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(appState.codeSelectedProject != nil ? Color.accentColor : Color.secondary.opacity(0.3))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.codeSelectedProject == nil)
                }
            }
        }
        .padding(12)
        .frame(width: widgetWidth, height: widgetHeight)
    }
}

// MARK: - Step 2: Co-pilot (voice-driven, no text input)

struct CodeCopilotView: View {
    @ObservedObject var appState: AppState

    private let widgetWidth: CGFloat = 220
    private let widgetHeight: CGFloat = 260

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 5) {
                Button(action: { appState.resetCodeWidget() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.accentColor)

                Text(appState.codeSelectedProject?.name.uppercased().prefix(12) ?? "CODE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentColor.opacity(0.8))
                    .lineLimit(1)

                Spacer()

                if appState.codeIsStreaming {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                        .modifier(PulsingDot())
                }

                if appState.isListening {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.green.opacity(0.7))
                }

                if appState.codeSession?.isRunning == true {
                    Button(action: { appState.stopCodeSession() }) {
                        Image(systemName: "stop.circle")
                            .font(.system(size: 11))
                            .foregroundColor(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Session thread
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(appState.codeSessionMessages) { msg in
                            CodeMessageRow(message: msg)
                                .id(msg.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
                .onChange(of: appState.codeSessionMessages.count) { _ in
                    if let last = appState.codeSessionMessages.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Tool use indicator
            if let toolName = appState.codeCurrentToolName {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(toolName)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.orange)
                        .lineLimit(1)
                }
                .transition(.opacity)
            }
        }
        .padding(12)
        .frame(width: widgetWidth, height: widgetHeight)
    }
}

// MARK: - Message Row

struct CodeMessageRow: View {
    let message: CodeMessage

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            roleIndicator
            Text(message.text)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(textColor)
                .lineSpacing(1.5)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var roleIndicator: some View {
        switch message.role {
        case .user:
            Image(systemName: "mic.fill")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.green)
        case .assistant:
            Text("A")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.accentColor)
        case .tool:
            Image(systemName: "wrench")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.orange)
        case .status:
            Image(systemName: "info.circle")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.secondary)
        case .error:
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.red)
        }
    }

    private var textColor: Color {
        switch message.role {
        case .user:      return .primary
        case .assistant: return .primary
        case .tool:      return .secondary
        case .status:    return .secondary.opacity(0.7)
        case .error:     return .red.opacity(0.8)
        }
    }
}
