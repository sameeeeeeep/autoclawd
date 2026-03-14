import SwiftUI
import AppKit

/// Capability suggestion toast — shown in top-right corner when `AppState.detectedSuggestion` is set.
struct CapabilityToastView: View {
    let item: SuggestionItem
    let onTap: () -> Void
    let onSnooze: () -> Void
    let onMarkIrrelevant: () -> Void
    var onQuestionOption: (String) -> Void = { _ in }

    var body: some View {
        switch item {
        case .capability(let match):
            capabilityBody(match: match)
        case .task(let task):
            taskBody(task: task)
        case .question(let question):
            questionBody(question: question)
        }
    }

    // MARK: Capability rendering

    private func capabilityBody(match: SuggestionMatch) -> some View {
        let capability = match.capability
        // Filter blank subWorkflows before rendering
        let steps = capability.subWorkflows.filter { !$0.name.isEmpty }
        let stepCount = steps.isEmpty ? 1 : steps.count

        return VStack(alignment: .leading, spacing: 8) {
            // ── Top row: icon strip + X ──
            HStack(alignment: .center, spacing: 0) {
                ToolIconStrip(triggers: capability.triggers, subWorkflows: steps)
                Spacer()
                Button(action: onSnooze) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Glass.textTertiary)
                }
                .buttonStyle(.plain)
            }

            // ── Headline ──
            Text(match.contextualHeadline)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Glass.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            // ── Subtitle + action row ──
            HStack(alignment: .center) {
                Text("AutoClawd can automate this · \(stepCount) step\(stepCount == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(Glass.textSecondary)
                    .lineLimit(1)

                Spacer()

                GlassButton("Run now", action: onTap)

                Button(action: onMarkIrrelevant) {
                    Image(systemName: "hand.thumbsdown")
                        .font(.system(size: 12))
                        .foregroundStyle(Glass.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 300)
        .background(glassBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }

    // MARK: Task rendering

    private func taskBody(task: TaskSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Intent chip
                Label(task.intent, systemImage: "bolt.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.blue.opacity(0.18))
                    .clipShape(Capsule())
                    .foregroundStyle(Color.blue)
                Spacer()
                Button(action: onSnooze) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Glass.textTertiary)
                }
                .buttonStyle(.plain)
            }
            Text(task.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Glass.textPrimary)
                .lineLimit(2)
            // Context chips
            if task.detectedContext.isComplete {
                contextChips(task.detectedContext)
            }
            HStack(spacing: 8) {
                GlassButton("Run", action: onTap)
                if !task.detectedContext.isComplete {
                    Button("Add context →") { onTap() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(Glass.textSecondary)
                }
                Spacer()
                Button(action: onMarkIrrelevant) {
                    Image(systemName: "hand.thumbsdown")
                        .font(.system(size: 12))
                        .foregroundStyle(Glass.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 300)
        .background(glassBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }

    // MARK: Question rendering

    private func questionBody(question: SuggestionQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("AutoClawd noticed", systemImage: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.purple.opacity(0.18))
                    .clipShape(Capsule())
                    .foregroundStyle(Color.purple)
                Spacer()
                Button(action: onSnooze) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Glass.textTertiary)
                }
                .buttonStyle(.plain)
            }

            Text(question.question)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Glass.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 4) {
                ForEach(question.options, id: \.self) { option in
                    Button {
                        onQuestionOption(option)
                    } label: {
                        Text(option)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(option.lowercased() == "not relevant" ? Glass.textTertiary : Glass.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Color.white.opacity(option.lowercased() == "not relevant" ? 0.04 : 0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 300)
        .background(glassBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.purple.opacity(0.25), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }

    @ViewBuilder
    private func contextChips(_ context: TaskContext) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(context.files, id: \.self) { f in
                    GlassChip(f, icon: "paperclip")
                }
                ForEach(context.contacts, id: \.self) { c in
                    GlassChip(c, icon: "person.fill")
                }
                ForEach(context.urls.prefix(2), id: \.self) { u in
                    GlassChip(URL(string: u)?.host ?? u, icon: "link")
                }
            }
        }
    }

    @ViewBuilder
    private var glassBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
            LinearGradient(colors: [Color.white.opacity(0.10), Color.clear],
                           startPoint: .top, endPoint: .center)
        }
    }
}

/// Horizontal strip of small app icons derived from a capability's trigger apps and subworkflows.
private struct ToolIconStrip: View {
    let triggers: CapabilityTriggers
    let subWorkflows: [SubWorkflow]
    private let maxIcons = 4
    private let iconSize: CGFloat = 28
    private let overlap: CGFloat = 8

