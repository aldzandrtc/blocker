import SwiftUI
import AppKit

struct BlocklistView: View {
    @Environment(SettingsStore.self) private var settings

    @State private var showingAddSheet = false
    @State private var targetToRemove: BlockedTarget?
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            header

            if settings.blockedTargets.isEmpty {
                EmptyNotice(title: "Nothing is blocked yet",
                            subtitle: "Add a site or app and it goes behind the gatekeeper.",
                            systemImage: "hand.raised")
            } else if filtered.isEmpty {
                EmptyNotice(title: "No matches",
                            subtitle: "Nothing on the list matches “\(search)”.",
                            systemImage: "magnifyingglass")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filtered) { target in
                            row(target)
                        }
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.bottom, Metrics.gutter)
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddTargetView(settings: settings, isPresented: $showingAddSheet)
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

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Blocked")
                    .font(Face.display(17, .bold))
                Spacer()
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            if settings.blockedTargets.count > 5 {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tertiary)
                    TextField("Filter", text: $search)
                        .textFieldStyle(.plain)
                        .font(Face.body(12))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                        .fill(Palette.sunken)
                )
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var filtered: [BlockedTarget] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return settings.blockedTargets }
        return settings.blockedTargets.filter {
            $0.displayName.lowercased().contains(needle) || $0.subtitle.lowercased().contains(needle)
        }
    }

    private func row(_ target: BlockedTarget) -> some View {
        let cooling = settings.cooldownRemaining(for: target.id)

        return Card(padding: 11) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Palette.tint(for: target.category).opacity(0.13))
                        .frame(width: 30, height: 30)
                    Image(systemName: target.isWebsite ? "globe" : "app.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.tint(for: target.category))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(target.displayName)
                        .font(Face.body(12.5, .semibold))
                        .lineLimit(1)
                    Text(target.subtitle)
                        .font(Face.body(10.5))
                        .foregroundStyle(Palette.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                if cooling > 0 {
                    Chip(text: clockText(cooling), tint: Palette.warning)
                        .help("Cooling down after a failed attempt")
                }

                // The chip is its own button rather than a Menu label: macOS
                // re-templates menu labels and strips the capsule fill, leaving
                // bare coloured text.
                Button {
                    settings.toggleCategory(target.id)
                } label: {
                    Chip(text: target.category == .strict ? "Judge" : "Quiz",
                         tint: Palette.tint(for: target.category))
                }
                .buttonStyle(.plain)
                .help(target.category == .strict
                      ? "Switch to a quiz question instead"
                      : "Switch to convincing the judge instead")

                Menu {
                    Button(target.category == .strict
                           ? "Switch to a quiz question"
                           : "Switch to convincing the judge") {
                        settings.toggleCategory(target.id)
                    }
                    Divider()
                    Button("Remove…", role: .destructive) { targetToRemove = target }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.tertiary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 18)
            }
        }
    }
}

private enum AddTab: String, CaseIterable {
    case website = "Website"
    case app = "Application"
}

private struct AddTargetView: View {
    let settings: SettingsStore
    @Binding var isPresented: Bool

    @State private var tab: AddTab = .website
    @State private var domain = ""
    @State private var label = ""
    @State private var bundleID = ""
    @State private var appName = ""
    @State private var category: BlockedTarget.Category = .regular
    @State private var selectedRunningApp: NSRunningApplication?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Block something")
                .font(Face.display(18, .bold))
                .padding(.bottom, 14)

            Picker("", selection: $tab) {
                ForEach(AddTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.bottom, 14)

            switch tab {
            case .website:
                VStack(alignment: .leading, spacing: 11) {
                    field("Domain", text: $domain, prompt: "youtube.com")
                    field("Name", text: $label, prompt: "optional")
                    Text("Subdomains are covered automatically.")
                        .font(Face.body(10.5))
                        .foregroundStyle(Palette.tertiary)
                }
            case .app:
                VStack(alignment: .leading, spacing: 11) {
                    HStack(spacing: 10) {
                        Text("Running")
                            .font(Face.body(11, .medium))
                            .foregroundStyle(Palette.secondary)
                            .frame(width: 62, alignment: .leading)
                        Picker("", selection: $selectedRunningApp) {
                            Text("Choose…").tag(nil as NSRunningApplication?)
                            ForEach(runningApps(), id: \.processIdentifier) { app in
                                Text(app.localizedName ?? app.bundleIdentifier ?? "Unknown")
                                    .tag(app as NSRunningApplication?)
                            }
                        }
                        .labelsHidden()
                        .onChange(of: selectedRunningApp) { _, app in
                            guard let app else { return }
                            bundleID = app.bundleIdentifier ?? ""
                            appName = app.localizedName ?? ""
                        }
                    }
                    field("Bundle ID", text: $bundleID, prompt: "com.google.Chrome")
                    field("Name", text: $appName, prompt: "optional")
                }
            }

            Spacer(minLength: 16)

            Text("How to get past it")
                .font(Face.body(11, .semibold))
                .foregroundStyle(Palette.secondary)
                .padding(.bottom, 7)

            VStack(spacing: 7) {
                gateOption(.regular, title: "Answer a question",
                           detail: "A problem drawn from your subjects and weak topics.",
                           icon: "function")
                gateOption(.strict, title: "Convince the judge",
                           detail: "An AI that starts from no and rarely moves.",
                           icon: "building.columns.fill")
            }

            Spacer(minLength: 16)

            HStack {
                Button("Cancel") { isPresented = false }
                    .buttonStyle(GhostButtonStyle())
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button("Block it") {
                    addTarget()
                    isPresented = false
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canAdd)
                .keyboardShortcut(.return)
            }
        }
        .padding(20)
        .frame(width: 420, height: 430)
        .background(Palette.canvas)
        .foregroundStyle(Palette.text)
    }

    private func gateOption(_ value: BlockedTarget.Category,
                            title: String, detail: String, icon: String) -> some View {
        let selected = category == value
        let tint = Palette.tint(for: value)

        return Button {
            category = value
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(selected ? tint : Palette.tertiary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Face.body(12, .semibold))
                        .foregroundStyle(Palette.text)
                    Text(detail)
                        .font(Face.body(10.5))
                        .foregroundStyle(Palette.tertiary)
                }
                Spacer()
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? tint : Palette.tertiary.opacity(0.5))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                    .fill(selected ? tint.opacity(0.09) : Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                    .strokeBorder(selected ? tint.opacity(0.5) : Palette.stroke, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(Face.body(11, .medium))
                .foregroundStyle(Palette.secondary)
                .frame(width: 62, alignment: .leading)
            TextField(prompt, text: text)
                .softField()
        }
    }

    private var canAdd: Bool {
        switch tab {
        case .website: return !domain.trimmingCharacters(in: .whitespaces).isEmpty
        case .app:     return !bundleID.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func addTarget() {
        switch tab {
        case .website:
            let d = domain.trimmingCharacters(in: .whitespaces)
            settings.addWebsite(domain: d, label: label.trimmingCharacters(in: .whitespaces))
            settings.setCategory("web-\(SettingsStore.normalizeDomain(d))", category)
        case .app:
            let id = bundleID.trimmingCharacters(in: .whitespaces)
            let name = appName.trimmingCharacters(in: .whitespaces)
            settings.addApp(bundleID: id, name: name.isEmpty ? id : name, path: "")
            settings.setCategory("app-\(id)", category)
        }
    }

    private func runningApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular
                && $0.bundleIdentifier != nil
                && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
}
