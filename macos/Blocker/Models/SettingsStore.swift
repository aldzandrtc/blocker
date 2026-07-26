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

    /// Model names that no longer resolve, mapped to their replacement.
    /// DeepSeek retired `deepseek-chat`/`deepseek-reasoner` on 2026-07-24.
    static let retiredModels: [String: String] = [
        "deepseek-chat": "deepseek-v4-flash",
        "deepseek-reasoner": "deepseek-v4-pro",
        "claude-sonnet-4-6": "claude-sonnet-5",
        "claude-opus-4-20250514": "claude-opus-5",
        "claude-haiku-4-5-20251001": "claude-haiku-4-5",
    ]

    // MARK: - Provider helpers

    func makeClient() -> AiClient {
        AiClient(apiKey: apiKey, endpoint: apiEndpoint, model: model, provider: selectedProvider)
    }

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

    /// Users type "https://www.youtube.com/" as often as "youtube.com"; the
    /// extension only ever matches against a bare hostname.
    static func normalizeDomain(_ raw: String) -> String {
        var d = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for scheme in ["https://", "http://"] where d.hasPrefix(scheme) {
            d = String(d.dropFirst(scheme.count))
        }
        if let slash = d.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            d = String(d[..<slash])
        }
        if let at = d.lastIndex(of: "@") { d = String(d[d.index(after: at)...]) }
        if let colon = d.firstIndex(of: ":") { d = String(d[..<colon]) }
        if d.hasPrefix("www.") { d = String(d.dropFirst(4)) }
        return d
    }

    func addWebsite(domain: String, label: String) {
        let domain = Self.normalizeDomain(domain)
        guard !domain.isEmpty else { return }
        guard !blockedTargets.contains(where: {
            if case .website(let d, _) = $0.kind { return d == domain }
            return false
        }) else { return }
        blockedTargets.append(BlockedTarget(
            kind: .website(domain: domain, label: label.isEmpty ? domain : label)))
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
        let needle = Self.normalizeDomain(domain)
        return blockedTargets.contains {
            if case .website(let d, _) = $0.kind {
                return d == needle || needle.hasSuffix(".\(d)")
            }
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
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        return dir.appendingPathComponent("settings.json")
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(SettingsData(from: self)) else { return }
        let url = Self.settingsURL()
        guard (try? data.write(to: url)) != nil else { return }
        // This file holds API keys — keep it owner-only.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: url.path)
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.settingsURL()),
              let decoded = try? JSONDecoder().decode(SettingsData.self, from: data) else { return }
        let hadLegacyKey = decoded.apiKey != nil && !(decoded.apiKey?.isEmpty ?? true)
        let hadProviderKeys = !decoded.providerKeys.isEmpty
        let hadRetiredModel = decoded.providerModels.values.contains { Self.retiredModels[$0] != nil }
        decoded.apply(to: self)
        if (hadLegacyKey && !hadProviderKeys) || hadRetiredModel {
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
            store.providerModels[p] = SettingsStore.retiredModels[value] ?? value
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
