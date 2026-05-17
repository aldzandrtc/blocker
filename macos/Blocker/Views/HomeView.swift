import SwiftUI

struct HomeView: View {
    @Environment(SettingsStore.self) private var settings

    @State private var extensionDismissed = false
    @State private var showInstallHelp = false

    private let githubURL = URL(string: "https://github.com/aldzandrtc/blocker")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Extension prompt (only when not connected)
                if !settings.extensionConnected && !extensionDismissed {
                    extensionBanner
                        .padding(.horizontal)
                }

                Text("Dashboard")
                    .font(.title2)
                    .padding(.horizontal)

                // Stats card
                GroupBox {
                    HStack(spacing: 24) {
                        stat(label: "Blocked", value: "\(settings.blockedTargets.count)")
                        stat(label: "Exams", value: "\(settings.profile.exams.count)")
                        stat(label: "Problems", value: "\(totalProblems)")
                        stat(label: "Accuracy", value: accuracyStr)
                    }
                    .frame(maxWidth: .infinity)
                } label: {
                    Label("Overview", systemImage: "chart.bar.fill")
                }
                .padding(.horizontal)

                // Blocklist preview
                GroupBox {
                    if settings.blockedTargets.isEmpty {
                        Text("No blocked targets yet")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(settings.blockedTargets.prefix(5)) { target in
                            HStack {
                                Image(systemName: target.category == .strict ? "xmark.shield" : "pencil.and.list.clipboard")
                                    .font(.caption)
                                Text(target.displayName)
                                    .font(.body)
                                Spacer()
                                Text(target.category == .strict ? "Strict" : "Regular")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                        if settings.blockedTargets.count > 5 {
                            Text("+ \(settings.blockedTargets.count - 5) more...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } label: {
                    Label("Blocklist", systemImage: "hand.raised.fill")
                }
                .padding(.horizontal)

                // Upcoming exams
                GroupBox {
                    let upcoming = settings.profile.exams
                        .filter { $0.daysUntil() >= 0 }
                        .sorted { $0.daysUntil() < $1.daysUntil() }
                    if upcoming.isEmpty {
                        Text("No upcoming exams")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(upcoming.prefix(3)) { exam in
                            HStack {
                                Text(exam.subject)
                                Spacer()
                                Text("\(exam.daysUntil())d left")
                                    .foregroundStyle(exam.daysUntil() <= 3 ? .red : .secondary)
                                    .font(.caption)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } label: {
                    Label("Upcoming Exams", systemImage: "calendar")
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.vertical)
        }
    }

    // MARK: - Extension banner

    private var extensionBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Chrome extension not detected")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("The extension blocks websites and syncs with this app. Install it to get full blocking coverage.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    extensionDismissed = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Button {
                    NSWorkspace.shared.open(githubURL)
                } label: {
                    Label("Download from GitHub", systemImage: "arrow.down.circle.fill")
                        .font(.caption)
                }

                Button {
                    showInstallHelp.toggle()
                } label: {
                    Label(showInstallHelp ? "Hide steps" : "How to install",
                          systemImage: showInstallHelp ? "chevron.up" : "questionmark.circle")
                        .font(.caption)
                }
            }

            if showInstallHelp {
                VStack(alignment: .leading, spacing: 6) {
                    step(1, "Open", "chrome://extensions")
                    step(2, "Toggle", "Developer mode ON (top right)")
                    step(3, "Click", "Load unpacked → select the BlockerChromeExt folder")
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }

    private func step(_ num: Int, _ verb: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(num).")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.orange)
                .frame(width: 16, alignment: .leading)
            Text("\(verb) ").font(.caption).fontWeight(.medium)
                + Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Stats

    private func stat(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var totalProblems: String {
        let n = settings.problemHistory.reduce(0) { $0 + $1.total }
        return "\(n)"
    }

    private var accuracyStr: String {
        let total = settings.problemHistory.reduce(0) { $0 + $1.total }
        guard total > 0 else { return "—" }
        let correct = settings.problemHistory.reduce(0) { $0 + $1.correct }
        return "\(Int(Double(correct) / Double(total) * 100))%"
    }
}
