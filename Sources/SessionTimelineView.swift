import SwiftUI

struct SessionTimelineView: View {
    @State private var sessions: [SessionRecord] = []
    @State private var expandedID: String? = nil

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(sessions) { session in
                    SessionCard(
                        session: session,
                        isExpanded: expandedID == session.id,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                expandedID = expandedID == session.id ? nil : session.id
                            }
                        }
                    )
                }
            }
            .padding(16)
        }
        .onAppear { reload() }
    }

    private func reload() {
        sessions = SessionStore.shared.recentSessions(limit: 50)
    }
}

// MARK: - Session Card

struct SessionCard: View {
    let session: SessionRecord
    let isExpanded: Bool
    let onTap: () -> Void

    private var timeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM · h:mma"
        return f.string(from: session.startedAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.placeName ?? "Unknown location")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(AppTheme.green)

                    Text(timeLabel)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(AppTheme.textSecondary)
                }
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.white.opacity(0.3))
                    .font(.system(size: 10))
            }

            if !session.transcriptSnippet.isEmpty {
                Text(session.transcriptSnippet)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(isExpanded ? nil : 2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(AppTheme.green.opacity(0.15), lineWidth: 1)
                )
        )
        .onTapGesture { onTap() }
    }
}
