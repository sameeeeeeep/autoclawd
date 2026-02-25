import Foundation

final class UserProfileService: @unchecked Sendable {
    private let sessionStore = SessionStore.shared
    private var conversationTurns: [(role: String, content: String)] = []
    private let maxFollowUps = 3
    private var followUpCount = 0

    var apiKey: String = ""
    var baseURL: String = "https://api.groq.com/openai/v1"
    let model = "meta-llama/llama-4-scout-17b-16e-instruct"

    /// Start or reset the profile chat. Returns the opening question.
    func startChat() -> String {
        conversationTurns = []
        followUpCount = 0
        return "Tell me about yourself — what do you do, where do you work, and who do you work with most?"
    }

    /// Submit a user message. Returns the assistant reply and whether conversation is done.
    func submitMessage(_ message: String) async throws -> (reply: String, isDone: Bool) {
        conversationTurns.append((role: "user", content: message))

        if followUpCount >= maxFollowUps {
            let blob = try await synthesiseBlob()
            sessionStore.saveUserContextBlob(blob)
            return ("Got it — your context is saved.", true)
        }

        let reply = try await callLLM(followingUp: true)
        conversationTurns.append((role: "assistant", content: reply))
        followUpCount += 1
        return (reply, false)
    }

    // MARK: - Private

    private func callLLM(followingUp: Bool) async throws -> String {
        let systemPrompt = followingUp
            ? """
              You are building a compact personal context profile.
              Ask ONE short follow-up question to learn more about the user.
              Focus on role, workplace, projects, or frequent collaborators.
              Keep question under 15 words.
              """
            : """
              Summarise what you know about the user in a compact paragraph (max 200 words).
              """

        var messages: [[String: String]] = [["role": "system", "content": systemPrompt]]
        messages += conversationTurns.map { ["role": $0.role, "content": $0.content] }
        return try await callGroq(messages: messages)
    }

    private func synthesiseBlob() async throws -> String {
        let conversation = conversationTurns
            .map { "\($0.role): \($0.content)" }
            .joined(separator: "\n")

        let systemPrompt = """
            Synthesise the following conversation into a compact personal context profile (max 300 words).
            Write in third-person present tense. Include: name, role, workplace, key collaborators, current projects.
            """
        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": conversation]
        ]
        return try await callGroq(messages: messages)
    }

    private func callGroq(messages: [[String: String]]) async throws -> String {
        var request = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["model": model, "messages": messages, "max_tokens": 400]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let content = msg["content"] as? String
        else { throw URLError(.badServerResponse) }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
