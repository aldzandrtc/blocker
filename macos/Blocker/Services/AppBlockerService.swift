import Foundation
import AppKit
import Observation

extension Notification.Name {
    static let gatekeeperChallengeReady = Notification.Name("gatekeeperChallengeReady")
}

struct GatekeeperChallenge: Identifiable {
    let id = UUID()
    let bundleID: String
    let appName: String
    let pid: Int32
    let category: BlockedTarget.Category

    enum Phase: Equatable {
        case starting
        case judgePrompt
        case judging
        case problemPrompt(GeneratedProblem)
        case verifying(GeneratedProblem)
        case allowed(String)
        case denied(String)
    }

    var phase: Phase = .starting
}

@MainActor
@Observable
final class AppBlockerService {
    private let store: SettingsStore
    var pendingChallenge: GatekeeperChallenge?
    private var sessionAllowlist: [String: Date] = [:]
    private var launchObserver: NSObjectProtocol?

    init(store: SettingsStore) {
        self.store = store
    }

    // MARK: - Start / Stop

    func start() {
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.handleAppLaunch(note) }
        }
    }

    func stop() {
        if let observer = launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            launchObserver = nil
        }
        resolveChallenge()
    }

    // MARK: - App Launch Handling

    private func handleAppLaunch(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
              let bundleID = app.bundleIdentifier,
              store.isOnBlocklist(bundleID: bundleID)
        else { return }

        if isSessionAllowed(bundleID) { return }

        let pid = app.processIdentifier
        let name = app.localizedName ?? bundleID

        kill(pid, SIGSTOP)

        let category = store.categoryFor(bundleID: bundleID) ?? .regular
        var challenge = GatekeeperChallenge(
            bundleID: bundleID, appName: name, pid: pid, category: category
        )

        if category == .strict {
            challenge.phase = .judgePrompt
            pendingChallenge = challenge
            postReady(challenge)
        } else {
            // Show the window right away — generating a problem takes seconds, and
            // the app is already frozen, so silence here just looks like a hang.
            pendingChallenge = challenge
            postReady(challenge)
            Task { await generateProblem(for: challenge) }
        }
    }

    private func generateProblem(for challenge: GatekeeperChallenge) async {
        let generator = ProblemGenerator(client: makeClient(), store: store)

        do {
            let problem = try await generator.generate()
            guard var current = pendingChallenge, current.id == challenge.id else { return }
            current.phase = .problemPrompt(problem)
            pendingChallenge = current
        } catch let error as AiError {
            guard var current = pendingChallenge, current.id == challenge.id else { return }
            current.phase = .denied(error.message)
            pendingChallenge = current
        } catch {
            guard var current = pendingChallenge, current.id == challenge.id else { return }
            current.phase = .denied("Could not generate a problem.")
            pendingChallenge = current
        }
    }

    // MARK: - Gatekeeper Actions

    func judge(argument: String) async {
        guard var challenge = pendingChallenge else { return }
        challenge.phase = .judging
        pendingChallenge = challenge

        let judge = BlocklistJudge(client: makeClient())
        let result = await judge.judge(appName: challenge.appName, argument: argument)

        guard var current = pendingChallenge, current.id == challenge.id else { return }
        if result.allowed {
            current.phase = .allowed(result.reason)
            allow(pid: current.pid, bundleID: current.bundleID)
        } else {
            current.phase = .denied(result.reason)
        }
        pendingChallenge = current
    }

    func verifyAnswer(_ answer: String) async {
        guard var challenge = pendingChallenge,
              case .problemPrompt(let problem) = challenge.phase
        else { return }

        challenge.phase = .verifying(problem)
        pendingChallenge = challenge

        let generator = ProblemGenerator(client: makeClient(), store: store)
        let result = await generator.verify(problem: problem, studentAnswer: answer)

        guard var current = pendingChallenge, current.id == challenge.id else { return }
        if result.correct {
            current.phase = .allowed("Correct!")
            allow(pid: current.pid, bundleID: current.bundleID)
            store.recordProblem(topic: problem.topic, correct: true)
        } else {
            current.phase = .denied(result.explanation)
            store.recordProblem(topic: problem.topic, correct: false)
        }
        pendingChallenge = current
    }

    func resolveChallenge() {
        guard let challenge = pendingChallenge else { return }
        switch challenge.phase {
        case .allowed:
            break // already resumed by allow()
        default:
            // Denied, or the user gave up / closed the window. Either way the app
            // is still SIGSTOPped — leaving it that way strands a frozen process.
            kill(challenge.pid, SIGKILL)
        }
        pendingChallenge = nil
    }

    // MARK: - Helpers

    private func allow(pid: Int32, bundleID: String) {
        kill(pid, SIGCONT)
        sessionAllowlist[bundleID] = Date()
    }

    private func isSessionAllowed(_ bundleID: String) -> Bool {
        guard let allowedAt = sessionAllowlist[bundleID] else { return false }
        let duration = TimeInterval(store.profile.unblockDurationMinutes * 60)
        return Date().timeIntervalSince(allowedAt) < duration
    }

    private func makeClient() -> AiClient {
        AiClient(apiKey: store.apiKey, endpoint: store.apiEndpoint, model: store.model, provider: store.selectedProvider)
    }

    private func postReady(_ challenge: GatekeeperChallenge) {
        NotificationCenter.default.post(name: .gatekeeperChallengeReady,
                                        object: challenge)
    }
}
