import Foundation

/// One row per calendar day — what the streak and the activity strip are built
/// from. Days with no attempts simply have no row.
struct DailyActivity: Codable, Identifiable {
    /// `yyyy-MM-dd` in the user's own timezone, so "today" means their today.
    var day: String
    var solved: Int = 0
    var failed: Int = 0

    var id: String { day }
    var total: Int { solved + failed }

    mutating func record(solved didSolve: Bool) {
        if didSolve { solved += 1 } else { failed += 1 }
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayKey(for date: Date) -> String {
        formatter.string(from: date)
    }
}
