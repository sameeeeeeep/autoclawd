import SwiftUI

// MARK: - SetupView

struct SetupView: View {
    @StateObject private var installer = DependencyInstaller.shared
    @State private var groqInput        = ""
    @State private var groqValidating   = false
    @State private var groqError: String? = nil
    var onComplete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ollamaRow
                    rowDivider
                    modelRow
                    rowDivider
                    groqRow
                    rowDivider
                    accessibilityRow
                }
                .padding(.bottom, 8)
            }
            if installer.isComplete { completeFooter }
        }
        .frame(width: 540, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await installer.checkAll() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("AUTOCLAWD SETUP")
                    .font(AppTheme.heading)
                    .foregroundColor(.primary)
                Spacer()
                if installer.isComplete {
                    Button("Skip →") { onComplete?() }
                        .buttonStyle(.plain)
                        .font(AppTheme.caption)
                        .foregroundColor(.secondary)
                }
            }
            Text("AutoClawd needs a few things installed to work. We'll handle it for you.")
                .font(AppTheme.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Ollama Row

    private var ollamaRow: some View {
        SetupRow(
            icon: "cpu",
            title: "OLLAMA",
            subtitle: "Local AI runtime — runs the intelligence features on your Mac",
            status: installer.ollamaStatus
        ) {
            actionButton(
                label: "Install",
                status: installer.ollamaStatus,
                runningLabel: "Installing…"
            ) {
                Task { await installer.installOllama() }
            }
        }
    }

    // MARK: - Model Row

    private var modelRow: some View {
        SetupRow(
            icon: "brain",
            title: "LLAMA 3.2 MODEL",
            subtitle: "~2 GB download • runs locally, nothing leaves your Mac",
            status: installer.modelStatus
        ) {
            VStack(alignment: .trailing, spacing: 6) {
                if case .running = installer.modelStatus, installer.modelProgress > 0 {
                    VStack(alignment: .leading, spacing: 3) {
                        ProgressView(value: installer.modelProgress)
                            .progressViewStyle(.linear)
                            .tint(Color.green)
                            .frame(width: 160)
                        Text(installer.modelProgressText)
                            .font(AppTheme.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    actionButton(
                        label: "Download",
                        status: installer.modelStatus,
                        runningLabel: "Downloading…"
                    ) {
                        Task { await installer.pullModel() }
                    }
                }
            }
        }
    }

    // MARK: - Groq Row

    private var groqRow: some View {
        SetupRow(
            icon: "bolt",
            title: "GROQ API KEY",
            subtitle: "Free key at console.groq.com — powers transcription",
            status: installer.groqStatus
        ) {
            if case .done = installer.groqStatus {
                statusBadge(.done)
            } else {
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        SecureField("gsk_...", text: $groqInput)
                            .textFieldStyle(.plain)
                            .font(.custom("JetBrains Mono", size: 11))
                            .frame(width: 160)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.07))
                            .cornerRadius(4)
                        Button(groqValidating ? "…" : "Validate") {
                            groqError = nil
                            groqValidating = true
                            Task {
                                _ = await installer.validateAndSaveGroqKey(groqInput)
                                groqValidating = false
                                if case .failed(let msg) = installer.groqStatus {
                                    groqError = msg
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .font(AppTheme.caption)
                        .foregroundColor(Color.green)
                        .disabled(groqInput.isEmpty || groqValidating)
                    }
                    if let err = groqError {
                        Text(err)
                            .font(AppTheme.caption)
                            .foregroundColor(.red.opacity(0.8))
                    }
                }
            }
        }
    }

    // MARK: - Accessibility Row

    private var accessibilityRow: some View {
        SetupRow(
            icon: "keyboard",
            title: "ACCESSIBILITY",
            subtitle: "Enables ⌃Space (flush chunk) and ⌃R (toggle mic) global hotkeys",
            status: installer.accessStatus
        ) {
            actionButton(
                label: "Grant",
                status: installer.accessStatus,
                runningLabel: "Waiting…"
            ) {
                installer.requestAccessibility()
            }
        }
    }

    // MARK: - Complete Footer

    private var completeFooter: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color.green)
                Text("All set — AutoClawd is ready to use.")
                    .font(AppTheme.body)
                    .foregroundColor(Color.green)
                Spacer()
                Button("Launch AutoClawd") { onComplete?() }
                    .buttonStyle(.plain)
                    .font(AppTheme.body)
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.green)
                    .cornerRadius(4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Helpers

    private var rowDivider: some View {
        Divider().opacity(0.25)
    }

    private func actionButton(
        label: String,
        status: StepStatus,
        runningLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Group {
            switch status {
            case .done:
                statusBadge(.done)
            case .running:
                HStack(spacing: 6) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                    Text(runningLabel)
                        .font(AppTheme.caption)
                        .foregroundColor(.secondary)
                }
            case .failed(let msg):
                VStack(alignment: .trailing, spacing: 4) {
                    Button("Retry") { action() }
                        .buttonStyle(.plain)
                        .font(AppTheme.caption)
                        .foregroundColor(.orange)
                    Text(msg)
                        .font(AppTheme.caption)
                        .foregroundColor(.red.opacity(0.7))
                        .lineLimit(2)
                        .frame(maxWidth: 180, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                }
            case .pending:
                Button(label) { action() }
                    .buttonStyle(.plain)
                    .font(AppTheme.caption)
                    .foregroundColor(Color.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.green.opacity(0.6), lineWidth: 1)
                    )
            }
        }
    }

    private func statusBadge(_ status: StepStatus) -> some View {
        Group {
            if case .done = status {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text("DONE")
                        .font(AppTheme.caption)
                }
                .foregroundColor(Color.green)
            }
        }
    }
}

// MARK: - SetupRow

private struct SetupRow<Trailing: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let status: StepStatus
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Step indicator
            ZStack {
                Circle()
                    .fill(circleColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(circleColor)
            }
            .padding(.top, 2)

            // Title + subtitle
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppTheme.body)
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(AppTheme.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            trailing()
                .frame(minWidth: 80, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var circleColor: Color {
        switch status {
        case .done:    return Color.green
        case .running: return .yellow
        case .failed:  return .red
        case .pending: return .white.opacity(0.3)
        }
    }
}

// MARK: - SetupWindow

final class SetupWindow: NSWindow {
    init(onComplete: @escaping () -> Void) {
        super.init(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = "AutoClawd Setup"
        isReleasedWhenClosed = false

        let view = SetupView(onComplete: onComplete)
        contentViewController = NSHostingController(rootView: view)
        center()
    }
}
