import Foundation
import Observation

@Observable
final class SettingsStore {
    var apiKey: String = ""
    var apiEndpoint: String = "https://api.anthropic.com/v1/messages"
    var model: String = "claude-sonnet-4-6"
    var profile = StudentProfile()
    var blockedTargets: [BlockedTarget] = []
    var problemHistory: [ProblemRecord] = []

    var hasApiKey: Bool { !apiKey.isEmpty }

    // MARK: - Init

    init() { load() }

    // MARK: - Blocklist

    func addApp(bundleID: String, name: String, path: String) {
        guard !blockedTargets.contains(where: {
            if case .app(let id, _, _) = $0 { return id == bundleID }
            return false
        }) else { return }
        blockedTargets.append(.app(bundleID: bundleID, name: name, path: path))
        save()
    }

    func addWebsite(domain: String, label: String) {
        guard !blockedTargets.contains(where: {
            if case .website(let d, _) = $0 { return d == domain }
            return false
        }) else { return }
        blockedTargets.append(.website(domain: domain, label: label))
        save()
    }

    func removeTarget(_ id: String) {
        blockedTargets.removeAll { $0.id == id }
        save()
    }

    func toggleCategory(_ id: String) {
        guard let i = blockedTargets.firstIndex(where: { $0.id == id }) else { return }
        blockedTargets[i].category = blockedTargets[i].category == .strict ? .regular : .strict
        save()
    }

    func setCategory(_ id: String, _ cat: BlockedTarget.Category) {
        guard let i = blockedTargets.firstIndex(where: { $0.id == id }) else { return }
        blockedTargets[i].category = cat
        save()
    }

    func isOnBlocklist(bundleID: String) -> Bool {
        blockedTargets.contains {
            if case .app(let id, _, _) = $0 { return id == bundleID }
            return false
        }
    }

    func isOnBlocklist(domain: String) -> Bool {
        blockedTargets.contains {
            if case .website(let d, _) = $0 { return d == domain }
            return false
        }
    }

    func categoryFor(bundleID: String) -> BlockedTarget.Category? {
        for t in blockedTargets {
            if case .app(let id, _, _) = t, id == bundleID { return t.category }
        }
        return nil
    }

    // Websites for Chrome extension sync
    var websiteTargets: [BlockedTarget] {
        blockedTargets.filter {
            if case .website = $0 { return true }
            return false
        }
    }

    // MARK: - Problem History

    func recordProblem(topic: String, correct: Bool) {
        if let i = problemHistory.firstIndex(where: { $0.topic == topic }) {
            problemHistory[i].record(correct: correct)
        } else {
            var record = ProblemRecord(topic: topic)
            record.record(correct: correct)
            problemHistory.append(record)
        }
        save()
    }

    // MARK: - Persistence

    private static func settingsURL() -> URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/blocker")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(SettingsData(from: self)) else { return }
        try? data.write(to: Self.settingsURL())
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.settingsURL()),
              let decoded = try? JSONDecoder().decode(SettingsData.self, from: data) else { return }
        decoded.apply(to: self)
    }
}

// Codable snapshot for persistence
private struct SettingsData: Codable {
    var apiKey: String
    var apiEndpoint: String
    var model: String
    var profile: StudentProfile
    var blockedTargets: [BlockedTarget]
    var problemHistory: [ProblemRecord]

    init(from store: SettingsStore) {
        apiKey = store.apiKey
        apiEndpoint = store.apiEndpoint
        model = store.model
        profile = store.profile
        blockedTargets = store.blockedTargets
        problemHistory = store.problemHistory
    }

    func apply(to store: SettingsStore) {
        store.apiKey = apiKey
        store.apiEndpoint = apiEndpoint
        store.model = model
        store.profile = profile
        store.blockedTargets = blockedTargets
        store.problemHistory = problemHistory
    }
}
