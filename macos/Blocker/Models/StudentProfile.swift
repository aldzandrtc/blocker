import Foundation

struct StudentProfile: Codable {
    var subjects: [String] = []
    var currentFocus: String = ""
    var exams: [Exam] = []
    var difficultyLevel: String = "college"
    var unblockDurationMinutes: Int = 30
    var cooldownMinutes: Int = 5
}

struct Exam: Codable, Identifiable {
    var id = UUID()
    var subject: String
    var date: String // YYYY-MM-DD

    func daysUntil() -> Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let target = formatter.date(from: date) else { return 999 }
        let seconds = target.timeIntervalSince(Date())
        return Int(ceil(seconds / 86400.0))
    }
}
