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

    /// How this app came to be gated, which decides what denial does to it.
    enum Trigger {
        /// Launched just now — nothing is open in it, so quitting is safe.
        case launch
        /// Already running and brought to the front. It may hold unsaved work,
        /// so denial hides it instead of quitting it.
        case activation
    }

    let trigger: Trigger

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

/// An app the student has already earned their way into, and for how long.
struct ActiveGrant: Identifiable {
    let bundleID: String
    let name: String
    let expires: Date

    var id: String { bundleID }
    var secondsRemaining: Int { max(0, Int(expires.timeIntervalSinceNow.rounded(.up))) }
}

@MainActor
@Observable
final class AppBlockerService {
    private let store: SettingsStore
    var pendingChallenge: GatekeeperChallenge?

    private var sessionAllowlist: [String: Date] = [:]
    private var launchObserver: NSObjectProtocol?
    private var activateObserver: NSObjectProtocol?

    init(store: SettingsStore) {
        self.store = store
    }

    // MARK: - Start / Stop

    func start() {
        let center = NSWorkspace.shared.notificationCenter

        launchObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.handleAppEvent(note, trigger: .launch) }
        }

        // Fresh launches were the only thing gated before, so an app already
        // running when Blocker started — or left running from before a grant
        // expired — was effectively unblocked. Activation is the moment the
        // student actually goes to use it, so gate there too.
        activateObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.handleAppEvent(note, trigger: .activation) }
        }
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in [launchObserver, activateObserver].compactMap({ $0 }) {
            center.removeObserver(observer)
        }
        launchObserver = nil
        activateObserver = nil
        resolveChallenge()
    }

    // MARK: - Grants

    var activeGrants: [ActiveGrant] {
        let duration = TimeInterval(store.profile.unblockDurationMinutes * 60)
        return sessionAllowlist.compactMap { bundleID, allowedAt in
            let expires = allowedAt.addingTimeInterval(duration)
            guard expires > Date() else { return nil }
            return ActiveGrant(bundleID: bundleID, name: displayName(for: bundleID), expires: expires)
        }
        .sorted { $0.expires < $1.expires }
    }

    /// Hand the leave back early. Tightening never needs the judge's approval.
    func revokeGrant(_ bundleID: String) {
        sessionAllowlist.removeValue(forKey: bundleID)
    }

    private func displayName(for bundleID: String) -> String {
        for target in store.blockedTargets {
            if case .app(let id, let name, _) = target.kind, id == bundleID {
                return name.isEmpty ? bundleID : name
            }
        }
        return bundleID
    }

    // MARK: - App event handling

    private func handleAppEvent(_ notification: Notification, trigger: GatekeeperChallenge.Trigger) {
        guard pendingChallenge == nil else { return } // one challenge at a time
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier,
              store.isOnBlocklist(bundleID: bundleID),
              !isSessionAllowed(bundleID)
        else { return }

        let pid = app.processIdentifier
        let name = app.localizedName ?? displayName(for: bundleID)

        // Freezing is reversible and costs nothing, so it happens for both
        // triggers — it stops the student from using the app behind the window.
        kill(pid, SIGSTOP)

        let category = store.categoryFor(bundleID: bundleID) ?? .regular
        var challenge = GatekeeperChallenge(
            bundleID: bundleID, appName: name, pid: pid,
            category: category, trigger: trigger
        )

        // The cooldown existed as a setting with nothing enforcing it. Waiting it
        // out is the whole point, so no challenge is offered until it elapses.
        let waiting = store.cooldownRemaining(for: "app-\(bundleID)")
        if waiting > 0 {
            challenge.phase = .denied("Cooling down. \(Self.formatWait(waiting)) before \(name) can be challenged again.")
            pendingChallenge = challenge
            postReady(challenge)
            return
        }

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

    /// Also called from the sync server's connection queue, so it must not be
    /// pinned to the main actor.
    nonisolated static func formatWait(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let minutes = Int((Double(seconds) / 60).rounded(.up))
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
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
            store.startCooldown(for: "app-\(current.bundleID)")
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
        } else {
            current.phase = .denied(result.explanation)
            store.startCooldown(for: "app-\(current.bundleID)")
        }
        store.recordProblem(topic: problem.topic, correct: result.correct)
        pendingChallenge = current
    }

    func resolveChallenge() {
        guard let challenge = pendingChallenge else { return }
        pendingChallenge = nil

        switch challenge.phase {
        case .allowed:
            break // already resumed by allow()
        default:
            // Denied, or the student gave up. Either way the app is still
            // SIGSTOPped, and leaving it that way strands a frozen process.
            deny(challenge)
        }
    }

    // MARK: - Helpers

    private func allow(pid: Int32, bundleID: String) {
        kill(pid, SIGCONT)
        sessionAllowlist[bundleID] = Date()
        store.clearCooldown(for: "app-\(bundleID)")
    }

    /// Shutting the app out without destroying anything in it. The old path sent
    /// SIGKILL, which discards unsaved work — fine for an app that had just
    /// launched, but not for one the student had been using all afternoon.
    private func deny(_ challenge: GatekeeperChallenge) {
        // A stopped process cannot run its own quit handlers, so it has to be
        // resumed before it can be asked to do anything.
        kill(challenge.pid, SIGCONT)

        guard let app = NSRunningApplication(processIdentifier: challenge.pid),
              !app.isTerminated else { return }

        switch challenge.trigger {
        case .activation:
            // It was already running: hide it and step in front. Never quit it.
            app.hide()
            NSApp.activate(ignoringOtherApps: true)
        case .launch:
            // It only just opened, so a normal quit loses nothing. Ask first and
            // escalate only if it ignores the request.
            app.terminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if !app.isTerminated { app.forceTerminate() }
            }
        }
    }

    private func isSessionAllowed(_ bundleID: String) -> Bool {
        guard let allowedAt = sessionAllowlist[bundleID] else { return false }
        let duration = TimeInterval(store.profile.unblockDurationMinutes * 60)
        guard Date().timeIntervalSince(allowedAt) < duration else {
            sessionAllowlist.removeValue(forKey: bundleID)
            return false
        }
        return true
    }

    private func makeClient() -> AiClient {
        store.makeClient()
    }

    private func postReady(_ challenge: GatekeeperChallenge) {
        NotificationCenter.default.post(name: .gatekeeperChallengeReady,
                                        object: challenge)
    }
}
