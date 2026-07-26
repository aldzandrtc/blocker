import SwiftUI

struct HistoryView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Academic record")
                    .font(Face.display(16, .semibold))
                Spacer()
                if !settings.problemHistory.isEmpty {
                    Text(overallLabel)
                        .font(Face.clerk(10))
                        .foregroundStyle(Palette.muted)
                    Button("Expunge") {
                        settings.problemHistory.removeAll()
                        settings.save()
                    }
                    .buttonStyle(PlainActionStyle())
                    .padding(.leading, 10)
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 16)
            .padding(.bottom, 12)

            if sortedHistory.isEmpty {
                EmptyNotice(title: "No examinations on record.",
                            subtitle: "Topics you fail are weighted more heavily next time.")
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        SectionRule(title: "Topic", trailing: "Marks")
                            .padding(.bottom, 6)

                        ForEach(sortedHistory) { record in
                            row(record)
                            Rule(color: Palette.ruleFaint)
                        }
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.bottom, Metrics.gutter)
                }
            }
        }
    }

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
        let tint = record.accuracy >= 0.7 ? Palette.verdigris
                 : (record.accuracy >= 0.4 ? Palette.brass : Palette.seal)

        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(record.topic)
                    .font(Face.body(12.5))
                    .lineLimit(1)
                if record.accuracy < 0.5 {
                    Text("WEAK")
                        .font(Face.clerk(8, .bold))
                        .tracking(1.1)
                        .foregroundStyle(Palette.seal)
                }
                Spacer(minLength: 8)
                Text("\(record.correct)/\(record.total)")
                    .font(Face.clerk(10))
                    .foregroundStyle(Palette.faint)
                Text("\(Int(record.accuracy * 100))%")
                    .font(Face.display(15, .medium))
                    .foregroundStyle(tint)
                    .frame(width: 42, alignment: .trailing)
            }

            // Marks bar, drawn as a ruled measure rather than a rounded pill.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Palette.ruleFaint)
                    Rectangle().fill(tint).frame(width: max(2, geo.size.width * record.accuracy))
                }
            }
            .frame(height: 3)

            if !record.lastAsked.isEmpty {
                Text("last examined \(record.lastAsked)")
                    .font(Face.clerk(8))
                    .foregroundStyle(Palette.faint)
            }
        }
        .padding(.vertical, 9)
    }
}
