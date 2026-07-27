import SwiftUI

/// Shared appeal flow. Used anywhere the student tries to weaken their own
/// setup — removing something from the blocklist, or loosening the limits.
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
    @FocusState private var argumentFocused: Bool

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
        .frame(width: 460, height: 420)
        .background(Palette.canvas)
        .foregroundStyle(Palette.text)
        .onReceive(timer) { _ in tick() }
    }

    // MARK: - Petition

    private var petition: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline)
                        .font(Face.display(19, .bold))
                    Text("The judge starts from no.")
                        .font(Face.body(11.5))
                        .foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 8)
                Countdown(remaining: timeRemaining, total: timeLimit)
            }
            .padding(.bottom, 12)

            Card(padding: 11, tint: Palette.warning) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.warning)
                    Text(request)
                        .font(Face.body(12))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 12)

            Text("Your argument")
                .font(Face.body(11, .medium))
                .foregroundStyle(Palette.secondary)
                .padding(.bottom, 6)

            Card(padding: 0) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $argument)
                        .font(Face.body(12.5))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .focused($argumentFocused)
                        .disabled(isBusy)

                    if argument.isEmpty {
                        Text("Be specific. Name the deadline.")
                            .font(Face.body(12.5))
                            .foregroundStyle(Palette.tertiary)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)

            HStack {
                Button("Cancel") { isPresented = false }
                    .buttonStyle(GhostButtonStyle())
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                if isBusy {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text("Considering it")
                            .font(Face.body(11.5))
                            .foregroundStyle(Palette.secondary)
                    }
                } else {
                    Button("Submit argument") { submit() }
                        .buttonStyle(PrimaryButtonStyle(tint: Palette.danger))
                        .disabled(argument.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .padding(.top, 14)
        }
        .padding(20)
        .onAppear { argumentFocused = true }
    }

    // MARK: - Verdict

    private func verdict(_ result: AiJudgment) -> some View {
        VStack(spacing: 0) {
            Spacer()
            Verdict(granted: result.allowed, title: result.allowed ? approvedTitle : "Denied")
            Text(result.reason)
                .font(Face.body(12.5))
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 34)
                .padding(.top, 18)
            Spacer()
            Button("Close") { isPresented = false }
                .buttonStyle(PrimaryButtonStyle(tint: result.allowed ? Palette.success : Palette.accent))
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
            result = AiJudgment(allowed: false, reason: "Time ran out. Denied automatically.")
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
            headline: "Remove \(target.displayName)?",
            request: "You're asking to take \(target.displayName) off the blocklist entirely — no gatekeeper, no question, no judge.",
            approvedTitle: "Removed",
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

/// Loosening the limits is the easiest way to defang the whole app, so the same
/// judge that guards the blocklist guards these two numbers.
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
                headline: "Loosen your limits?",
                request: "You're asking to \(changeDescription).",
                approvedTitle: "Changed",
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
            Text("Limits")
                .font(Face.display(19, .bold))
            Text("Tightening applies immediately. Loosening has to be argued.")
                .font(Face.body(11.5))
                .foregroundStyle(Palette.secondary)
                .padding(.top, 3)
                .padding(.bottom, 16)

            dial(title: "Unblock window",
                 caption: "How long a target stays open once you're through.",
                 value: $unblock, range: 5...120, step: 5,
                 current: currentUnblock, looserWhenHigher: true)

            Spacer().frame(height: 16)

            dial(title: "Cooldown",
                 caption: "How long you wait after a failed attempt.",
                 value: $cooldown, range: 1...30, step: 1,
                 current: currentCooldown, looserWhenHigher: false)

            Spacer(minLength: 14)

            if changed && weakens {
                Card(padding: 10, tint: Palette.danger) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.danger)
                        Text("This weakens your own limits, so the judge decides.")
                            .font(Face.body(11.5))
                            .foregroundStyle(Palette.secondary)
                    }
                }
                .padding(.bottom, 10)
            }

            HStack {
                Button("Cancel") { isPresented = false }
                    .buttonStyle(GhostButtonStyle())
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
                .buttonStyle(PrimaryButtonStyle(tint: weakens ? Palette.danger : Palette.accent))
                .disabled(!changed)
                .keyboardShortcut(.return)
            }
            .padding(.top, 12)
        }
        .padding(20)
        .frame(width: 460, height: 420)
        .background(Palette.canvas)
        .foregroundStyle(Palette.text)
    }

    private func dial(title: String, caption: String, value: Binding<Double>,
                      range: ClosedRange<Double>, step: Double,
                      current: Int, looserWhenHigher: Bool) -> some View {
        let proposed = Int(value.wrappedValue)
        let isLooser = looserWhenHigher ? proposed > current : proposed < current
        let tint = proposed == current ? Palette.accent : (isLooser ? Palette.danger : Palette.success)

        return Card {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(Face.body(12, .semibold))
                    Spacer()
                    if proposed != current {
                        Text("\(current)")
                            .font(Face.body(11))
                            .foregroundStyle(Palette.tertiary)
                            .strikethrough()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Palette.tertiary)
                    }
                    Text("\(proposed)")
                        .font(Face.display(18, .bold))
                        .foregroundStyle(tint)
                    Text("min")
                        .font(Face.body(10.5))
                        .foregroundStyle(Palette.tertiary)
                }
                Slider(value: value, in: range, step: step)
                    .controlSize(.small)
                    .tint(tint)
                Text(caption)
                    .font(Face.body(10.5))
                    .foregroundStyle(Palette.tertiary)
            }
        }
    }

    private func apply() {
        settings.profile.unblockDurationMinutes = newUnblock
        settings.profile.cooldownMinutes = newCooldown
        settings.save()
    }
}
