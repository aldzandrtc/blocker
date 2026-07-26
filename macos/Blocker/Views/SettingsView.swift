import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings

    @State private var keyInput: String = ""
    @State private var endpointInput: String = ""
    @State private var showKey = false
    @State private var showAdvanced = false

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.block) {
                provider(binding: $settings.selectedProvider)
                credentials(model: $settings.model)
                roster
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 16)
        }
        .onAppear(perform: syncInputs)
    }

    private func syncInputs() {
        keyInput = settings.apiKey
        endpointInput = settings.apiEndpoint
    }

    // MARK: - Provider

    private func provider(binding: Binding<AIProvider>) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionRule(title: "Counsel")
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
                .foregroundStyle(Palette.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Credentials

    private func credentials(model: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionRule(title: "Credentials")

            HStack(alignment: .bottom, spacing: 10) {
                Text("KEY")
                    .font(Face.clerk(9, .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Palette.muted)
                    .frame(width: 54, alignment: .leading)
                Group {
                    if showKey {
                        TextField(providerKeyPlaceholder, text: $keyInput)
                    } else {
                        SecureField(providerKeyPlaceholder, text: $keyInput)
                    }
                }
                .ruledField()
                .onChange(of: keyInput) { _, value in
                    let trimmed = value.trimmingCharacters(in: .whitespaces)
                    guard trimmed != settings.apiKey else { return }
                    settings.apiKey = trimmed
                    settings.save()
                }
                Button(showKey ? "Hide" : "Show") { showKey.toggle() }
                    .buttonStyle(PlainActionStyle())
            }

            HStack(spacing: 10) {
                Text("MODEL")
                    .font(Face.clerk(9, .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Palette.muted)
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
                HStack(alignment: .bottom, spacing: 10) {
                    Text("URL")
                        .font(Face.clerk(9, .semibold))
                        .tracking(1.2)
                        .foregroundStyle(Palette.muted)
                        .frame(width: 54, alignment: .leading)
                    TextField(settings.selectedProvider.defaultEndpoint, text: $endpointInput)
                        .ruledField()
                        .font(Face.clerk(10))
                        .onChange(of: endpointInput) { _, value in
                            let trimmed = value.trimmingCharacters(in: .whitespaces)
                            guard trimmed != settings.apiEndpoint else { return }
                            settings.apiEndpoint = trimmed
                            settings.save()
                        }
                }
                .padding(.top, 8)
            } label: {
                Text("ENDPOINT")
                    .font(Face.clerk(9, .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Palette.muted)
            }
        }
    }

    // MARK: - Roster

    private var roster: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionRule(title: "On file")
                .padding(.bottom, 6)

            ForEach(Array(AIProvider.allCases.enumerated()), id: \.element) { index, provider in
                let configured = settings.isProviderConfigured(provider)
                let active = provider == settings.selectedProvider
                HStack(spacing: 9) {
                    Rectangle()
                        .fill(configured ? Palette.verdigris : Palette.ruleFaint)
                        .frame(width: 4, height: 4)
                    Text(provider.displayName)
                        .font(Face.body(12, active ? .semibold : .regular))
                    if active {
                        Text("RETAINED")
                            .font(Face.clerk(8, .bold))
                            .tracking(1.1)
                            .foregroundStyle(Palette.brass)
                    }
                    Spacer(minLength: 8)
                    Text(configured ? settings.effectiveModel(for: provider) : "no key")
                        .font(Face.clerk(9))
                        .foregroundStyle(Palette.faint)
                        .lineLimit(1)
                }
                .padding(.vertical, 6)
                if index < AIProvider.allCases.count - 1 { Rule(color: Palette.ruleFaint) }
            }

            Text("Keys are held in ~/.config/blocker/settings.json, readable only by you.")
                .font(Face.body(10.5))
                .foregroundStyle(Palette.faint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
    }

    // MARK: - Copy

    private var providerDescription: String {
        switch settings.selectedProvider {
        case .anthropic: "Anthropic Claude — the most capable judge and examiner."
        case .openai:    "OpenAI — fast, solid all round."
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
