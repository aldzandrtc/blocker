import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings

    @State private var keyInput: String = ""
    @State private var showKey = false
    @State private var endpointInput: String = ""

    var body: some View {
        @Bindable var settings = settings
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("AI Configuration")
                    .font(.title2)
                    .padding(.horizontal)

                // Provider selector
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Provider", selection: $settings.selectedProvider) {
                            ForEach(AIProvider.allCases, id: \.self) { provider in
                                HStack {
                                    Circle()
                                        .fill(settings.isProviderConfigured(provider) ? Color.green : Color.gray.opacity(0.3))
                                        .frame(width: 8, height: 8)
                                    Text(provider.displayName)
                                }
                                .tag(provider)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: settings.selectedProvider) { _, _ in
                            keyInput = settings.apiKey
                            endpointInput = settings.apiEndpoint
                            settings.save()
                        }

                        Text(providerDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                } label: {
                    Label("Provider", systemImage: "cpu.fill")
                }
                .padding(.horizontal)

                // API Key
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("API Key")
                                .frame(width: 80, alignment: .leading)
                            if showKey {
                                TextField(providerKeyPlaceholder, text: $keyInput)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField(providerKeyPlaceholder, text: $keyInput)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Button {
                                showKey.toggle()
                            } label: {
                                Image(systemName: showKey ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.plain)
                        }
                        .onAppear { keyInput = settings.apiKey }
                        .onChange(of: keyInput) { _, value in
                            settings.apiKey = value.trimmingCharacters(in: .whitespaces)
                            settings.save()
                        }

                        HStack {
                            Text("Model")
                                .frame(width: 80, alignment: .leading)
                            Picker("", selection: $settings.model) {
                                ForEach(settings.selectedProvider.models, id: \.self) { m in
                                    Text(m).tag(m)
                                }
                            }
                            .onChange(of: settings.model) { _, _ in settings.save() }
                        }

                        HStack {
                            Text("Endpoint")
                                .frame(width: 80, alignment: .leading)
                            TextField(settings.selectedProvider.defaultEndpoint, text: $endpointInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                                .onAppear { endpointInput = settings.apiEndpoint }
                                .onChange(of: endpointInput) { _, value in
                                    settings.apiEndpoint = value.trimmingCharacters(in: .whitespaces)
                                    settings.save()
                                }
                        }
                    }
                    .padding(8)
                } label: {
                    Label("Credentials", systemImage: "key.fill")
                }
                .padding(.horizontal)

                // Provider status
                GroupBox {
                    VStack(spacing: 6) {
                        ForEach(AIProvider.allCases, id: \.self) { provider in
                            HStack {
                                Circle()
                                    .fill(settings.isProviderConfigured(provider) ? Color.green : Color.gray.opacity(0.3))
                                    .frame(width: 8, height: 8)
                                Text(provider.displayName)
                                    .font(.body)
                                Spacer()
                                if settings.isProviderConfigured(provider) {
                                    Text(settings.effectiveModel(for: provider))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("not configured")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(8)
                } label: {
                    Label("Status", systemImage: "checklist")
                }
                .padding(.horizontal)

                // About
                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Blocker supports Claude, ChatGPT, DeepSeek, and Gemini.")
                            .font(.caption)
                        Text("Get API keys from each provider's console, or use a proxy like OpenRouter for unified access.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                } label: {
                    Label("About", systemImage: "info.circle.fill")
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.vertical)
        }
    }

    private var providerDescription: String {
        switch settings.selectedProvider {
        case .anthropic: "Anthropic Claude — most capable for judging + problem generation"
        case .openai:    "OpenAI ChatGPT — fast, good all-around performance"
        case .deepseek:  "DeepSeek — affordable, strong reasoning"
        case .gemini:    "Google Gemini — generous free tier available"
        }
    }

    private var providerKeyPlaceholder: String {
        switch settings.selectedProvider {
        case .anthropic: "sk-ant-api03-..."
        case .openai:    "sk-proj-..."
        case .deepseek:  "sk-..."
        case .gemini:    "AIza..."
        }
    }
}
