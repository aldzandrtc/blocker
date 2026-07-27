import SwiftUI

struct GatekeeperView: View {
    @Environment(AppBlockerService.self) private var blocker

    @State private var argument: String = ""
    @State private var answer: String = ""
    @State private var isBusy = false
    @State private var timeRemaining = 120
    @State private var problemHeight: CGFloat = 90
    @FocusState private var answerFocused: Bool
    @FocusState private var argumentFocused: Bool

    private let judgeTimeLimit = 120
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            if let challenge = blocker.pendingChallenge {
                titleBar(challenge)

                Group {
                    switch challenge.phase {
                    case .starting:
                        waiting("Getting things ready")
                    case .judgePrompt:
                        judgeView(challenge)
                    case .judging:
                        waiting("The judge is considering it")
                    case .problemPrompt(let problem):
                        problemView(problem)
                    case .verifying:
                        waiting("Checking your answer")
                    case .allowed(let reason):
                        verdictView(granted: true, reason: reason)
                    case .denied(let reason):
                        verdictView(granted: false, reason: reason)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
            }
        }
        .frame(width: 560, height: 500)
        .background(Palette.canvas)
        .foregroundStyle(Palette.text)
        .onReceive(timer) { _ in tick() }
    }

    private var isStrict: Bool { blocker.pendingChallenge?.category == .strict }

    // MARK: - Title bar

    private func titleBar(_ challenge: GatekeeperChallenge) -> some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill((isStrict ? Palette.danger : Palette.accent).gradient)
                    .frame(width: 24, height: 24)
                Image(systemName: isStrict ? "building.columns.fill" : "function")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text(challenge.appName)
                .font(Face.display(13, .semibold))
                .lineLimit(1)

            Chip(text: isStrict ? "Judge" : "Quiz",
                 tint: isStrict ? Palette.danger : Palette.accent)

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Waiting

    private func waiting(_ title: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView().controlSize(.large)
            Text(title)
                .font(Face.body(12.5, .medium))
                .foregroundStyle(Palette.secondary)
            Spacer()
        }
    }

    // MARK: - Judge

    private func judgeView(_ challenge: GatekeeperChallenge) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Make your case")
                        .font(Face.display(26, .bold))
                    Text("You're trying to open **\(challenge.appName)**. The judge starts from no.")
                        .font(Face.body(13))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Countdown(remaining: timeRemaining, total: judgeTimeLimit)
            }
            .padding(.bottom, 16)

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

            Label("Boredom, \"just five minutes\", and anything that can wait are refused on sight.",
                  systemImage: "info.circle")
                .font(Face.body(11))
                .foregroundStyle(Palette.tertiary)
                .padding(.top, 9)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Never mind") { giveUp() }
                    .buttonStyle(GhostButtonStyle())
                Spacer()
                Button("Submit argument") { submitArgument() }
                    .buttonStyle(PrimaryButtonStyle(tint: Palette.danger))
                    .disabled(argument.trimmingCharacters(in: .whitespaces).isEmpty || isBusy)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.vertical, 16)
        }
        .onAppear { argumentFocused = true }
    }

    private func submitArgument() {
        guard !argument.trimmingCharacters(in: .whitespaces).isEmpty, !isBusy else { return }
        isBusy = true
        Task {
            await blocker.judge(argument: argument)
            isBusy = false
        }
    }

    // MARK: - Problem

    private func problemView(_ problem: GeneratedProblem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("One question")
                    .font(Face.display(26, .bold))
                Chip(text: problem.topic, tint: Palette.accent)
            }
            .padding(.bottom, 14)

            Card {
                ScrollView {
                    LaTeXWebView(text: problem.problem, dynamicHeight: $problemHeight)
                        .frame(height: max(problemHeight, 60))
                }
            }
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text("Your answer")
                    .font(Face.body(11, .medium))
                    .foregroundStyle(Palette.secondary)
                HStack(spacing: 10) {
                    TextField("", text: $answer)
                        .softField(focused: answerFocused)
                        .font(Face.mono(13))
                        .focused($answerFocused)
                        .disabled(isBusy)
                        .onSubmit(submitAnswer)
                    Button("Submit") { submitAnswer() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(answer.trimmingCharacters(in: .whitespaces).isEmpty || isBusy)
                        .keyboardShortcut(.return)
                }
            }
            .padding(.top, 14)

            HStack {
                Button("Give up") { giveUp() }
                    .buttonStyle(GhostButtonStyle())
                Spacer()
            }
            .padding(.vertical, 14)
        }
        .onAppear { answerFocused = true }
    }

    private func submitAnswer() {
        guard !answer.trimmingCharacters(in: .whitespaces).isEmpty, !isBusy else { return }
        isBusy = true
        Task {
            await blocker.verifyAnswer(answer)
            isBusy = false
        }
    }

    // MARK: - Verdict

    private func verdictView(granted: Bool, reason: String) -> some View {
        VStack(spacing: 0) {
            Spacer()

            Verdict(granted: granted)

            Text(reason)
                .font(Face.body(13))
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30)
                .padding(.top, 18)

            if !granted, let challenge = blocker.pendingChallenge {
                Text(cooldownNote(for: challenge))
                    .font(Face.body(11))
                    .foregroundStyle(Palette.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 30)
                    .padding(.top, 10)
            }

            Spacer()

            Button(granted ? "Go ahead" : "Back to work") {
                blocker.resolveChallenge()
                closeWindow()
            }
            .buttonStyle(PrimaryButtonStyle(tint: granted ? Palette.success : Palette.accent))
            .keyboardShortcut(.return)
            .padding(.bottom, 26)
        }
    }

    private func cooldownNote(for challenge: GatekeeperChallenge) -> String {
        switch challenge.trigger {
        case .launch:     "\(challenge.appName) will close."
        case .activation: "\(challenge.appName) will be hidden — anything open in it is untouched."
        }
    }

    // MARK: - Logic

    private func tick() {
        guard let challenge = blocker.pendingChallenge else { return }
        guard case .judgePrompt = challenge.phase, !isBusy else { return }
        if timeRemaining > 0 {
            timeRemaining -= 1
        } else {
            blocker.resolveChallenge()
            closeWindow()
        }
    }

    private func giveUp() {
        blocker.resolveChallenge()
        closeWindow()
    }

    private func closeWindow() {
        NotificationCenter.default.post(name: .gatekeeperWindowShouldClose, object: nil)
    }
}
