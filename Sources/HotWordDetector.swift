// Sources/HotWordDetector.swift
import Foundation

struct HotWordMatch {
    let config: HotWordConfig
    let payload: String          // everything after "hot <keyword> [for project X]"
    let explicitProjectRef: String?  // "1", "2", or project name if specified
}

struct HotWordDetector {
    // Pattern: "hot <keyword> [for project <ref>] <payload>"
    // Case-insensitive.
    private static let pattern = try! NSRegularExpression(
        pattern: #"\bhot\s+(\w+)(?:\s+for\s+project\s+(\w+))?\s+(.+)"#,
        options: [.caseInsensitive]
    )

    static func detect(in transcript: String, configs: [HotWordConfig]) -> [HotWordMatch] {
        let range = NSRange(transcript.startIndex..., in: transcript)
        let matches = pattern.matches(in: transcript, range: range)

        return matches.compactMap { match in
            guard
                let keywordRange = Range(match.range(at: 1), in: transcript),
                let payloadRange = Range(match.range(at: 3), in: transcript)
            else { return nil }

            let keyword = String(transcript[keywordRange]).lowercased()
            let payload = String(transcript[payloadRange]).trimmingCharacters(in: .whitespaces)

            let projectRef: String?
            if let projRange = Range(match.range(at: 2), in: transcript), !transcript[projRange].isEmpty {
                projectRef = String(transcript[projRange])
            } else {
                projectRef = nil
            }

            guard let config = configs.first(where: { $0.keyword.lowercased() == keyword }) else {
                return nil
            }

            return HotWordMatch(config: config, payload: payload, explicitProjectRef: projectRef)
        }
    }
}
