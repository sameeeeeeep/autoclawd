import Foundation

// MARK: - QAItem

struct QAItem: Identifiable {
    let id: String
    let question: String
    let answer: String
    let timestamp: Date

    init(question: String, answer: String) {
        self.id        = UUID().uuidString
        self.question  = question
        self.answer    = answer
        self.timestamp = Date()
    }
}

// MARK: - QAStore

@MainActor
final class QAStore: ObservableObject {
    @Published private(set) var items: [QAItem] = []

    func append(question: String, answer: String) {
        items.insert(QAItem(question: question, answer: answer), at: 0)
    }
}
