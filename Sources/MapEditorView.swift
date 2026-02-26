import SwiftUI

// MARK: - MapEditorView

struct MapEditorView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ────────────────────────────────────────────────
            HStack {
                Text("EDIT ROOM")
                    .font(BrutalistTheme.monoSM)
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().opacity(0.2)

            // ── Location name ─────────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                Text("LOCATION")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                TextField("Room name", text: $appState.locationName)
                    .font(BrutalistTheme.monoSM)
                    .textFieldStyle(.plain)
                    .padding(6)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().opacity(0.2)

            // ── People list ───────────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                Text("PEOPLE")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach($appState.people) { $person in
                            PersonRowView(person: $person, appState: appState)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .frame(maxHeight: 180)
            }

            Divider().opacity(0.2)

            // ── Add person ────────────────────────────────────────────
            HStack(spacing: 6) {
                TextField("Add person…", text: $newName)
                    .font(BrutalistTheme.monoSM)
                    .textFieldStyle(.plain)
                    .padding(6)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(6)
                    .onSubmit { addPerson() }
                Button(action: addPerson) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(BrutalistTheme.neonGreen)
                }
                .buttonStyle(.plain)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: 220)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    private func addPerson() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        appState.addPerson(name: trimmed)
        newName = ""
    }
}

// MARK: - PersonRowView

private struct PersonRowView: View {
    @Binding var person: Person
    @ObservedObject var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(person.color)
                .frame(width: 10, height: 10)

            TextField("Name", text: $person.name)
                .font(.system(size: 11, design: .monospaced))
                .textFieldStyle(.plain)

            Spacer()

            if !person.isMe && !person.isMusic {
                Button {
                    appState.people.removeAll { $0.id == person.id }
                    if appState.currentSpeakerID == person.id {
                        appState.currentSpeakerID = nil
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Color.white.opacity(0.04))
        .cornerRadius(5)
    }
}
