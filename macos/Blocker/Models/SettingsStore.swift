import Foundation
import Observation

@Observable
final class SettingsStore {
    var selectedProvider: AIProvider = .anthropic
    var providerKeys: [AIProvider: String] = [:]
    var providerModels: [AIProvider: String] = [:]
    var providerEndpoints: [AIProvider: String] = [:]

    var profile = StudentProfile()
    var blockedTargets: [BlockedTarget] = []
    var problemHistory: [ProblemRecord] = []

    // Extension detection (session-only, not persisted)
    var lastExtensionContact: Date? = nil
    var extensionConnected: Bool {
        guard let last = lastExtensionContact else { return false }
        return Date().timeIntervalSince(last) < 300 // seen within 5 min
    }

    // Computed from selected provider
    var apiKey: String {
        get { providerKeys[selectedProvider] ?? "" }
        set { providerKeys[selectedProvider] = newValue }
    }

    var apiEndpoint: String {
        get { providerEndpoints[selectedProvider] ?? selectedProvider.defaultEndpoint }
        set { providerEndpoints[selectedProvider] = newValue }
    }

    var model: String {
        get { providerModels[selectedProvider] ?? selectedProvider.defaultModel }
        set { providerModels[selectedProvider] = newValue }
    }

    var hasApiKey: Bool { !apiKey.isEmpty }

    init() { load() }

    // MARK: - Provider helpers

    func isProviderConfigured(_ provider: AIProvider) -> Bool {
        !(providerKeys[provider] ?? "").isEmpty
    }

    func effectiveModel(for provider: AIProvider) -> String {
        providerModels[provider] ?? provider.defaultModel
    }

    // MARK: - Blocklist

    func addApp(bundleID: String, name: String, path: String) {
        guard !blockedTargets.contains(where: {
            if case .app(let id, _, _) = $0.kind { return id == bundleID }
            return false
        }) else { return }
        blockedTargets.append(BlockedTarget(
            kind: .app(bundleID: bundleID, name: name, path: path)))
        save()
    }

    func addWebsite(domain: String, label: String) {
        guard !blockedTargets.contains(where: {
            if case .website(let d, _) = $0.kind { return d == domain }
            return false
        }) else { return }
        blockedTargets.append(BlockedTarget(
            kind: .website(domain: domain, label: label)))
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
            if case .app(let id, _, _) = $0.kind { return id == bundleID }
            return false
        }
    }

    func isOnBlocklist(domain: String) -> Bool {
        blockedTargets.contains {
            if case .website(let d, _) = $0.kind { return d == domain }
            return false
        }
    }

    func categoryFor(bundleID: String) -> BlockedTarget.Category? {
        for t in blockedTargets {
            if case .app(let id, _, _) = t.kind, id == bundleID { return t.category }
        }
        return nil
    }

    var websiteTargets: [BlockedTarget] {
        blockedTargets.filter {
            if case .website = $0.kind { return true }
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
        let hadLegacyKey = decoded.apiKey != nil && !(decoded.apiKey?.isEmpty ?? true)
        let hadProviderKeys = !decoded.providerKeys.isEmpty
        decoded.apply(to: self)
        if hadLegacyKey && !hadProviderKeys {
            save() // persist migration to new format
        }
    }
}

// Codable snapshot for persistence.
// Uses String-keyed dicts internally so JSON is readable objects, not flat arrays.
private struct SettingsData: Codable {
    var apiKey: String?
    var apiEndpoint: String?
    var model: String?
    var selectedProvider: AIProvider = .anthropic
    var providerKeys: [String: String] = [:]
    var providerModels: [String: String] = [:]
    var providerEndpoints: [String: String] = [:]

    var profile: StudentProfile
    var blockedTargets: [BlockedTarget]
    var problemHistory: [ProblemRecord]

    enum CodingKeys: String, CodingKey {
        case apiKey, apiEndpoint, model, selectedProvider
        case providerKeys, providerModels, providerEndpoints
        case profile, blockedTargets, problemHistory
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey)
        apiEndpoint = try c.decodeIfPresent(String.self, forKey: .apiEndpoint)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        selectedProvider = try c.decodeIfPresent(AIProvider.self, forKey: .selectedProvider) ?? .anthropic
        providerKeys = try c.decodeIfPresent([String: String].self, forKey: .providerKeys) ?? [:]
        providerModels = try c.decodeIfPresent([String: String].self, forKey: .providerModels) ?? [:]
        providerEndpoints = try c.decodeIfPresent([String: String].self, forKey: .providerEndpoints) ?? [:]
        profile = try c.decode(StudentProfile.self, forKey: .profile)
        blockedTargets = try c.decode([BlockedTarget].self, forKey: .blockedTargets)
        problemHistory = try c.decode([ProblemRecord].self, forKey: .problemHistory)
    }

    init(from store: SettingsStore) {
        apiKey = nil
        apiEndpoint = nil
        model = nil
        selectedProvider = store.selectedProvider
        providerKeys = store.providerKeys.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value }
        providerModels = store.providerModels.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value }
        providerEndpoints = store.providerEndpoints.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value }
        profile = store.profile
        blockedTargets = store.blockedTargets
        problemHistory = store.problemHistory
    }

    func apply(to store: SettingsStore) {
        // Migration: old-format apiKey → providerKeys
        if let oldKey = apiKey, !oldKey.isEmpty, providerKeys.isEmpty {
            store.providerKeys[.anthropic] = oldKey
        }
        if let oldModel = model, !oldModel.isEmpty, providerModels.isEmpty {
            store.providerModels[.anthropic] = oldModel
        }

        store.selectedProvider = selectedProvider
        for (key, value) in providerKeys {
            guard let p = AIProvider(rawValue: key) else { continue }
            store.providerKeys[p] = value
        }
        for (key, value) in providerModels {
            guard let p = AIProvider(rawValue: key) else { continue }
            store.providerModels[p] = value
        }
        for (key, value) in providerEndpoints {
            guard let p = AIProvider(rawValue: key) else { continue }
            store.providerEndpoints[p] = value
        }
        store.profile = profile
        store.blockedTargets = blockedTargets
        store.problemHistory = problemHistory
    }
}
