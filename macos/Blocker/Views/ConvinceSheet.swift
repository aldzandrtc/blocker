import SwiftUI

/// Shared petition flow. Used anywhere the student tries to weaken their own
/// setup — striking a blocklist entry, or loosening the timings.
struct ConvinceSheet: View {
    let headline: String
    /// What is being asked for, shown to the student and sent to the judge.
    let request: String
    let approvedTitle: String
    let judge: (String) async -> AiJudgment
    let onApproved: () -> Void
    @Binding var isPresented: Bool

    @State private var argument = ""
    @State private var isBusy = false
    @State private var result: AiJudgment?
    @State private var timeRemaining = 120

    private let timeLimit = 120
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            if let result {
                verdict(result)
            } else {
                petition
            }
        }
        .frame(width: 440, height: 390)
        .background(Palette.paper)
        .foregroundStyle(Palette.ink)
        .onReceive(timer) { _ in tick() }
    }

    // MARK: - Petition

    private var petition: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(headline)
                        .font(Face.display(20, .semibold))
                    Text("The default answer is deny.")
                        .font(Face.body(11.5))
                        .foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 14)
                Countdown(remaining: timeRemaining, total: timeLimit)
            }
            Rule(color: Palette.ink, weight: 2)
                .padding(.top, 11)

            Text(request)
                .font(Face.body(12.5))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 13)

            SectionRule(title: "Statement")
            ZStack(alignment: .topLeading) {
                TextEditor(text: $argument)
                    .font(Face.body(12.5))
                    .scrollContentBackground(.hidden)
                    .padding(.top, 8)
                    .disabled(isBusy)

                if argument.isEmpty {
                    Text("Be specific. Name the deadline.")
                        .font(Face.body(12.5))
                        .foregroundStyle(Palette.faint)
                        .padding(.top, 13)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxHeight: .infinity)
            Rule()

            HStack {
                Button("Cancel") { isPresented = false }
                    .buttonStyle(PlainActionStyle())
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                if isBusy {
                    Text("DELIBERATING")
                        .font(Face.clerk(9, .semibold))
                        .tracking(1.6)
                        .foregroundStyle(Palette.muted)
                } else {
                    Button("Submit argument") { submit() }
                        .buttonStyle(SealButtonStyle(tint: Palette.seal))
                        .disabled(argument.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.return)
                }
            }
            .padding(.top, 14)
        }
        .padding(22)
    }

    // MARK: - Verdict

    private func verdict(_ result: AiJudgment) -> some View {
        let tint = result.allowed ? Palette.verdigris : Palette.seal

        return VStack(spacing: 0) {
            Spacer()
            Stamp(text: result.allowed ? approvedTitle : "Denied", tint: tint)
            Text(result.reason)
                .font(Face.display(14))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 34)
                .padding(.top, 24)
            Spacer()
            Button("Close") { isPresented = false }
                .buttonStyle(OutlineButtonStyle(tint: Palette.ink))
                .keyboardShortcut(.return)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Logic

    private func tick() {
        guard result == nil, !isBusy else { return }
        if timeRemaining > 0 {
            timeRemaining -= 1
        } else {
            result = AiJudgment(allowed: false, reason: "Time expired. Denied automatically.")
        }
    }

    private func submit() {
        isBusy = true
        Task {
            let judgment = await judge(argument)
            if judgment.allowed { onApproved() }
            result = judgment
            isBusy = false
        }
    }
}

// MARK: - Blocklist removal

struct RemoveGatekeeperSheet: View {
    let target: BlockedTarget
    let settings: SettingsStore
    @Binding var isPresented: Bool

    var body: some View {
        ConvinceSheet(
            headline: "Petition to strike",
            request: "You ask that \(target.displayName) be struck from the blocklist entirely.",
            approvedTitle: "Struck",
            judge: { argument in
                let judge = BlocklistJudge(client: settings.makeClient())
                return await judge.judgeSettingChange(
                    change: "remove \(target.displayName) from the blocklist entirely",
                    argument: argument
                )
            },
            onApproved: { settings.removeTarget(target.id) },
            isPresented: $isPresented
        )
    }
}

// MARK: - Timing changes

/// Loosening the timings is the easiest way to defang the whole app, so the
/// same judge that guards the blocklist guards these two numbers.
struct TimingChangeSheet: View {
    let settings: SettingsStore
    @Binding var isPresented: Bool

    @State private var unblock: Double
    @State private var cooldown: Double
    @State private var arguing = false

    init(settings: SettingsStore, isPresented: Binding<Bool>) {
        self.settings = settings
        self._isPresented = isPresented
        self._unblock = State(initialValue: Double(settings.profile.unblockDurationMinutes))
        self._cooldown = State(initialValue: Double(settings.profile.cooldownMinutes))
    }

