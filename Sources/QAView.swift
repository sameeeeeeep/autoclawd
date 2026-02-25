import AppKit
import SwiftUI

// MARK: - QAView

struct QAView: View {
    @ObservedObject var store: QAStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TabHeader("AI SEARCH") { EmptyView() }
            Divider()

            if store.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("Switch to AI Search mode and ask a question out loud")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(store.items) { item in
                    QAItemRow(item: item)
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - QAItemRow

struct QAItemRow: View {
    let item: QAItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.answer, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Text(item.question)
                .font(.custom("JetBrains Mono", size: 10))
                .foregroundStyle(.secondary)

            Text(item.answer)
                .font(.system(size: 12))
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
}
