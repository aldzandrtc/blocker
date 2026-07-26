import SwiftUI

struct ContentView: View {
    @Environment(SettingsStore.self) private var settings

    @State private var selection: NavItem = .home

    var body: some View {
        VStack(spacing: 0) {
            masthead
            Rule(color: Palette.ink, weight: 2)
            tabs
            Rule()

            Group {
                switch selection {
                case .home:      HomeView()
                case .blocklist: BlocklistView()
                case .profile:   ProfileView()
                case .history:   HistoryView()
                case .settings:  SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 440, height: 520)
        .background(Palette.paper)
        .foregroundStyle(Palette.ink)
    }

    // MARK: - Masthead

    private var masthead: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("BLOCKER")
                .font(Face.display(19, .bold))
                .tracking(3.5)

            Spacer()

            HStack(spacing: 12) {
                indicator("API", on: settings.hasApiKey)
                indicator("EXT", on: settings.extensionConnected)
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    /// Status reads as a ledger mark, not a coloured dot on a chat app.
    private func indicator(_ label: String, on: Bool) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(Face.clerk(9, .semibold))
                .tracking(1.2)
                .foregroundStyle(on ? Palette.ink : Palette.faint)
            Rectangle()
                .fill(on ? Palette.verdigris : Palette.seal)
                .frame(width: 5, height: 5)
        }
        .help(on ? "\(label): connected" : "\(label): not connected")
    }

    // MARK: - Tabs

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(NavItem.allCases, id: \.self) { item in
                TabButton(item: item, isSelected: selection == item) {
                    selection = item
                }
            }
        }
        .padding(.horizontal, Metrics.gutter - 6)
    }
}

private struct TabButton: View {
    let item: NavItem
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(item.rawValue.uppercased())
                    .font(Face.clerk(9, isSelected ? .bold : .medium))
                    .tracking(1.2)
                    .foregroundStyle(isSelected ? Palette.ink
                                     : (hovering ? Palette.muted : Palette.faint))
                Rectangle()
                    .fill(isSelected ? Palette.seal : Color.clear)
                    .frame(height: 2)
            }
            .padding(.top, 9)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

enum NavItem: String, CaseIterable {
    case home      = "Docket"
    case blocklist = "Blocklist"
    case profile   = "Profile"
    case history   = "Record"
    case settings  = "Settings"
}
