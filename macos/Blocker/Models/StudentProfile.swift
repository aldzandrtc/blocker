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

    /// Fixed-format parsing needs a fixed locale and calendar, or it breaks for
    /// users on a non-Gregorian calendar. Shared because `daysUntil()` runs on
    /// every render for every exam.
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    func daysUntil() -> Int {
        guard let target = Self.dateFormatter.date(from: date) else { return 999 }
        let seconds = target.timeIntervalSince(Date())
        return Int(ceil(seconds / 86400.0))
    }
}
