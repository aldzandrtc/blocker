import SwiftUI
import AppKit

struct BlocklistView: View {
    @Environment(SettingsStore.self) private var settings

    @State private var showingAddSheet = false
    @State private var addTab: AddTab = .website
    @State private var targetToRemove: BlockedTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Blocklist")
                    .font(.title2)
                Spacer()
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            .padding(.horizontal)

            if settings.blockedTargets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "hand.raised.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Nothing blocked yet")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(settings.blockedTargets) { target in
                        HStack {
                            Image(systemName: categoryIcon(target))
                            VStack(alignment: .leading) {
                                Text(target.displayName)
                                    .font(.body)
                                Text(subtitle(target))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Menu {
                                Button {
                                    settings.toggleCategory(target.id)
                                } label: {
                                    Text(target.category == .strict ? "Make Regular" : "Make Strict")
                                }
                                Button(role: .destructive) {
                                    targetToRemove = target
                                } label: {
                                    Text("Remove")
                                }
                            } label: {
                                Text(target.category == .strict ? "Strict" : "Regular")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(target.category == .strict ? Color.red.opacity(0.2) : Color.blue.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                            .menuStyle(.borderlessButton)
                            .frame(width: 80)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showingAddSheet) {
            AddTargetView(settings: settings, isPresented: $showingAddSheet)
                .frame(width: 400, height: 300)
        }
        .sheet(item: $targetToRemove) { target in
            RemoveGatekeeperSheet(
                target: target,
                settings: settings,
                isPresented: Binding(
                    get: { targetToRemove != nil },
                    set: { if !$0 { targetToRemove = nil } }
                )
            )
        }
    }

    private func categoryIcon(_ target: BlockedTarget) -> String {
        switch target.kind {
        case .app:     return "app.fill"
        case .website: return "globe"
        }
    }

    private func subtitle(_ target: BlockedTarget) -> String {
        switch target.kind {
        case .app(let id, _, _):     return id
        case .website(let domain, _): return domain
        }
    }
}

private enum AddTab: String, CaseIterable {
    case website = "Website"
    case app = "App"
}

private struct AddTargetView: View {
    let settings: SettingsStore
    @Binding var isPresented: Bool

    @State private var tab: AddTab = .website
    @State private var domain = ""
    @State private var label = ""
    @State private var bundleID = ""
    @State private var appName = ""
    @State private var selectedRunningApp: NSRunningApplication?

    var body: some View {
        VStack(spacing: 16) {
            Picker("Type", selection: $tab) {
                ForEach(AddTab.allCases, id: \.self) { t in
                    Text(t.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            switch tab {
            case .website:
                VStack(spacing: 12) {
                    TextField("Domain (e.g. youtube.com)", text: $domain)
                        .textFieldStyle(.roundedBorder)
                    TextField("Label (e.g. YouTube)", text: $label)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal)

            case .app:
                VStack(spacing: 12) {
                    Text("Quick add from running apps:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("App", selection: $selectedRunningApp) {
                        Text("Select an app...").tag(nil as NSRunningApplication?)
                        ForEach(runningApps(), id: \.bundleIdentifier) { app in
                            Text(app.localizedName ?? app.bundleIdentifier ?? "Unknown")
                                .tag(app as NSRunningApplication?)
                        }
                    }
                    .onChange(of: selectedRunningApp) { _, app in
                        if let app = app {
                            bundleID = app.bundleIdentifier ?? ""
                            appName = app.localizedName ?? ""
                        }
                    }

                    Divider()
                    Text("Or enter manually:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Bundle ID (e.g. com.google.Chrome)", text: $bundleID)
                        .textFieldStyle(.roundedBorder)
                    TextField("Display name", text: $appName)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal)
            }

            Spacer()

            HStack {
                Button("Cancel") { isPresented = false }
                Spacer()
                Button("Add") {
                    addTarget()
                    isPresented = false
                }
                .disabled(!canAdd)
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .padding(.top)
    }

    private var canAdd: Bool {
        switch tab {
        case .website: return !domain.isEmpty && !label.isEmpty
        case .app:     return !bundleID.isEmpty && !appName.isEmpty
        }
    }

    private func addTarget() {
        switch tab {
        case .website:
            settings.addWebsite(domain: domain.trimmingCharacters(in: .whitespaces),
                                label: label.trimmingCharacters(in: .whitespaces))
        case .app:
            settings.addApp(bundleID: bundleID.trimmingCharacters(in: .whitespaces),
                            name: appName.trimmingCharacters(in: .whitespaces),
                            path: "")
        }
    }

    private func runningApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier != nil && $0.bundleIdentifier != "com.blocker.app" }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
}