    private var appNames: [String] {
        var names: [String] = []
        names.append(contentsOf: triggers.apps)
        for sw in subWorkflows {
            if let inv = sw.invocation {
                let lower = inv.lowercased()
                if lower.contains("slack") { names.append("Slack") }
                else if lower.contains("sheets") || lower.contains("google") { names.append("Numbers") }
                else if lower.contains("github") { names.append("Xcode") }
            }
        }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    private var displayNames: [String] { Array(appNames.prefix(maxIcons)) }
    private var extraCount: Int { max(0, appNames.count - maxIcons) }

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                ForEach(Array(displayNames.enumerated()), id: \.offset) { index, name in
                    AppIconView(appName: name, size: iconSize)
                        .offset(x: CGFloat(index) * (iconSize - overlap))
                }
                if extraCount > 0 {
                    Text("+\(extraCount)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Glass.textSecondary)
                        .frame(width: iconSize, height: iconSize)
                        .background(Circle().fill(Color.white.opacity(0.15)))
                        .offset(x: CGFloat(displayNames.count) * (iconSize - overlap))
                }
            }
            .frame(
                width: CGFloat(min(appNames.count, maxIcons + (extraCount > 0 ? 1 : 0))) * (iconSize - overlap) + overlap,
                height: iconSize
            )
        }
    }
}

/// Single app icon circle — uses NSWorkspace app icon with SF Symbol fallback.
struct AppIconView: View {
    let appName: String
    let size: CGFloat

    var body: some View {
        Group {
            if let nsImage = appIcon(for: appName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(Glass.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
    }

    private func appIcon(for name: String) -> NSImage? {
        let workspace = NSWorkspace.shared
        let bid = bundleID(for: name)
        let url: URL?
        if !bid.isEmpty {
            if let appURL = workspace.urlForApplication(withBundleIdentifier: bid) {
                url = appURL
            } else {
                url = findAppURL(name: name)
            }
        } else {
            url = findAppURL(name: name)
        }
        guard let appURL = url else { return nil }
        let icon = workspace.icon(forFile: appURL.path).copy() as? NSImage
        icon?.size = NSSize(width: size * 2, height: size * 2)
        return icon
    }

    private func bundleID(for name: String) -> String {
        switch name.lowercased() {
        case "xcode":    return "com.apple.dt.Xcode"
        case "vs code":  return "com.microsoft.VSCode"
        case "cursor":   return "com.todesktop.230313mzl4w4u92"
        case "figma":    return "com.figma.Desktop"
        case "canva":    return "com.canva.DesktopApp"
        case "linear":   return "com.linear"
        case "notion":   return "notion.id"
        case "slack":    return "com.tinyspeck.slackmacgap"
        case "threads":  return "com.burbn.instagram.Threads"
        case "twitter":  return "com.twitter.twitter-mac"
        case "numbers":  return "com.apple.iWork.Numbers"
        case "excel":    return "com.microsoft.Excel"
        default:         return ""
        }
    }

    private func findAppURL(name: String) -> URL? {
        let paths = ["/Applications", "/System/Applications", "/Applications/Utilities"]
        for path in paths {
            let url = URL(fileURLWithPath: path).appendingPathComponent("\(name).app")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}

/// Legacy log entry toast — kept for pipeline log display on the pill.
struct ToastView: View {
    let entry: LogEntry

    var body: some View {
        HStack(spacing: 6) {
            Text(badge)
                .font(AppTheme.caption)
                .foregroundColor(badgeColor)

            Text(entry.message)
                .font(AppTheme.caption)
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Text("[\(entry.component.rawValue)]")
                .font(AppTheme.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(height: 40)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(colors: [Color.white.opacity(0.10), Color.clear],
                               startPoint: .top, endPoint: .center)
            }
        )
        .overlay(
            Rectangle()
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    private var badge: String {
        switch entry.level {
        case .warn, .error: return "[!]"
        default:            return "[●]"
        }
    }

    private var badgeColor: Color {
        switch entry.level {
        case .warn, .error: return .red
        default:            return Color.green
        }
    }
}
