import Foundation

final class PeopleTaggingService: @unchecked Sendable {
    private let store = SessionStore.shared
    var apiKey: String = ""
    var baseURL: String = "https://api.groq.com/openai/v1"

    func tagPeople(sessionID: String, transcript: String) async {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let prompt = """
            Extract the proper names of PEOPLE mentioned in this transcript.
            Return only a JSON array of strings, e.g. ["Alice", "Bob"].
            If no names, return [].
            Transcript:
            \(transcript.prefix(2000))
            """

        guard let names = try? await callGroq(prompt: prompt), !names.isEmpty else { return }

        for name in names {
            let personID = UUID().uuidString
            store.execBind(
                "INSERT OR IGNORE INTO people (id, name) VALUES (?, ?);",
                args: [personID, name]
            )
            // Link person to session (uses name lookup to avoid duplication)
            store.execBind(
                """
                INSERT OR IGNORE INTO session_people (session_id, person_id)
                SELECT ?, id FROM people WHERE name = ? LIMIT 1;
                """,
                args: [sessionID, name]
            )
        }
        Log.info(.system, "Tagged \(names.count) people for session \(sessionID): \(names)")
    }

    private func callGroq(prompt: String) async throws -> [String] {
        var request = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "meta-llama/llama-4-scout-17b-16e-instruct",
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 200
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let content = msg["content"] as? String
        else { return [] }

        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let jsonData = cleaned.data(using: .utf8),
           let names = try? JSONDecoder().decode([String].self, from: jsonData) {
            return names
        }
        return []
    }
}
