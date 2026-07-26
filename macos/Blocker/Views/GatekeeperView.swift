import SwiftUI

struct GatekeeperView: View {
    @Environment(AppBlockerService.self) private var blocker

    @State private var argument: String = ""
    @State private var answer: String = ""
    @State private var isBusy = false
    @State private var timeRemaining = 120
    @State private var problemHeight: CGFloat = 90
    @FocusState private var answerFocused: Bool

    private let judgeTimeLimit = 120
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            if let challenge = blocker.pendingChallenge {
                docket(challenge)
                Rule(color: Palette.ink, weight: 2)

                Group {
                    switch challenge.phase {
                    case .starting:
                        recess("Preparing the challenge")
                    case .judgePrompt:
                        judgeView(challenge)
                    case .judging:
                        recess("The judge is deliberating")
                    case .problemPrompt(let problem):
                        problemView(problem)
                    case .verifying:
                        recess("Marking your answer")
                    case .allowed(let reason):
                        verdictView(granted: true, reason: reason)
                    case .denied(let reason):
                        verdictView(granted: false, reason: reason)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 26)
            }
        }
        .frame(width: 540, height: 460)
        .background(Palette.paper)
        .foregroundStyle(Palette.ink)
        .onReceive(timer) { _ in tick() }
    }

    private var isStrict: Bool { blocker.pendingChallenge?.category == .strict }

    // MARK: - Docket

    private func docket(_ challenge: GatekeeperChallenge) -> some View {
        HStack {
            Text("THE GATEKEEPER")
                .font(Face.display(12, .bold))
                .tracking(3)
            Spacer()
            DocketLine(parts: [
                "case \(caseNumber(from: challenge.id))",
                challenge.appName,
                isStrict ? "strict" : "regular",
            ])
        }
        .padding(.horizontal, 26)
        .padding(.top, 16)
        .padding(.bottom, 11)
    }

    // MARK: - Recess (busy)

    private func recess(_ title: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Text(title.uppercased())
                .font(Face.clerk(10, .semibold))
                .tracking(2)
                .foregroundStyle(Palette.muted)
            ProgressView().controlSize(.small)
            Spacer()
        }
    }

    // MARK: - Judge

    private func judgeView(_ challenge: GatekeeperChallenge) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 22)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Convince the Judge")
                        .font(Face.display(29, .semibold))
                    Text("You moved to open **\(challenge.appName)**. The default answer is deny.")
                        .font(Face.body(13))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 16)
                Countdown(remaining: timeRemaining, total: judgeTimeLimit)
            }

            Spacer().frame(height: 20)

            SectionRule(title: "Statement of the accused")
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

            Text("Boredom, “just five minutes”, and anything that can wait are denied on sight.")
                .font(Face.body(11))
                .foregroundStyle(Palette.faint)
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Withdraw") { giveUp() }
                    .buttonStyle(PlainActionStyle())
                Spacer()
                Button("Submit argument") {
                    isBusy = true
                    Task {
                        await blocker.judge(argument: argument)
                        isBusy = false
                    }
                }
                .buttonStyle(SealButtonStyle(tint: Palette.seal))
                .disabled(argument.trimmingCharacters(in: .whitespaces).isEmpty || isBusy)
                .keyboardShortcut(.return)
            }
            .padding(.vertical, 16)
        }
    }

    // MARK: - Problem

    private func problemView(_ problem: GeneratedProblem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 20)

            Text("Examination")
                .font(Face.display(29, .semibold))
            Text(problem.topic)
                .font(Face.clerk(10))
                .tracking(1)
                .foregroundStyle(Palette.muted)
                .padding(.top, 5)
                .lineLimit(1)

            Spacer().frame(height: 16)

            SectionRule(title: "Question")
            ScrollView {
                LaTeXWebView(text: problem.problem, dynamicHeight: $problemHeight)
                    .frame(height: max(problemHeight, 60))
            }
            .frame(maxHeight: .infinity)
            Rule()

            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("ANSWER")
                        .font(Face.clerk(9, .semibold))
                        .tracking(1.3)
                        .foregroundStyle(Palette.muted)
                    TextField("", text: $answer)
                        .ruledField(focused: answerFocused)
                        .focused($answerFocused)
                        .disabled(isBusy)
                        .onSubmit(submitAnswer)
                }
                Button("Submit") { submitAnswer() }
                    .buttonStyle(SealButtonStyle())
                    .disabled(answer.trimmingCharacters(in: .whitespaces).isEmpty || isBusy)
                    .keyboardShortcut(.return)
            }
            .padding(.top, 14)

            HStack {
                Button("Withdraw") { giveUp() }
                    .buttonStyle(PlainActionStyle())
                Spacer()
            }
            .padding(.vertical, 14)
        }
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
        let tint = granted ? Palette.verdigris : Palette.seal

        return VStack(spacing: 0) {
            Spacer()

            Stamp(text: granted ? "Granted" : "Denied", tint: tint)

            Text(reason)
                .font(Face.display(15))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30)
                .padding(.top, 26)

            Spacer()

            Button(granted ? "Proceed" : "Close") {
                blocker.resolveChallenge()
                closeWindow()
            }
            .buttonStyle(OutlineButtonStyle(tint: Palette.ink))
            .keyboardShortcut(.return)
            .padding(.bottom, 26)
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
