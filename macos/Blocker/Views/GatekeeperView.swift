import SwiftUI

struct GatekeeperView: View {
    @Environment(AppBlockerService.self) private var blocker

    @State private var argument: String = ""
    @State private var answer: String = ""
    @State private var isBusy = false
    @State private var timeRemaining = 120
    @State private var problemHeight: CGFloat = 100

    private let judgeTimeLimit = 120

    var body: some View {
        if let challenge = blocker.pendingChallenge {
            VStack(spacing: 16) {
                Text("Gatekeeper")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                switch challenge.phase {
                case .starting:
                    Spacer()
                    ProgressView("Preparing challenge...")
                    Spacer()

                case .judgePrompt:
                    judgeView(challenge: challenge)

                case .judging:
                    Spacer()
                    ProgressView("Judging your argument...")
                    Text("The AI is evaluating your case...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()

                case .problemPrompt(let problem):
                    problemView(problem: problem)

                case .verifying:
                    Spacer()
                    ProgressView("Verifying your answer...")
                    Text("Checking against the expected answer...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()

                case .allowed(let reason):
                    resultView(success: true, message: reason)

                case .denied(let reason):
                    resultView(success: false, message: reason)
                }
            }
            .padding()
            .frame(width: 480, height: 360)
            .onReceive(
                Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            ) { _ in
                tick()
            }
        }
    }

    private func tick() {
        guard let challenge = blocker.pendingChallenge else { return }
        switch challenge.phase {
        case .judgePrompt:
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                blocker.resolveChallenge()
                closeWindow()
            }
        default:
            break
        }
    }

    private var timerColor: Color {
        timeRemaining <= 30 ? .red : .secondary
    }

    // MARK: - Judge

    private func judgeView(challenge: GatekeeperChallenge) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.mind.and.body")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("Convince the Judge")
                .font(.title2)

            Text("You tried to open **\(challenge.appName)**.\nThe default answer is DENY. Make your case:")
                .multilineTextAlignment(.center)
                .font(.body)

            Text(timeText)
                .font(.caption)
                .foregroundStyle(timerColor)

            TextEditor(text: $argument)
                .frame(height: 100)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.secondary.opacity(0.3), lineWidth: 1)
                }
                .disabled(isBusy)

            HStack(spacing: 16) {
                Button("Give Up") {
                    blocker.resolveChallenge()
                    closeWindow()
                }

                Button {
                    isBusy = true
                    Task {
                        await blocker.judge(argument: argument)
                        isBusy = false
                    }
                } label: {
                    Text("Submit Argument")
                }
                .disabled(argument.trimmingCharacters(in: .whitespaces).isEmpty || isBusy)
                .keyboardShortcut(.return)
            }
        }
    }

    private var timeText: String {
        let m = timeRemaining / 60
        let s = timeRemaining % 60
        if timeRemaining <= 0 {
            return "Time's up — access denied"
        }
        return "Time remaining: \(m):\(String(format: "%02d", s))"
    }

    // MARK: - Problem

    private func problemView(problem: GeneratedProblem) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "function")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("Academic Problem")
                .font(.title2)

            LaTeXWebView(text: problem.problem, dynamicHeight: $problemHeight)
                .frame(height: max(problemHeight, 60))

            TextField("Your answer", text: $answer)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .disabled(isBusy)

            Text("Topic: \(problem.topic)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Button("Give Up") {
                    blocker.resolveChallenge()
                    closeWindow()
                }

                Button {
                    isBusy = true
                    Task {
                        await blocker.verifyAnswer(answer)
                        isBusy = false
                    }
                } label: {
                    Text("Submit Answer")
                }
                .disabled(answer.trimmingCharacters(in: .whitespaces).isEmpty || isBusy)
                .keyboardShortcut(.return)
            }
        }
    }

    // MARK: - Result

    private func resultView(success: Bool, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(success ? .green : .red)

            Text(success ? "Access Granted" : "Access Denied")
                .font(.title2)

            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Button("Close") {
                blocker.resolveChallenge()
                closeWindow()
            }
            .keyboardShortcut(.return)
        }
    }

    private func closeWindow() {
        NotificationCenter.default.post(name: .gatekeeperWindowShouldClose, object: nil)
    }
}

// MARK: - Judge sheet for blocklist removal

struct RemoveGatekeeperSheet: View {
    let target: BlockedTarget
    let settings: SettingsStore
    @Binding var isPresented: Bool

    @State private var argument: String = ""
    @State private var isBusy = false
    @State private var result: (allowed: Bool, reason: String)?
    @State private var timeRemaining = 120

    var body: some View {
        VStack(spacing: 16) {
            if let result = result {
                VStack(spacing: 12) {
                    Image(systemName: result.allowed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(result.allowed ? .green : .red)
                    Text(result.allowed ? "Removed" : "Denied")
                        .font(.title2)
                    Text(result.reason)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button(result.allowed ? "Done" : "Close") {
                        isPresented = false
                    }
                    .keyboardShortcut(.return)
                }
            } else {
                Image(systemName: "figure.mind.and.body")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)

                Text("Convince the Judge")
                    .font(.title2)

                Text("You want to remove **\(target.displayName)** from the blocklist. Explain why:")
                    .font(.body)
                    .multilineTextAlignment(.center)

                Text(timeRemainingText)
                    .font(.caption)
                    .foregroundStyle(timeRemaining <= 30 ? .red : .secondary)

                TextEditor(text: $argument)
                    .frame(height: 80)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.secondary.opacity(0.3), lineWidth: 1)
                    }
                    .disabled(isBusy)

                HStack(spacing: 16) {
                    Button("Cancel") { isPresented = false }
                    Button("Submit") {
                        submit()
                    }
                    .disabled(argument.trimmingCharacters(in: .whitespaces).isEmpty || isBusy)
                    .keyboardShortcut(.return)
                }
            }
        }
        .padding()
        .frame(width: 440, height: 320)
        .onReceive(
            Timer.publish(every: 1, on: .main, in: .common).autoconnect()
        ) { _ in
            if result == nil, timeRemaining > 0 {
                timeRemaining -= 1
            } else if result == nil, timeRemaining <= 0 {
                result = (false, "Time expired — removal denied automatically.")
            }
        }
    }

    private var timeRemainingText: String {
        if timeRemaining <= 0 { return "Time's up" }
        return "Time remaining: \(timeRemaining / 60):\(String(format: "%02d", timeRemaining % 60))"
    }

    private func submit() {
        isBusy = true
        let client = AiClient(
            apiKey: settings.apiKey,
            endpoint: settings.apiEndpoint,
            model: settings.model,
            provider: settings.selectedProvider
        )
        let judge = BlocklistJudge(client: client)
        Task {
            let judgment = await judge.judge(
                appName: target.displayName,
                argument: "I want to remove \(target.displayName) from my blocklist because: \(argument)"
            )
            result = (judgment.allowed, judgment.reason)
            if judgment.allowed {
                settings.removeTarget(target.id)
            }
            isBusy = false
        }
    }
}