    private var currentUnblock: Int { settings.profile.unblockDurationMinutes }
    private var currentCooldown: Int { settings.profile.cooldownMinutes }
    private var newUnblock: Int { Int(unblock) }
    private var newCooldown: Int { Int(cooldown) }

    private var changed: Bool {
        newUnblock != currentUnblock || newCooldown != currentCooldown
    }

    /// A longer unblock window or a shorter cooldown makes the blocker weaker.
    private var weakens: Bool {
        newUnblock > currentUnblock || newCooldown < currentCooldown
    }

    private var changeDescription: String {
        var parts: [String] = []
        if newUnblock != currentUnblock {
            parts.append("change the unblock window from \(currentUnblock) to \(newUnblock) minutes")
        }
        if newCooldown != currentCooldown {
            parts.append("change the cooldown from \(currentCooldown) to \(newCooldown) minutes")
        }
        return parts.joined(separator: ", and ")
    }

    var body: some View {
        if arguing {
            ConvinceSheet(
                headline: "Petition to amend",
                request: "You ask to \(changeDescription).",
                approvedTitle: "Amended",
                judge: { argument in
                    let judge = BlocklistJudge(client: settings.makeClient())
                    return await judge.judgeSettingChange(change: changeDescription, argument: argument)
                },
                onApproved: apply,
                isPresented: $isPresented
            )
        } else {
            adjustView
        }
    }

    private var adjustView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Standing orders")
                .font(Face.display(20, .semibold))
            Rule(color: Palette.ink, weight: 2)
                .padding(.top, 11)

            Text("Tightening takes effect at once. Loosening must be argued.")
                .font(Face.body(11.5))
                .foregroundStyle(Palette.muted)
                .padding(.vertical, 13)
                .fixedSize(horizontal: false, vertical: true)

            dial(title: "Unblock window",
                 caption: "How long a target stays open once you pass.",
                 value: $unblock, range: 5...120, step: 5,
                 current: currentUnblock, looserWhenHigher: true)

            Spacer().frame(height: 18)

            dial(title: "Cooldown",
                 caption: "Minimum wait before the gate can be challenged again.",
                 value: $cooldown, range: 1...30, step: 1,
                 current: currentCooldown, looserWhenHigher: false)

            Spacer(minLength: 14)

            if changed && weakens {
                Text("This weakens your own orders. The judge decides.")
                    .font(Face.body(11))
                    .foregroundStyle(Palette.seal)
                    .padding(.bottom, 10)
            }

            Rule()
            HStack {
                Button("Cancel") { isPresented = false }
                    .buttonStyle(PlainActionStyle())
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button(weakens ? "Argue your case" : "Apply") {
                    if weakens {
                        arguing = true
                    } else {
                        apply()
                        isPresented = false
                    }
                }
                .buttonStyle(SealButtonStyle(tint: weakens ? Palette.seal : Palette.ink))
                .disabled(!changed)
                .keyboardShortcut(.return)
            }
            .padding(.top, 14)
        }
        .padding(22)
        .frame(width: 440, height: 390)
        .background(Palette.paper)
        .foregroundStyle(Palette.ink)
    }

    private func dial(title: String, caption: String, value: Binding<Double>,
                      range: ClosedRange<Double>, step: Double,
                      current: Int, looserWhenHigher: Bool) -> some View {
        let proposed = Int(value.wrappedValue)
        let isLooser = looserWhenHigher ? proposed > current : proposed < current
        let tint = proposed == current ? Palette.ink : (isLooser ? Palette.seal : Palette.verdigris)

        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(Face.clerk(9, .semibold))
                    .tracking(1.3)
                    .foregroundStyle(Palette.muted)
                Spacer()
                if proposed != current {
                    Text("\(current)")
                        .font(Face.clerk(11))
                        .foregroundStyle(Palette.faint)
                        .strikethrough()
                    Text("→")
                        .font(Face.clerk(10))
                        .foregroundStyle(Palette.faint)
                }
                Text("\(proposed)")
                    .font(Face.display(20, .medium))
                    .foregroundStyle(tint)
                Text("min")
                    .font(Face.clerk(9))
                    .foregroundStyle(Palette.faint)
            }
            Slider(value: value, in: range, step: step)
                .controlSize(.mini)
                .tint(tint)
            Text(caption)
                .font(Face.body(10.5))
                .foregroundStyle(Palette.faint)
        }
    }

    private func apply() {
        settings.profile.unblockDurationMinutes = newUnblock
        settings.profile.cooldownMinutes = newCooldown
        settings.save()
    }
}
