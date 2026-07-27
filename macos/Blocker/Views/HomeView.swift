import SwiftUI

struct HomeView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppBlockerService.self) private var blocker

    @State private var extensionDismissed = false
    @State private var showInstallHelp = false
    @State private var now = Date()

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let githubURL = URL(string: "https://github.com/aldzandrtc/blocker")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.block) {
                if !settings.extensionConnected && !extensionDismissed {
                    extensionNotice
                }

                standing
                if !activeGrants.isEmpty { grants }
                if !cooldowns.isEmpty { coolingDown }
                blocklistDigest
                examsDigest
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 14)
        }
        .onReceive(ticker) { now = $0 }
    }

    // MARK: - Standing

    private var standing: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Today", trailing: friendlyDate)

            Card {
                VStack(spacing: 14) {
                    HStack(alignment: .top, spacing: 0) {
                        Stat(value: "\(settings.solvedToday)", label: "solved today",
                             tint: Palette.accent, systemImage: "checkmark.seal.fill")
                        Stat(value: "\(settings.currentStreak)", label: streakLabel,
                             tint: settings.currentStreak > 0 ? Palette.warning : Palette.text,
                             systemImage: "flame.fill")
                        Stat(value: accuracyStr, label: "accuracy",
                             tint: accuracyTint, systemImage: "target")
                        Stat(value: "\(settings.blockedTargets.count)", label: "blocked",
                             systemImage: "hand.raised.fill")
                    }

                    if let accuracy = accuracyValue {
                        VStack(alignment: .leading, spacing: 5) {
                            Meter(fraction: accuracy, tint: accuracyTint)
                            Text("\(totalCorrect) of \(totalProblems) problems answered correctly")
                                .font(Face.body(10.5))
                                .foregroundStyle(Palette.tertiary)
                        }
                    } else {
                        Text("No problems answered yet — they appear when you open something blocked.")
                            .font(Face.body(11))
                            .foregroundStyle(Palette.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var streakLabel: String { settings.currentStreak == 1 ? "day streak" : "day streak" }

    // MARK: - Grants

    private var activeGrants: [ActiveGrant] {
        _ = now // recompute as the clock ticks
        return blocker.activeGrants
    }

    private var grants: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Open right now",
                          trailing: "\(activeGrants.count) app\(activeGrants.count == 1 ? "" : "s")")

            Card(tint: Palette.success) {
                VStack(spacing: 0) {
                    ForEach(Array(activeGrants.enumerated()), id: \.element.id) { index, grant in
                        HStack(spacing: 10) {
                            Image(systemName: "lock.open.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.success)
                            Text(grant.name)
                                .font(Face.body(12.5, .medium))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Chip(text: "\(clockText(grant.secondsRemaining)) left", tint: Palette.success)
                            Button("Close") { blocker.revokeGrant(grant.bundleID) }
                                .buttonStyle(GhostButtonStyle())
                                .help("End this access now — no need to argue, tightening is always free")
                        }
                        .padding(.vertical, 6)

                        if index < activeGrants.count - 1 {
                            Divider().overlay(Palette.strokeFaint)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Cooldowns

    private var cooldowns: [(name: String, seconds: Int)] {
        _ = now
        return settings.blockedTargets.compactMap { target in
            let seconds = settings.cooldownRemaining(for: target.id)
            guard seconds > 0 else { return nil }
            return (target.displayName, seconds)
        }
        .sorted { $0.seconds < $1.seconds }
    }

    private var coolingDown: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Cooling down")

            Card(tint: Palette.warning) {
                VStack(spacing: 0) {
                    ForEach(Array(cooldowns.enumerated()), id: \.offset) { index, entry in
                        HStack(spacing: 10) {
                            Image(systemName: "hourglass")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.warning)
                            Text(entry.name)
                                .font(Face.body(12.5, .medium))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(clockText(entry.seconds))
                                .font(Face.mono(11, .semibold))
                                .foregroundStyle(Palette.warning)
                        }
                        .padding(.vertical, 6)

                        if index < cooldowns.count - 1 {
                            Divider().overlay(Palette.strokeFaint)
                        }
                    }

                    Text("A failed attempt locks a target for \(settings.profile.cooldownMinutes) minutes.")
                        .font(Face.body(10.5))
                        .foregroundStyle(Palette.tertiary)
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Blocklist digest

    private var blocklistDigest: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Blocked",
                          trailing: settings.blockedTargets.isEmpty ? nil
                                  : "\(settings.blockedTargets.count) total")

            Card {
                if settings.blockedTargets.isEmpty {
                    Text("Nothing is blocked yet. Add a site or app under Blocked.")
                        .font(Face.body(11.5))
                        .foregroundStyle(Palette.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 0) {
                        let shown = Array(settings.blockedTargets.prefix(5))
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, target in
                            HStack(spacing: 10) {
                                Image(systemName: target.isWebsite ? "globe" : "app.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Palette.tertiary)
                                    .frame(width: 14)
                                Text(target.displayName)
                                    .font(Face.body(12.5))
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Chip(text: target.category == .strict ? "Judge" : "Quiz",
                                     tint: Palette.tint(for: target.category))
                            }
                            .padding(.vertical, 6)

                            if index < shown.count - 1 {
                                Divider().overlay(Palette.strokeFaint)
                            }
                        }

                        if settings.blockedTargets.count > 5 {
                            Text("and \(settings.blockedTargets.count - 5) more")
                                .font(Face.body(10.5))
                                .foregroundStyle(Palette.tertiary)
                                .padding(.top, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
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
            SectionHeader(title: "Upcoming exams")

            Card {
                if upcomingExams.isEmpty {
                    Text("No exams scheduled. Add one in Profile and problems will lean toward that subject.")
                        .font(Face.body(11.5))
                        .foregroundStyle(Palette.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 0) {
                        let shown = Array(upcomingExams.prefix(3))
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, exam in
                            let days = exam.daysUntil()
                            HStack(spacing: 10) {
                                Text(exam.subject)
                                    .font(Face.body(12.5, .medium))
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(exam.date)
                                    .font(Face.body(10.5))
                                    .foregroundStyle(Palette.tertiary)
                                Chip(text: days == 0 ? "Today" : "\(days)d",
                                     tint: days <= 3 ? Palette.danger : Palette.accent,
                                     filled: days <= 3)
                            }
                            .padding(.vertical, 6)

                            if index < shown.count - 1 {
                                Divider().overlay(Palette.strokeFaint)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Extension notice

    private var extensionNotice: some View {
        Card(tint: Palette.warning) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.warning)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Browser extension isn't connected")
                            .font(Face.display(13, .semibold))
                        Text("Websites stay open until it's installed. Apps are still blocked.")
                            .font(Face.body(11))
                            .foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Button {
                        withAnimation(.easeOut(duration: 0.12)) { extensionDismissed = true }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(IconButtonStyle())
                    .accessibilityLabel("Dismiss")
                }

                HStack(spacing: 8) {
                    Button("Get the extension") { NSWorkspace.shared.open(githubURL) }
                        .buttonStyle(SecondaryButtonStyle(tint: Palette.warning))
                    Button(showInstallHelp ? "Hide steps" : "How to install") {
                        withAnimation(.easeOut(duration: 0.12)) { showInstallHelp.toggle() }
                    }
                    .buttonStyle(GhostButtonStyle())
                }

                if showInstallHelp {
                    VStack(alignment: .leading, spacing: 5) {
                        step(1, "Download or clone the repository, then run `make app`.")
                        step(2, "Open chrome://extensions and turn on Developer mode.")
                        step(3, "Load unpacked → BlockerChromeExt on your Desktop.")
                    }
                }
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(Face.body(9.5, .bold))
                .foregroundStyle(Palette.warning)
                .frame(width: 15, height: 15)
                .background(Circle().fill(Palette.warning.opacity(0.15)))
            Text(text)
                .font(Face.body(11))
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Derived

    private var friendlyDate: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMM"
        return f.string(from: Date())
    }

    private var totalProblems: Int {
        settings.problemHistory.reduce(0) { $0 + $1.total }
    }

    private var totalCorrect: Int {
        settings.problemHistory.reduce(0) { $0 + $1.correct }
    }

    private var accuracyValue: Double? {
        guard totalProblems > 0 else { return nil }
        return Double(totalCorrect) / Double(totalProblems)
    }

    private var accuracyStr: String {
        guard let accuracyValue else { return "—" }
        return "\(Int(accuracyValue * 100))%"
    }

    private var accuracyTint: Color {
        guard let accuracyValue else { return Palette.text }
        if accuracyValue >= 0.7 { return Palette.success }
        return accuracyValue >= 0.4 ? Palette.warning : Palette.danger
    }
}
