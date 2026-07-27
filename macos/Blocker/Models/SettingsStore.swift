import Foundation
import Observation

@Observable
final class SettingsStore {
    /// Keys live in their own gitignored file, never in settings.json.
    @ObservationIgnored let secrets = SecretsStore()

    var selectedProvider: AIProvider = .anthropic
    /// Observable mirror of `secrets`, so the UI updates when a key changes.
    var providerKeys: [AIProvider: String] = [:]
    var providerModels: [AIProvider: String] = [:]
    var providerEndpoints: [AIProvider: String] = [:]

    var profile = StudentProfile()
    var blockedTargets: [BlockedTarget] = []
    var problemHistory: [ProblemRecord] = []
    var activity: [DailyActivity] = []

    /// Target id → the moment a new attempt is allowed. Persisted, because
    /// quitting and relaunching the app would otherwise clear every cooldown.
    var cooldownUntil: [String: Date] = [:]

    // Extension detection (session-only, not persisted)
    var lastExtensionContact: Date? = nil
    var extensionConnected: Bool {
        guard let last = lastExtensionContact else { return false }
        return Date().timeIntervalSince(last) < 300 // seen within 5 min
    }

    // Computed from selected provider
    var apiKey: String {
        get { key(for: selectedProvider) }
        set { providerKeys[selectedProvider] = newValue }
    }

    /// The stored key, or the provider's environment variable if there is none.
    func key(for provider: AIProvider) -> String {
        let stored = providerKeys[provider] ?? ""
        return stored.isEmpty ? secrets.environmentKey(for: provider) : stored
    }

    func isInheritedFromEnvironment(_ provider: AIProvider) -> Bool {
        (providerKeys[provider] ?? "").isEmpty && !secrets.environmentKey(for: provider).isEmpty
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
        "claude-sonnet-4-5": "claude-sonnet-5",
        "claude-opus-4-6": "claude-opus-5",
        "claude-opus-4-5": "claude-opus-5",
        "claude-opus-4-20250514": "claude-opus-5",
        "claude-3-7-sonnet-20250219": "claude-sonnet-5",
        "claude-3-5-haiku-20241022": "claude-haiku-4-5",
    ]

    // MARK: - Provider helpers

    func makeClient() -> AiClient {
        AiClient(apiKey: apiKey, endpoint: apiEndpoint, model: model, provider: selectedProvider)
    }

    func isProviderConfigured(_ provider: AIProvider) -> Bool {
        !key(for: provider).isEmpty
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

    // MARK: - Cooldown
    //
    // The cooldown is what stops a failed attempt from being retried instantly
    // until something gets through. It was a settings field with nothing behind
    // it until now, so both gatekeepers consult it before opening a challenge.

    func startCooldown(for id: String) {
        let minutes = profile.cooldownMinutes
        guard minutes > 0 else { return }
        cooldownUntil[id] = Date().addingTimeInterval(TimeInterval(minutes * 60))
        save()
    }

    /// Seconds left before `id` may be challenged again; 0 when it is free.
    func cooldownRemaining(for id: String) -> Int {
        guard let until = cooldownUntil[id] else { return 0 }
        let remaining = until.timeIntervalSinceNow
        guard remaining > 0 else {
            cooldownUntil.removeValue(forKey: id)
            return 0
        }
        return Int(remaining.rounded(.up))
    }

    func clearCooldown(for id: String) {
        guard cooldownUntil.removeValue(forKey: id) != nil else { return }
        save()
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
        recordActivity(solved: correct)
        save()
    }

    // MARK: - Daily activity

    private func recordActivity(solved: Bool) {
        let today = DailyActivity.dayKey(for: Date())
        if let i = activity.firstIndex(where: { $0.day == today }) {
            activity[i].record(solved: solved)
        } else {
            var entry = DailyActivity(day: today)
            entry.record(solved: solved)
            activity.append(entry)
        }
        // A year of daily rows is all the streak and heatmap ever look at.
        if activity.count > 400 {
            activity = Array(activity.sorted { $0.day < $1.day }.suffix(400))
        }
    }

    /// Consecutive days up to today with at least one correct answer.
    var currentStreak: Int {
        let solvedDays = Set(activity.filter { $0.solved > 0 }.map(\.day))
        guard !solvedDays.isEmpty else { return 0 }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var cursor = Date()
        // Today not being done yet shouldn't read as a broken streak.
        if !solvedDays.contains(DailyActivity.dayKey(for: cursor)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  solvedDays.contains(DailyActivity.dayKey(for: yesterday)) else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        while solvedDays.contains(DailyActivity.dayKey(for: cursor)) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    var solvedToday: Int {
        activity.first { $0.day == DailyActivity.dayKey(for: Date()) }?.solved ?? 0
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
        secrets.replaceAll(with: providerKeys)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(SettingsData(from: self)) else { return }
        let url = Self.settingsURL()
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: url.path)
    }

    private func load() {
        providerKeys = secrets.storedKeys

        guard let data = try? Data(contentsOf: Self.settingsURL()),
              let decoded = try? JSONDecoder().decode(SettingsData.self, from: data) else { return }

        // Keys used to live in settings.json. Move any we find into secrets.json
        // and rewrite settings.json without them.
        var legacyKeys: [AIProvider: String] = [:]
        for (raw, value) in decoded.providerKeys {
            guard let provider = AIProvider(rawValue: raw) else { continue }
            legacyKeys[provider] = value
        }
        if let oldKey = decoded.apiKey, !oldKey.isEmpty, legacyKeys[.anthropic] == nil {
            legacyKeys[.anthropic] = oldKey
        }
        let migratedKeys = secrets.merge(legacyKeys)
        if migratedKeys { providerKeys = secrets.storedKeys }

        let hadRetiredModel = decoded.providerModels.values.contains { Self.retiredModels[$0] != nil }
        decoded.apply(to: self)
        if migratedKeys || !legacyKeys.isEmpty || hadRetiredModel {
            save() // persist migration; strips keys out of settings.json
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
    var activity: [DailyActivity] = []
    var cooldownUntil: [String: Date] = [:]

    enum CodingKeys: String, CodingKey {
        case apiKey, apiEndpoint, model, selectedProvider
        case providerKeys, providerModels, providerEndpoints
        case profile, blockedTargets, problemHistory, activity, cooldownUntil
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
        activity = try c.decodeIfPresent([DailyActivity].self, forKey: .activity) ?? []
        cooldownUntil = try c.decodeIfPresent([String: Date].self, forKey: .cooldownUntil) ?? [:]
    }

    init(from store: SettingsStore) {
        apiKey = nil
        apiEndpoint = nil
        model = nil
        selectedProvider = store.selectedProvider
        providerKeys = [:] // keys live in secrets.json, never here
        providerModels = store.providerModels.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value }
        providerEndpoints = store.providerEndpoints.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value }
        profile = store.profile
        blockedTargets = store.blockedTargets
        problemHistory = store.problemHistory
        activity = store.activity
        // Expired entries would otherwise pile up in the file forever.
        cooldownUntil = store.cooldownUntil.filter { $0.value > Date() }
    }

    /// Keys are deliberately not applied here — `SettingsStore.load()` owns them,
    /// because they come from secrets.json rather than this file.
    func apply(to store: SettingsStore) {
        if let oldModel = model, !oldModel.isEmpty, providerModels.isEmpty {
            store.providerModels[.anthropic] = oldModel
        }

        store.selectedProvider = selectedProvider
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
        store.activity = activity
        store.cooldownUntil = cooldownUntil
    }
}
