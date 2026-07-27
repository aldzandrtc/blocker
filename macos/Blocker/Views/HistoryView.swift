import SwiftUI

struct HistoryView: View {
    @Environment(SettingsStore.self) private var settings

    @State private var confirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            header

            if sortedHistory.isEmpty {
                EmptyNotice(title: "No problems answered yet",
                            subtitle: "Topics you get wrong are weighted more heavily next time.",
                            systemImage: "chart.bar")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Metrics.block) {
                        if !settings.activity.isEmpty { activityStrip }

                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "By topic", trailing: "weakest first")
                            VStack(spacing: 8) {
                                ForEach(sortedHistory) { record in
                                    row(record)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.bottom, Metrics.gutter)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Progress")
                .font(Face.display(17, .bold))
            Spacer()
            if !settings.problemHistory.isEmpty {
                Text(overallLabel)
                    .font(Face.mono(11, .medium))
                    .foregroundStyle(Palette.secondary)
                Button(confirmingClear ? "Really clear?" : "Clear") {
                    if confirmingClear {
                        settings.problemHistory.removeAll()
                        settings.activity.removeAll()
                        settings.save()
                        confirmingClear = false
                    } else {
                        confirmingClear = true
                    }
                }
                .buttonStyle(GhostButtonStyle(tint: confirmingClear ? Palette.danger : Palette.tertiary))
                .padding(.leading, 6)
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: - Activity

    /// The last 30 days as a strip, so a broken streak is visible rather than
    /// just a number that quietly went back to zero.
    private var activityStrip: some View {
        let days = recentDays()
        let peak = max(1, days.map(\.total).max() ?? 1)

        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Last 30 days",
                          trailing: settings.currentStreak > 0
                              ? "\(settings.currentStreak)-day streak" : nil)

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(days, id: \.day) { entry in
                            bar(for: entry, peak: peak)
                        }
                    }
                    .frame(height: 36)

                    HStack {
                        Text("30 days ago")
                        Spacer()
                        Text("today")
                    }
                    .font(Face.body(9.5))
                    .foregroundStyle(Palette.tertiary)
                }
            }
        }
    }

    private func bar(for entry: DailyActivity, peak: Int) -> some View {
        let height: CGFloat = entry.total == 0
            ? 3
            : max(4, 34 * CGFloat(entry.total) / CGFloat(peak))
        let tooltip = entry.total == 0
            ? "\(entry.day): nothing"
            : "\(entry.day): \(entry.solved) right, \(entry.failed) wrong"

        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(barTint(for: entry))
                .frame(height: height)
        }
        .frame(maxWidth: .infinity)
        .help(tooltip)
    }

    private func barTint(for entry: DailyActivity) -> Color {
        guard entry.total > 0 else { return Palette.strokeFaint }
        let accuracy = Double(entry.solved) / Double(entry.total)
        if accuracy >= 0.7 { return Palette.success }
        return accuracy >= 0.4 ? Palette.warning : Palette.danger
    }

    private func recentDays() -> [DailyActivity] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let byDay = Dictionary(uniqueKeysWithValues: settings.activity.map { ($0.day, $0) })

        return (0..<30).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let key = DailyActivity.dayKey(for: date)
            return byDay[key] ?? DailyActivity(day: key)
        }
    }

    // MARK: - Topics

    /// Weakest topics first — those are the ones worth seeing.
    private var sortedHistory: [ProblemRecord] {
        settings.problemHistory
            .filter { $0.total > 0 }
            .sorted { $0.accuracy == $1.accuracy ? $0.topic < $1.topic : $0.accuracy < $1.accuracy }
    }

    private var overallLabel: String {
        let total = settings.problemHistory.reduce(0) { $0 + $1.total }
        let correct = settings.problemHistory.reduce(0) { $0 + $1.correct }
        guard total > 0 else { return "" }
        return "\(correct)/\(total)"
    }

    private func row(_ record: ProblemRecord) -> some View {
        let tint = record.accuracy >= 0.7 ? Palette.success
                 : (record.accuracy >= 0.4 ? Palette.warning : Palette.danger)

        return Card(padding: 11) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(record.topic)
                        .font(Face.body(12.5, .semibold))
                        .lineLimit(1)
                    if record.accuracy < 0.5 {
                        Chip(text: "Weak", tint: Palette.danger)
                    }
                    Spacer(minLength: 6)
                    Text("\(record.correct)/\(record.total)")
                        .font(Face.mono(10.5))
                        .foregroundStyle(Palette.tertiary)
                    Text("\(Int(record.accuracy * 100))%")
                        .font(Face.display(15, .bold))
                        .foregroundStyle(tint)
                        .frame(width: 42, alignment: .trailing)
                }

                Meter(fraction: record.accuracy, tint: tint, height: 4)

                if !record.lastAsked.isEmpty {
                    Text("last asked \(record.lastAsked)")
                        .font(Face.body(9.5))
                        .foregroundStyle(Palette.tertiary)
                }
            }
        }
    }
}
