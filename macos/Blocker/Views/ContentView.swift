import SwiftUI

struct ContentView: View {
    @Environment(SettingsStore.self) private var settings

    @State private var selection: NavItem? = .home

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "shield.checkered")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Blocker")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            HStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(NavItem.allCases, id: \.self) { item in
                        Label(item.rawValue, systemImage: item.icon)
                            .padding(.vertical, 4)
                    }
                }
                .listStyle(.sidebar)
                .frame(width: 140)

                Divider()

                Group {
                    switch selection ?? .home {
                    case .home:      HomeView()
                    case .blocklist: BlocklistView()
                    case .profile:   ProfileView()
                    case .history:   HistoryView()
                    case .settings:  SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(settings.hasApiKey ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(settings.hasApiKey ? "API" : "No key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(settings.extensionConnected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(settings.extensionConnected ? "Ext" : "No ext")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(":14923")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .frame(width: 440, height: 500)
    }
}

private enum NavItem: String, CaseIterable {
    case home      = "Home"
    case blocklist = "Blocklist"
    case profile   = "Profile"
    case history   = "History"
    case settings  = "Settings"

    var icon: String {
        switch self {
        case .home:      "house.fill"
        case .blocklist: "hand.raised.fill"
        case .profile:   "person.fill"
        case .history:   "clock.fill"
        case .settings:  "gearshape.fill"
        }
    }
}
