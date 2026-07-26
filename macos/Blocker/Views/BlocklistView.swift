import SwiftUI
import AppKit

struct BlocklistView: View {
    @Environment(SettingsStore.self) private var settings

    @State private var showingAddSheet = false
    @State private var targetToRemove: BlockedTarget?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Under injunction")
                    .font(Face.display(16, .semibold))
                Spacer()
                Button("File new") { showingAddSheet = true }
                    .buttonStyle(OutlineButtonStyle(tint: Palette.ink))
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 16)
            .padding(.bottom, 12)

            if settings.blockedTargets.isEmpty {
                EmptyNotice(title: "The docket is empty.",
                            subtitle: "File a site or application to put it behind the gatekeeper.")
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        SectionRule(title: "Entry", trailing: "Gate")
                            .padding(.bottom, 4)

                        ForEach(Array(settings.blockedTargets.enumerated()), id: \.element.id) { index, target in
                            row(index: index, target: target)
                            Rule(color: Palette.ruleFaint)
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

    private func row(index: Int, target: BlockedTarget) -> some View {
        HStack(spacing: 11) {
            Text(String(format: "%02d", index + 1))
                .font(Face.clerk(9))
                .foregroundStyle(Palette.faint)

            VStack(alignment: .leading, spacing: 1) {
                Text(target.displayName)
                    .font(Face.body(12.5, .medium))
                    .lineLimit(1)
                Text(subtitle(target))
                    .font(Face.clerk(9))
                    .foregroundStyle(Palette.faint)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Menu {
                Button(target.category == .strict ? "Reduce to examination" : "Raise to judgment") {
                    settings.toggleCategory(target.id)
                }
                Divider()
                Button("Petition to remove…", role: .destructive) {
                    targetToRemove = target
                }
            } label: {
                Tag(text: target.category == .strict ? "Judge" : "Exam",
                    tint: target.category == .strict ? Palette.seal : Palette.muted)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 9)
    }

    private func subtitle(_ target: BlockedTarget) -> String {
        switch target.kind {
        case .app(let id, _, _):      return id
        case .website(let domain, _): return domain
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
            Text("File an injunction")
                .font(Face.display(19, .semibold))
            Rule(color: Palette.ink, weight: 2)
                .padding(.top, 11)
                .padding(.bottom, 16)

            Picker("", selection: $tab) {
                ForEach(AddTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.bottom, 16)

            switch tab {
            case .website:
                VStack(alignment: .leading, spacing: 13) {
                    field("Domain", text: $domain, prompt: "youtube.com")
                    field("Name", text: $label, prompt: "optional")
                    Text("Subdomains are covered automatically.")
                        .font(Face.body(10.5))
                        .foregroundStyle(Palette.faint)
                }
            case .app:
                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 10) {
                        Text("RUNNING")
                            .font(Face.clerk(9, .semibold))
                            .tracking(1.2)
                            .foregroundStyle(Palette.muted)
                            .frame(width: 62, alignment: .leading)
                        Picker("", selection: $selectedRunningApp) {
                            Text("choose…").tag(nil as NSRunningApplication?)
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
                    field("Bundle", text: $bundleID, prompt: "com.google.Chrome")
                    field("Name", text: $appName, prompt: "optional")
                }
            }

            Spacer(minLength: 18)

            SectionRule(title: "Gate")
                .padding(.bottom, 9)
            Picker("", selection: $category) {
                Text("Examination — solve a problem").tag(BlockedTarget.Category.regular)
                Text("Judgment — convince the judge").tag(BlockedTarget.Category.strict)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Spacer(minLength: 18)

            HStack {
                Button("Cancel") { isPresented = false }
                    .buttonStyle(PlainActionStyle())
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button("File") {
                    addTarget()
                    isPresented = false
                }
                .buttonStyle(SealButtonStyle())
                .disabled(!canAdd)
                .keyboardShortcut(.return)
            }
        }
        .padding(22)
        .frame(width: 400, height: 380)
        .background(Palette.paper)
        .foregroundStyle(Palette.ink)
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            Text(title.uppercased())
                .font(Face.clerk(9, .semibold))
                .tracking(1.2)
                .foregroundStyle(Palette.muted)
                .frame(width: 62, alignment: .leading)
            TextField(prompt, text: text)
                .ruledField()
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
