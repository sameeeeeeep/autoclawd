import SwiftUI

// MARK: - People Intelligence View

struct PeopleIntelligenceView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedPersonID: UUID?

    private var selectedPerson: Person? {
        guard let id = selectedPersonID else { return nil }
        return appState.people.first { $0.id == id }
    }

    private func analyses(for person: Person) -> [TranscriptAnalysis] {
        let name = person.name.lowercased()
        return appState.transcriptAnalyses
            .filter { $0.personNames.map { $0.lowercased() }.contains(name) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private func tasks(for person: Person) -> [PipelineTaskRecord] {
        let analysisIDs = Set(analyses(for: person).map { $0.id })
        return appState.pipelineTasks.filter { analysisIDs.contains($0.analysisID) }
    }

    private func mentionCount(for person: Person) -> Int {
        analyses(for: person).count
    }

    var body: some View {
        HStack(spacing: 0) {

            // ── Left nav ─────────────────────────────────────────
            PPNavColumn(
                people: appState.people,
                mentionCounts: { p in mentionCount(for: p) },
                selectedID: $selectedPersonID
            )
            .frame(width: 160)

            Divider().opacity(0.06)

            // ── Center + right ────────────────────────────────────
            if let person = selectedPerson {
                let personAnalyses = analyses(for: person)
                let personTasks    = tasks(for: person)

                PPPersonCard(
                    person: person,
                    analyses: personAnalyses,
                    tasks: personTasks
                )
                .frame(width: 320)

                Divider().opacity(0.06)

                IntelligenceTaskFeed(
                    header: "TASKS INVOLVING \(person.name.uppercased())",
                    tasks: personTasks,
                    appState: appState
                )
            } else {
                IntelligenceEmptyHint(icon: "person.2", text: "Select a person")
            }
        }
        .onAppear {
            if selectedPersonID == nil {
                selectedPersonID = appState.people.first(where: { !$0.isMe })?.id
                    ?? appState.people.first?.id
            }
        }
    }
}

// MARK: - Nav Column

private struct PPNavColumn: View {
    let people: [Person]
    let mentionCounts: (Person) -> Int
    @Binding var selectedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PEOPLE")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.5)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 10)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 1) {
                    ForEach(people.filter { !$0.isMe && !$0.isMusic }) { person in
                        PPNavRow(
                            person: person,
                            mentionCount: mentionCounts(person),
                            isSelected: selectedID == person.id
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.14)) {
                                selectedID = person.id
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
            }
        }
        .background(.thickMaterial)
    }
}

private struct PPNavRow: View {
    let person: Person
    let mentionCount: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            PPPersonAvatar(name: person.name, color: person.color, size: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(person.name)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)

                if mentionCount > 0 {
                    Text("\(mentionCount) mentions")
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                }
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            isSelected ? Color.primary.opacity(0.07) : .clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .contentShape(Rectangle())
    }

}

// MARK: - Person Card

private struct PPPersonCard: View {
    let person: Person
    let analyses: [TranscriptAnalysis]
    let tasks: [PipelineTaskRecord]

    @State private var insight: String = ""
    @State private var insightLoading: Bool = false

    private var recentAnalyses: [TranscriptAnalysis] {
        analyses.prefix(4).map { $0 }
    }

    private var allTags: [String] {
        let tagSets = analyses.flatMap { $0.tags }
        let counts = Dictionary(tagSets.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.sorted { $0.value > $1.value }.prefix(4).map { $0.key }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {

                // ── Header ────────────────────────────────────────
                VStack(alignment: .leading, spacing: 14) {
                    PPPersonAvatar(name: person.name, color: person.color, size: 52)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(person.name)
                            .font(.system(size: 18, weight: .semibold))

                        if !allTags.isEmpty {
                            Text(allTags.joined(separator: " · "))
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    HStack(spacing: 16) {
                        IntelligenceStat(value: analyses.count, label: "mentions")
                        IntelligenceStat(value: tasks.count, label: "tasks")
                    }

                    if !allTags.isEmpty {
                        IntelligenceTagRow(tags: allTags)
                    }
                }
                .padding(24)

                // ── AI Insight ────────────────────────────────────
                if insightLoading || !insight.isEmpty {
                    IntelligenceDivider()
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Insight", systemImage: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.purple)

                        if insightLoading {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .tint(.purple)
                                Text("Thinking…")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.quaternary)
                            }
                        } else {
                            Text(insight)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(24)
                }

                // ── Activity Timeline ─────────────────────────────
                if !recentAnalyses.isEmpty {
                    IntelligenceDivider()
                    VStack(alignment: .leading, spacing: 0) {
                        IntelligenceSectionLabel("ACTIVITY")
                            .padding(.bottom, 14)

                        ForEach(Array(recentAnalyses.enumerated()), id: \.element.id) { idx, a in
                            PPTimelineEntry(
                                analysis: a,
                                isLast: idx == recentAnalyses.count - 1
                            )
                        }
                    }
                    .padding(24)
                }

                Spacer(minLength: 32)
            }
        }
        .background(.regularMaterial)
        .task(id: person.id) {
            await loadInsight()
        }
        .onChange(of: analyses.count) { _ in
            Task { await loadInsight() }
        }
    }

    // MARK: - Insight Loading

    @MainActor
    private func loadInsight() async {
        guard !analyses.isEmpty else { insight = ""; return }
        insightLoading = insight.isEmpty   // only show spinner on first load
        let result = await PersonInsightService.shared.insight(
            personID: person.id.uuidString,
            personName: person.name,
            analyses: analyses
        )
        insight = result
        insightLoading = false
    }
}

// MARK: - Timeline Entry

private struct PPTimelineEntry: View {
    let analysis: TranscriptAnalysis
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {

            // Rail
            VStack(spacing: 0) {
                Circle()
                    .fill(.purple.opacity(0.5))
                    .frame(width: 7, height: 7)
                    .padding(.top, 4)

                if !isLast {
                    Rectangle()
                        .fill(.primary.opacity(0.06))
                        .frame(width: 1)
                        .frame(minHeight: 32)
                }
            }
            .frame(width: 20, alignment: .top)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(analysis.timestamp, style: .relative)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                if !analysis.summary.isEmpty {
                    Text(analysis.summary)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .lineSpacing(2)
                }

                // Tags as chips
                if !analysis.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(analysis.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 10))
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.purple.opacity(0.1), in: Capsule())
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.leading, 10)
            .padding(.bottom, isLast ? 0 : 18)
        }
    }
}

// MARK: - Person Avatar

struct PPPersonAvatar: View {
    let name: String
    let color: Color
    let size: CGFloat

    private var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}
