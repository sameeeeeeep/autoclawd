import SwiftUI

struct UserProfileChatView: View {
    @EnvironmentObject var appState: AppState

    @State private var messages: [(role: String, text: String)] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var isDone = false
    private let service = UserProfileService()

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { idx, msg in
                            ChatBubble(role: msg.role, text: msg.text)
                                .id(idx)
                        }
                        if isLoading {
                            ChatBubble(role: "assistant", text: "…")
                                .id(-1)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: messages.count) { _ in
                    proxy.scrollTo(messages.count - 1)
                }
            }

            Divider()

            HStack {
                TextField("Type here…", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .disabled(isLoading || isDone)
                    .onSubmit { sendMessage() }

                Button(isDone ? "Done" : "Send") { sendMessage() }
                    .buttonStyle(.plain)
                    .foregroundColor(AppTheme.green)
                    .disabled(inputText.isEmpty || isLoading)
            }
            .padding(10)
        }
        .onAppear { startChat() }
    }

    private func startChat() {
        service.apiKey = appState.groqAPIKey
        let opening = service.startChat()
        messages = [(role: "assistant", text: opening)]
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        messages.append((role: "user", text: text))
        inputText = ""
        isLoading = true
        Task {
            do {
                let (reply, done) = try await service.submitMessage(text)
                await MainActor.run {
                    messages.append((role: "assistant", text: reply))
                    isLoading = false
                    isDone = done
                }
            } catch {
                await MainActor.run {
                    messages.append((role: "assistant", text: "Error: \(error.localizedDescription)"))
                    isLoading = false
                }
            }
        }
    }
}

struct ChatBubble: View {
    let role: String
    let text: String

    var body: some View {
        HStack {
            if role == "user" { Spacer() }
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .padding(8)
                .background(role == "user"
                    ? AppTheme.green.opacity(0.15)
                    : Color.white.opacity(0.05))
                .cornerRadius(6)
                .foregroundColor(.white.opacity(0.9))
            if role == "assistant" { Spacer() }
        }
    }
}
