import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings

    @State private var keyInput: String = ""
    @State private var endpointInput: String = ""
    @State private var showKey = false
    @State private var showAdvanced = false
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.block) {
                provider(binding: $settings.selectedProvider)
                credentials(model: $settings.model)
                roster
                general
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 14)
        }
        .onAppear(perform: syncInputs)
    }

    private func syncInputs() {
        // Never show an inherited environment key in an editable field — typing
        // over it would look like an edit but write a brand new stored key.
        keyInput = settings.isInheritedFromEnvironment(settings.selectedProvider)
            ? "" : settings.apiKey
        endpointInput = settings.apiEndpoint
    }

    // MARK: - Provider

    private func provider(binding: Binding<AIProvider>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "AI provider")

            Card {
                VStack(alignment: .leading, spacing: 9) {
                    Picker("", selection: binding) {
                        ForEach(AIProvider.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: settings.selectedProvider) { _, _ in
                        syncInputs()
                        settings.save()
                    }
                    Text(providerDescription)
                        .font(Face.body(11))
                        .foregroundStyle(Palette.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Credentials

    private func credentials(model: Binding<String>) -> some View {
        let inherited = settings.isInheritedFromEnvironment(settings.selectedProvider)

        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Credentials")

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("API key")
                                .font(Face.body(11, .medium))
                                .foregroundStyle(Palette.secondary)
                            Spacer()
                            if inherited {
                                Chip(text: "from \(settings.selectedProvider.environmentVariable)",
                                     tint: Palette.success)
                            } else if !keyInput.isEmpty {
                                Button(showKey ? "Hide" : "Show") { showKey.toggle() }
                                    .buttonStyle(GhostButtonStyle())
                            }
                        }

                        Group {
                            if showKey {
                                TextField(providerKeyPlaceholder, text: $keyInput)
                            } else {
                                SecureField(providerKeyPlaceholder, text: $keyInput)
                            }
                        }
                        .softField()
                        .onChange(of: keyInput) { _, value in
                            let trimmed = value.trimmingCharacters(in: .whitespaces)
                            guard trimmed != (settings.providerKeys[settings.selectedProvider] ?? "")
                            else { return }
                            settings.providerKeys[settings.selectedProvider] = trimmed
                            settings.save()
                        }

                        if inherited {
                            Text("Using the key from your environment. Type here to override it.")
                                .font(Face.body(10.5))
                                .foregroundStyle(Palette.tertiary)
                        }
                    }

                    HStack(spacing: 10) {
                        Text("Model")
                            .font(Face.body(11, .medium))
                            .foregroundStyle(Palette.secondary)
                            .frame(width: 54, alignment: .leading)
                        Picker("", selection: model) {
                            ForEach(settings.selectedProvider.models, id: \.self) { Text($0).tag($0) }
                            // Keeps a hand-edited or newly released model visible
                            // instead of silently showing an empty picker.
                            if !settings.selectedProvider.models.contains(settings.model) {
                                Text(settings.model).tag(settings.model)
                            }
                        }
                        .labelsHidden()
                        .onChange(of: settings.model) { _, _ in settings.save() }
                    }

                    DisclosureGroup(isExpanded: $showAdvanced) {
                        TextField(settings.selectedProvider.defaultEndpoint, text: $endpointInput)
                            .softField()
                            .font(Face.mono(10.5))
                            .padding(.top, 7)
                            .onChange(of: endpointInput) { _, value in
                                let trimmed = value.trimmingCharacters(in: .whitespaces)
                                guard trimmed != settings.apiEndpoint else { return }
                                settings.apiEndpoint = trimmed
                                settings.save()
                            }
                    } label: {
                        Text("Custom endpoint")
                            .font(Face.body(11, .medium))
                            .foregroundStyle(Palette.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Roster

    private var roster: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Configured providers")

            Card {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(AIProvider.allCases.enumerated()), id: \.element) { index, provider in
                        let configured = settings.isProviderConfigured(provider)
                        let active = provider == settings.selectedProvider

                        HStack(spacing: 9) {
                            Circle()
                                .fill(configured ? Palette.success : Palette.tertiary.opacity(0.35))
                                .frame(width: 6, height: 6)
                            Text(provider.displayName)
                                .font(Face.body(12, active ? .semibold : .regular))
                            if active { Chip(text: "In use", tint: Palette.accent) }
                            Spacer(minLength: 8)
                            Text(configured ? settings.effectiveModel(for: provider) : "no key")
                                .font(Face.mono(10))
                                .foregroundStyle(Palette.tertiary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 6)

                        if index < AIProvider.allCases.count - 1 {
                            Divider().overlay(Palette.strokeFaint)
                        }
                    }

                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.tertiary)
                            .padding(.top, 1)
                        Text("Keys are stored in \(settings.secrets.displayPath), readable only by you and excluded from git. Everything else lives in settings.json.")
                            .font(Face.body(10.5))
                            .foregroundStyle(Palette.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 11)
                }
            }
        }
    }

    // MARK: - General

    private var general: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "General")

            Card {
                VStack(alignment: .leading, spacing: 9) {
                    Toggle(isOn: Binding(
                        get: { launchAtLogin },
                        set: { newValue in
                            loginItemError = LoginItem.setEnabled(newValue)
                            // Trust the system, not the click — the toggle should
                            // reflect what actually happened.
                            launchAtLogin = LoginItem.isEnabled
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Open at login")
                                .font(Face.body(12, .medium))
                            Text("Blocking only works while Blocker is running.")
                                .font(Face.body(10.5))
                                .foregroundStyle(Palette.tertiary)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!LoginItem.isAvailable)

                    if let loginItemError {
                        Text(loginItemError)
                            .font(Face.body(10.5))
                            .foregroundStyle(Palette.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if !LoginItem.isAvailable {
                        Text("Available once Blocker is installed as an app bundle.")
                            .font(Face.body(10.5))
                            .foregroundStyle(Palette.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Copy

    private var providerDescription: String {
        switch settings.selectedProvider {
        case .anthropic: "Anthropic Claude — the strongest judge and examiner."
        case .openai:    "OpenAI — fast and solid all round."
        case .deepseek:  "DeepSeek — inexpensive, strong reasoning."
        case .gemini:    "Google Gemini — generous free tier."
        }
    }

    private var providerKeyPlaceholder: String {
        switch settings.selectedProvider {
        case .anthropic: "sk-ant-api03-…"
        case .openai:    "sk-proj-…"
        case .deepseek:  "sk-…"
        case .gemini:    "AIza…"
        }
    }
}
