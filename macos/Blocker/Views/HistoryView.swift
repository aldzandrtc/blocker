import SwiftUI

struct HistoryView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Problem History")
                    .font(.title2)
                Spacer()
                if !settings.problemHistory.isEmpty {
                    Button("Clear") {
                        settings.problemHistory.removeAll()
                        settings.save()
                    }
                }
            }
            .padding(.horizontal)

            if settings.problemHistory.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No problems attempted yet")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(settings.problemHistory.sorted { $0.topic < $1.topic }) {
                    TableColumn("Topic", value: \.topic)
                    TableColumn("Accuracy") { record in
                        HStack {
                            Text("\(record.correct)/\(record.total)")
                            Text("(\(Int(record.accuracy * 100))%)")
                                .foregroundStyle(record.accuracy >= 0.7 ? .green : .red)
                        }
                    }
                    TableColumn("Last") { record in
                        Text(record.lastAsked)
                    }
                }
                .tableStyle(.inset)
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
    }
}
