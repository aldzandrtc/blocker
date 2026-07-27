import SwiftUI

struct ContentView: View {
    @Environment(SettingsStore.self) private var settings

    @State private var selection: NavItem = .home
    /// `extensionConnected` is derived from a timestamp, so nothing would tell
    /// the view to re-read it. This keeps the badge honest.
    @State private var heartbeat = Date()

    private let ticker = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            tabs

            Divider().overlay(Palette.strokeFaint)

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
        .frame(width: 440, height: 560)
        .background(Palette.canvas)
        .foregroundStyle(Palette.text)
        .onReceive(ticker) { heartbeat = $0 }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Palette.accent.gradient)
                    .frame(width: 24, height: 24)
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text("Blocker")
                .font(Face.display(16, .bold))

            Spacer()

            statusDot("API", on: settings.hasApiKey,
                      help: settings.hasApiKey ? "API key configured" : "No API key — add one in Settings")
            statusDot("Extension", on: settings.extensionConnected,
                      help: settings.extensionConnected ? "Chrome extension connected" : "Chrome extension not answering")
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 13)
        .padding(.bottom, 11)
        .id(heartbeat)
    }

    private func statusDot(_ label: String, on: Bool, help: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(on ? Palette.success : Palette.tertiary.opacity(0.5))
                .frame(width: 6, height: 6)
            Text(label)
                .font(Face.body(10.5, .medium))
                .foregroundStyle(on ? Palette.secondary : Palette.tertiary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Palette.surface))
        .overlay(Capsule().strokeBorder(Palette.strokeFaint, lineWidth: 1))
        .help(help)
    }

    // MARK: - Tabs

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(NavItem.allCases, id: \.self) { item in
                TabButton(item: item, isSelected: selection == item) {
                    withAnimation(.easeOut(duration: 0.12)) { selection = item }
                }
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 10)
    }
}

private struct TabButton: View {
    let item: NavItem
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: item.icon)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                Text(item.title)
                    .font(Face.body(9.5, isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? Palette.accent
                             : (hovering ? Palette.secondary : Palette.tertiary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                    .fill(isSelected ? Palette.accent.opacity(0.12)
                          : (hovering ? Palette.strokeFaint : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

enum NavItem: String, CaseIterable {
    case home, blocklist, profile, history, settings

    var title: String {
        switch self {
        case .home:      "Today"
        case .blocklist: "Blocked"
        case .profile:   "Profile"
        case .history:   "Progress"
        case .settings:  "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home:      "square.grid.2x2.fill"
        case .blocklist: "hand.raised.fill"
        case .profile:   "person.fill"
        case .history:   "chart.bar.fill"
        case .settings:  "gearshape.fill"
        }
    }
}
