import SwiftUI
import AppKit

// MARK: - IntelligenceView

struct IntelligenceView: View {
    @ObservedObject var appState: AppState
    @State private var expandedChunk: Int? = nil  // auto-expand most recent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack {
                Text("Intelligence")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(appState.pendingExtractionCount == 0
                     ? "No pending items"
                     : "\(appState.pendingExtractionCount) pending synthesis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Auto", selection: $appState.synthesizeThreshold) {
                    Text("Manual").tag(0)
                    Text("Auto: 5").tag(5)
                    Text("Auto: 10").tag(10)
                    Text("Auto: 20").tag(20)
                }
                .pickerStyle(.menu)
                .frame(width: 100)
                Button("Synthesize Now") {
                    Task { await appState.synthesizeNow() }
                }
                .disabled(appState.pendingExtractionCount == 0)
                .buttonStyle(.bordered)
                Button("Clean Up") {
                    Task { await appState.cleanupNow() }
                }
                .disabled(appState.isCleaningUp)
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Grouped list by chunkIndex, sorted descending
            let grouped = Dictionary(grouping: appState.extractionItems, by: \.chunkIndex)
            let sortedChunks = grouped.keys.sorted(by: >)

            if sortedChunks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "brain")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No extraction items yet")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(sortedChunks, id: \.self) { chunkIdx in
                    let items = grouped[chunkIdx] ?? []
                    ChunkGroupView(
                        chunkIndex: chunkIdx,
                        items: items,
                        isExpanded: expandedChunk == chunkIdx,
                        onToggle: {
                            expandedChunk = expandedChunk == chunkIdx ? nil : chunkIdx
                        },
                        onToggleItem: { appState.toggleExtraction(id: $0) },
                        onSetBucket: { appState.setExtractionBucket(id: $0, bucket: $1) }
                    )
                }
                .listStyle(.plain)
            }
        }
        .onAppear {
            appState.refreshExtractionItems()
            // Auto-expand most recent chunk
            let grouped = Dictionary(grouping: appState.extractionItems, by: \.chunkIndex)
            expandedChunk = grouped.keys.max()
        }
    }
}

// MARK: - ChunkGroupView

struct ChunkGroupView: View {
    let chunkIndex: Int
    let items: [ExtractionItem]
    let isExpanded: Bool
    let onToggle: () -> Void
    let onToggleItem: (String) -> Void
    let onSetBucket: (String, ExtractionBucket) -> Void

    private var acceptedCount: Int { items.filter(\.isAccepted).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Chunk \(chunkIndex)")
                        .font(.custom("JetBrains Mono", size: 11).weight(.medium))
                    if let first = items.first {
                        Text(first.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("\"\(String(first.sourcePhrase.prefix(40)))\"")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("\(acceptedCount)/\(items.count) accepted")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 6)

            if isExpanded {
                ForEach(items) { item in
                    ExtractionItemRow(
                        item: item,
                        onToggle: { onToggleItem(item.id) },
                        onSetBucket: { onSetBucket(item.id, $0) }
                    )
                    .padding(.leading, 16)
                }
            }
        }
    }
}

// MARK: - ExtractionItemRow

struct ExtractionItemRow: View {
    let item: ExtractionItem
    let onToggle: () -> Void
    let onSetBucket: (ExtractionBucket) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Toggle button
            Button(action: onToggle) {
                Image(systemName: item.isAccepted ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundColor(item.isAccepted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    // Bucket capsule with color + picker
                    Menu {
                        ForEach(ExtractionBucket.allCases, id: \.self) { bucket in
                            Button(bucket.displayName) { onSetBucket(bucket) }
                        }
                    } label: {
                        Text(item.bucket.displayName)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(bucketColor(item.bucket).opacity(0.2))
                            .foregroundColor(bucketColor(item.bucket))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    // Type + priority badge
                    Text(item.type == .todo ? "todo\(item.priorityLabel)" : "fact")
                        .font(.custom("JetBrains Mono", size: 9))
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Synced indicator
                    if item.applied {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                // Content text
                Text(item.content)
                    .font(.system(size: 12))
                    .foregroundStyle(item.applied ? .tertiary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private func bucketColor(_ bucket: ExtractionBucket) -> Color {
        switch bucket {
        case .projects:    return .blue
        case .people:      return .purple
        case .plans:       return .orange
        case .preferences: return .teal
        case .decisions:   return .green
        case .other:       return .secondary
        }
    }
}
