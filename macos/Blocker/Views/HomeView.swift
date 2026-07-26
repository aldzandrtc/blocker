import SwiftUI

struct HomeView: View {
    @Environment(SettingsStore.self) private var settings

    @State private var extensionDismissed = false
    @State private var showInstallHelp = false

    private let githubURL = URL(string: "https://github.com/aldzandrtc/blocker")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.block) {
                if !settings.extensionConnected && !extensionDismissed {
                    extensionNotice
                }

                standing
                blocklistDigest
                examsDigest
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Standing

    private var standing: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionRule(title: "Standing", trailing: Exam.dateFormatter.string(from: Date()))

            HStack(alignment: .top, spacing: 0) {
                figure(totalProblems, "solved")
                figure(accuracyStr, "accuracy", tint: accuracyTint)
                figure("\(settings.blockedTargets.count)", "blocked")
                figure("\(upcomingExams.count)", "exams")
            }
        }
    }

    private func figure(_ value: String, _ label: String, tint: Color = Palette.ink) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Face.display(27, .medium))
                .foregroundStyle(tint)
            Text(label.uppercased())
                .font(Face.clerk(8, .medium))
                .tracking(1.2)
                .foregroundStyle(Palette.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Blocklist digest

    private var blocklistDigest: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionRule(title: "Blocklist",
                        trailing: settings.blockedTargets.isEmpty ? nil
                                : "\(settings.blockedTargets.count) entries")

            if settings.blockedTargets.isEmpty {
                Text("Nothing is under injunction.")
                    .font(Face.body(12))
                    .foregroundStyle(Palette.faint)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(settings.blockedTargets.prefix(5).enumerated()), id: \.element.id) { index, target in
                        HStack(spacing: 10) {
                            Text(String(format: "%02d", index + 1))
                                .font(Face.clerk(9))
                                .foregroundStyle(Palette.faint)
                            Text(target.displayName)
                                .font(Face.body(12.5))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(target.category == .strict ? "JUDGE" : "EXAM")
                                .font(Face.clerk(9, .semibold))
                                .tracking(1.1)
                                .foregroundStyle(target.category == .strict ? Palette.seal : Palette.muted)
                        }
                        .padding(.vertical, 6)

                        if index < min(4, settings.blockedTargets.count - 1) {
                            Rule(color: Palette.ruleFaint)
                        }
                    }
                }

                if settings.blockedTargets.count > 5 {
                    Text("and \(settings.blockedTargets.count - 5) more")
                        .font(Face.clerk(9))
                        .foregroundStyle(Palette.faint)
                        .padding(.top, 2)
                }
            }
        }
    }

    // MARK: - Exams

    private var upcomingExams: [Exam] {
        settings.profile.exams
            .filter { $0.daysUntil() >= 0 }
            .sorted { $0.daysUntil() < $1.daysUntil() }
    }

    private var examsDigest: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionRule(title: "Calendar")

            if upcomingExams.isEmpty {
                Text("No examinations scheduled.")
                    .font(Face.body(12))
                    .foregroundStyle(Palette.faint)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(upcomingExams.prefix(3).enumerated()), id: \.element.id) { index, exam in
                        let days = exam.daysUntil()
                        HStack(spacing: 10) {
                            Text(exam.subject)
                                .font(Face.body(12.5))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(exam.date)
                                .font(Face.clerk(9))
                                .foregroundStyle(Palette.faint)
                            Text(days == 0 ? "TODAY" : "\(days)D")
                                .font(Face.clerk(10, .semibold))
                                .tracking(0.8)
                                .foregroundStyle(days <= 3 ? Palette.seal : Palette.muted)
                                .frame(width: 44, alignment: .trailing)
                        }
                        .padding(.vertical, 6)

                        if index < min(2, upcomingExams.count - 1) {
                            Rule(color: Palette.ruleFaint)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Extension notice

    private var extensionNotice: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                Text("NOTICE")
                    .font(Face.clerk(9, .bold))
                    .tracking(1.4)
                    .foregroundStyle(Palette.brass)
                Spacer()
                Button("Dismiss") { extensionDismissed = true }
                    .buttonStyle(PlainActionStyle(tint: Palette.faint))
            }

            Text("The browser extension is not answering.")
                .font(Face.display(14))

            Text("Websites stay open until it is installed. Applications are still gated.")
                .font(Face.body(11.5))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                Button("Download") { NSWorkspace.shared.open(githubURL) }
                    .buttonStyle(OutlineButtonStyle(tint: Palette.brass))
                Button(showInstallHelp ? "Hide steps" : "How to install") {
                    withAnimation(.easeInOut(duration: 0.12)) { showInstallHelp.toggle() }
                }
                .buttonStyle(PlainActionStyle())
            }

            if showInstallHelp {
                VStack(alignment: .leading, spacing: 5) {
                    step("i", "Download or clone the repository.")
                    step("ii", "Open chrome://extensions and enable Developer mode.")
                    step("iii", "Load unpacked → BlockerChromeExt on your Desktop.")
                }
                .padding(.top, 3)
            }
        }
        .padding(13)
        .background(Palette.surface)
        .overlay(
            Rectangle().fill(Palette.brass).frame(width: 3),
            alignment: .leading
        )
        .overlay(Rectangle().strokeBorder(Palette.rule, lineWidth: 1))
    }

    private func step(_ numeral: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(numeral)
                .font(Face.clerk(9))
                .foregroundStyle(Palette.brass)
                .frame(width: 16, alignment: .trailing)
            Text(text)
                .font(Face.body(11.5))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Derived

    private var totalProblems: String {
        "\(settings.problemHistory.reduce(0) { $0 + $1.total })"
    }

    private var accuracyValue: Double? {
        let total = settings.problemHistory.reduce(0) { $0 + $1.total }
        guard total > 0 else { return nil }
        let correct = settings.problemHistory.reduce(0) { $0 + $1.correct }
        return Double(correct) / Double(total)
    }

    private var accuracyStr: String {
        guard let accuracyValue else { return "—" }
        return "\(Int(accuracyValue * 100))%"
    }

    private var accuracyTint: Color {
        guard let accuracyValue else { return Palette.ink }
        return accuracyValue >= 0.7 ? Palette.verdigris : Palette.seal
    }
}
