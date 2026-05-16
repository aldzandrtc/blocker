import Foundation

struct ProblemRecord: Codable, Identifiable {
    var id = UUID()
    var topic: String
    var correct: Int = 0
    var incorrect: Int = 0
    var lastAsked: String = ""

    var total: Int { correct + incorrect }
    var accuracy: Double { total > 0 ? Double(correct) / Double(total) : 0 }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    mutating func record(correct: Bool) {
        if correct { self.correct += 1 }
        else { self.incorrect += 1 }
        lastAsked = Self.dateFormatter.string(from: Date())
    }
}
