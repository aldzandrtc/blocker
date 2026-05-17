import SwiftUI
import AppKit

extension Notification.Name {
    static let gatekeeperWindowShouldClose = Notification.Name("gatekeeperWindowShouldClose")
}

@main
struct BlockerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(delegate.settings)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    let blocker: AppBlockerService
    let syncServer: SyncServer

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var gatekeeperWindow: NSWindow?

    override init() {
        blocker = AppBlockerService(store: settings)
        syncServer = SyncServer(store: settings)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if SyncServer.isAlreadyRunning() {
            SyncServer.activateExisting()
            print("Blocker is already running — activating existing instance.")
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return
        }

        NSApp.setActivationPolicy(.accessory)
        setupMenuBar()
        setupNotifications()
        blocker.start()

        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")

        guard syncServer.start() else {

            let alert = NSAlert()
            alert.messageText = "Port \(syncServer.port) is in use"
            alert.informativeText = "Another application is using port \(syncServer.port). Blocker needs this port to sync with the Chrome extension."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        if !hasLaunchedBefore {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, let button = self.statusItem.button else { return }
                self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        blocker.stop()
        syncServer.stop()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "shield.fill",
                accessibilityDescription: "Blocker"
            )
            button.action = #selector(togglePopover)
            button.target = self
        }

        let contentView = ContentView()
            .environment(settings)
            .environment(blocker)

        popover = NSPopover()
        popover.contentSize = NSSize(width: 440, height: 500)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)
        popover.delegate = self
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Notifications

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: .gatekeeperChallengeReady, object: nil, queue: .main
        ) { [weak self] _ in
            self?.showGatekeeperWindow()
        }

        NotificationCenter.default.addObserver(
            forName: .gatekeeperWindowShouldClose, object: nil, queue: .main
        ) { [weak self] _ in
            self?.dismissGatekeeper()
        }
    }

    // MARK: - Gatekeeper Window

    private func showGatekeeperWindow() {
        gatekeeperWindow?.close()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Blocker — Gatekeeper"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: GatekeeperView()
                .environment(settings)
                .environment(blocker)
        )
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        gatekeeperWindow = window
    }

    private func dismissGatekeeper() {
        blocker.resolveChallenge()
        gatekeeperWindow?.close()
        gatekeeperWindow = nil
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow,
           window == gatekeeperWindow {
            blocker.resolveChallenge()
            gatekeeperWindow = nil
        }
    }
}

// MARK: - NSPopoverDelegate

extension AppDelegate: NSPopoverDelegate {
    func popoverWillShow(_ notification: Notification) {
        attachButtonAction()
    }

    func popoverDidClose(_ notification: Notification) {
        attachButtonAction()
    }

    private func attachButtonAction() {
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self
    }
}
