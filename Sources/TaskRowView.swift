import SwiftUI

// MARK: - TaskRowView

/// Compact list row for the Tasks panel.
struct TaskRowView: View {

    let record: TaskRecord
    let isRunning: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {

                // Emoji badge
                Text(record.emoji)
                    .font(.system(size: 22))
                    .frame(width: 36, height: 36)
                    .background(Glass.backgroundDark)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                // Title + meta
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Glass.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let proj = record.projectName {
                            HStack(spacing: 3) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 9))
                                Text(proj)
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(Glass.textTertiary)
                        }

                        if let nextFire = record.nextFireDate {
                            HStack(spacing: 3) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 9))
                                Text(nextFireLabel(nextFire))
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(Color.purple.opacity(0.7))
                        } else if record.status == .building {
                            Text(record.description)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.cyan.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                // Recurring icon
                if record.isRecurring {
                    Image(systemName: "repeat")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.purple.opacity(0.6))
                }

                // Status dot
                statusDot(record.status)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isRunning ? Color.cyan.opacity(0.06) : Color.clear)
        )
    }

    // MARK: - Status Dot

    private func statusDot(_ status: TaskRecordStatus) -> some View {
        let (color, animated): (Color, Bool) = {
            switch status {
            case .idle:           return (Glass.textTertiary, false)
            case .running:        return (Color.orange, true)
            case .completed:      return (Color.green, false)
            case .failed:         return (Color.red, false)
            case .needsInput:     return (Color.purple, true)
            case .pendingApproval:return (Color.orange, true)
            case .building:       return (Color.cyan, true)
            }
        }()

        return Group {
            if animated {
                CanvasPulsingDot(color: color)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
            }
        }
    }

    // MARK: - Next Fire Label

    private func nextFireLabel(_ date: Date) -> String {
        let diff = date.timeIntervalSinceNow
        if diff < 60 { return "soon" }
        if diff < 3600 { return "in \(Int(diff / 60))m" }
        if diff < 86400 { return "in \(Int(diff / 3600))h" }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE HH:mm"
        return fmt.string(from: date)
    }
}
