import Foundation

/// API keys live in their own file — never in `settings.json`, and never inside
/// the repository working tree unless that file is gitignored.
///
/// The file is resolved in this order:
///   1. `$BLOCKER_SECRETS_PATH`
///   2. `<repo>/secrets.json`, when running from a source checkout (gitignored)
///   3. `~/.config/blocker/secrets.json` — the default for an installed app
///
/// A provider missing from the file falls back to its environment variable, so a
/// shell session or CI run can supply a key without writing anything to disk.
/// Environment keys are never written back out.
final class SecretsStore {
    static let fileName = "secrets.json"

    let url: URL
    private var keys: [AIProvider: String] = [:]

    init(url: URL? = nil) {
        self.url = url ?? Self.resolveURL()
        load()
    }

    // MARK: - Reading

    /// The file's key, or the environment's if the file has none.
    func key(for provider: AIProvider) -> String {
        let stored = keys[provider] ?? ""
        return stored.isEmpty ? environmentKey(for: provider) : stored
    }

    func environmentKey(for provider: AIProvider) -> String {
        ProcessInfo.processInfo.environment[provider.environmentVariable]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// True when this provider works only because of an environment variable.
    /// The UI shows such a key as inherited and refuses to overwrite it silently.
    func isFromEnvironment(_ provider: AIProvider) -> Bool {
        (keys[provider] ?? "").isEmpty && !environmentKey(for: provider).isEmpty
    }

    var storedKeys: [AIProvider: String] { keys }

    /// Where the UI should tell the user their keys ended up.
    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home)
            ? "~" + url.path.dropFirst(home.count)
            : url.path
    }

    // MARK: - Writing

    func replaceAll(with newKeys: [AIProvider: String]) {
        keys = newKeys.filter { !$0.value.isEmpty }
        save()
    }

    /// Folds in keys found elsewhere (an old settings.json) without clobbering
    /// anything already here. Returns true if the file changed.
    @discardableResult
    func merge(_ incoming: [AIProvider: String]) -> Bool {
        var changed = false
        for (provider, key) in incoming where !key.isEmpty {
            guard (keys[provider] ?? "").isEmpty else { continue }
            keys[provider] = key
            changed = true
        }
        if changed { save() }
        return changed
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode(SecretsFile.self, from: data)
        else { return }
        keys = raw.providerKeys.reduce(into: [:]) { result, entry in
            guard let provider = AIProvider(rawValue: entry.key) else { return }
            let trimmed = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            result[provider] = trimmed
        }
    }

    private func save() {
        let file = SecretsFile(
            providerKeys: keys.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value })

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(file) else { return }

        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])

        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        // Written atomically, so the mode has to be reapplied to the new inode.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: url.path)
    }

    // MARK: - Path resolution

    private static func resolveURL() -> URL {
        let env = ProcessInfo.processInfo.environment["BLOCKER_SECRETS_PATH"]
        if let env, !env.isEmpty {
            return URL(fileURLWithPath: (env as NSString).expandingTildeInPath)
        }
        if let repo = repositorySecretsURL() { return repo }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/blocker/\(fileName)")
    }

    /// Only used from a source checkout. In a packaged .app `#filePath` points at
    /// a directory that exists on the build machine and nowhere else, so the
    /// existence check is what keeps this from leaking off the developer's Mac.
    private static func repositorySecretsURL() -> URL? {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Models/
            .deletingLastPathComponent()  // Blocker/
            .deletingLastPathComponent()  // macos/
            .deletingLastPathComponent()  // repo root
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path)
        else { return nil }
        return root.appendingPathComponent(fileName)
    }
}

private struct SecretsFile: Codable {
    var providerKeys: [String: String] = [:]
}
