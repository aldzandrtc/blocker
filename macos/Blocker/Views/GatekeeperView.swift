import SwiftUI

struct GatekeeperView: View {
    @Environment(AppBlockerService.self) private var blocker

    @State private var argument: String = ""
    @State private var answer: String = ""
    @State private var isBusy = false

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
        }
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

    // MARK: - Problem

    private func problemView(problem: GeneratedProblem) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "function")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("Academic Problem")
                .font(.title2)

            Text(.init(problem.problem))
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

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
