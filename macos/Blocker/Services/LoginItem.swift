import Foundation
import ServiceManagement

/// Launch-at-login, so the blocker is running before the first temptation of the
/// day rather than after the student remembers to start it.
///
/// `SMAppService.mainApp` only works for a bundled, signed .app — running via
/// `swift run` there is no bundle to register, so the toggle reports itself as
/// unavailable instead of failing at the user.
enum LoginItem {
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    static var isEnabled: Bool {
        guard isAvailable else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// Returns a message when the change could not be made, nil on success.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        guard isAvailable else {
            return "Launch at login needs the packaged app — run `make app`, then open Blocker from /Applications."
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            // The most common cause is the login-item approval being switched
            // off in System Settings, which the app cannot override.
            return "macOS refused the change: \(error.localizedDescription). Check Login Items in System Settings."
        }
    }
}
