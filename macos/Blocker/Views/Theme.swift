import SwiftUI
import AppKit

// Visual language: a court that sets you an exam.
//
// Ink on paper, not glass. Type does the work — a serif for anything with
// authority (headings, verdicts, figures), a mono for the clerical layer
// (labels, case numbers, timers), system sans for reading text. Structure comes
// from rules and alignment rather than boxes, and colour is reserved for
// judgment: seal red denies, verdigris grants, brass presides.
//
// The Chrome extension mirrors all of this in ChromeExt/theme.css.

enum Palette {
    /// Resolves per appearance so light mode is genuinely paper, not a wash of grey.
    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    private static func hex(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: alpha)
    }

    // Surfaces
    static let paper   = dynamic(light: hex(0xF7F3EA), dark: hex(0x141210))
    static let surface = dynamic(light: hex(0xFFFDF8), dark: hex(0x1C1A16))
    static let sunken  = dynamic(light: hex(0xEFE9DC), dark: hex(0x100E0C))

    // Text
    static let ink     = dynamic(light: hex(0x1A1714), dark: hex(0xEDE8DF))
    static let muted   = dynamic(light: hex(0x6B6259), dark: hex(0x9C9388))
    static let faint   = dynamic(light: hex(0x9A9086), dark: hex(0x6A635B))

    // Rules
    static let rule      = dynamic(light: hex(0x1A1714, alpha: 0.16), dark: hex(0xEDE8DF, alpha: 0.16))
    static let ruleFaint = dynamic(light: hex(0x1A1714, alpha: 0.08), dark: hex(0xEDE8DF, alpha: 0.08))

    // Judgment
    static let seal      = dynamic(light: hex(0xA33227), dark: hex(0xCB4E3F)) // deny / strict
    static let brass     = dynamic(light: hex(0x8A6420), dark: hex(0xC49A48)) // the judge / caution
    static let verdigris = dynamic(light: hex(0x2E6A4F), dark: hex(0x5CA57F)) // granted

    static func tint(for category: BlockedTarget.Category) -> Color {
        category == .strict ? seal : ink
    }
}

// MARK: - Type

enum Face {
    static func display(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    /// Clerical layer: labels, case numbers, timers, figures in tables.
    static func clerk(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

enum Metrics {
    static let gutter: CGFloat = 18
    static let block: CGFloat = 20      // space between major blocks
    static let radius: CGFloat = 3      // near-square; paper doesn't have 12pt corners
}

// MARK: - Structure

struct Rule: View {
    var color: Color = Palette.rule
    var weight: CGFloat = 1
    var body: some View {
        Rectangle().fill(color).frame(height: weight)
    }
}

/// A clerical caption with a rule running out to the right margin.
struct SectionRule: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(spacing: 9) {
            Text(title.uppercased())
                .font(Face.clerk(9, .semibold))
                .tracking(1.3)
                .foregroundStyle(Palette.muted)
            Rule(color: Palette.ruleFaint)
            if let trailing {
                Text(trailing.uppercased())
                    .font(Face.clerk(9))
                    .tracking(1.1)
                    .foregroundStyle(Palette.faint)
            }
        }
    }
}

/// Sharp-cornered classification tag. Outlined, never filled — filled pills read
/// as chat-app UI.
struct Tag: View {
    let text: String
    var tint: Color = Palette.ink

    var body: some View {
        Text(text.uppercased())
            .font(Face.clerk(9, .semibold))
            .tracking(1.1)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(Rectangle().strokeBorder(tint.opacity(0.5), lineWidth: 1))
    }
}

/// Docket line: `CASE №2607-1438 · TIKTOK · STRICT`
struct DocketLine: View {
    let parts: [String]

    var body: some View {
        Text(parts.joined(separator: "  ·  ").uppercased())
            .font(Face.clerk(9))
            .tracking(1.2)
            .foregroundStyle(Palette.faint)
            .lineLimit(1)
    }
}

/// The verdict mark — double-ruled, letterspaced, sitting slightly off-square
/// like something pressed onto the page.
struct Stamp: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text.uppercased())
            .font(Face.display(28, .bold))
            .tracking(7)
            .foregroundStyle(tint)
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
            .overlay(Rectangle().strokeBorder(tint, lineWidth: 3))
            .padding(3)
            .overlay(Rectangle().strokeBorder(tint.opacity(0.45), lineWidth: 1))
            .rotationEffect(.degrees(-2.5))
    }
}

struct EmptyNotice: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(Face.display(15))
                .foregroundStyle(Palette.muted)
            if let subtitle {
                Text(subtitle)
                    .font(Face.body(11.5))
                    .foregroundStyle(Palette.faint)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 30)
    }
}

// MARK: - Controls

/// Solid, square, clerical. The only loud control on screen.
struct SealButtonStyle: ButtonStyle {
    var tint: Color = Palette.ink
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Face.clerk(10, .semibold))
            .tracking(1.3)
            .textCase(.uppercase)
            .foregroundStyle(isEnabled ? Palette.paper : Palette.faint)
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            .background(
                Rectangle()
                    .fill(isEnabled ? tint : Color.clear)
                    .opacity(configuration.isPressed ? 0.78 : 1)
            )
            // Disabled reads as a faint outline rather than a heavy grey slab.
            .overlay(
                Rectangle().strokeBorder(isEnabled ? Color.clear : Palette.ruleFaint, lineWidth: 1)
            )
            .contentShape(Rectangle())
    }
}

/// Outlined counterpart for secondary actions.
struct OutlineButtonStyle: ButtonStyle {
    var tint: Color = Palette.muted
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Face.clerk(10, .semibold))
            .tracking(1.3)
            .textCase(.uppercase)
            .foregroundStyle(isEnabled ? tint : Palette.faint)
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            .background(Rectangle().fill(configuration.isPressed ? Palette.rule : Color.clear))
            .overlay(Rectangle().strokeBorder(tint.opacity(0.45), lineWidth: 1))
            .contentShape(Rectangle())
    }
}

/// Bare text action, for tertiary moves like "give up".
struct PlainActionStyle: ButtonStyle {
    var tint: Color = Palette.muted

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Face.clerk(10, .semibold))
            .tracking(1.3)
            .textCase(.uppercase)
            .foregroundStyle(configuration.isPressed ? Palette.ink : tint)
            .contentShape(Rectangle())
    }
}

/// Field styling: ruled underline, not a rounded box.
struct RuledField: ViewModifier {
    var focused = false
    func body(content: Content) -> some View {
        VStack(spacing: 5) {
            content
                .textFieldStyle(.plain)
                .font(Face.body(12.5))
            Rule(color: focused ? Palette.ink : Palette.rule)
        }
    }
}

extension View {
    func ruledField(focused: Bool = false) -> some View {
        modifier(RuledField(focused: focused))
    }
}

// MARK: - Clock

/// Countdown as a clerical readout with a depleting rule beneath it — no dial.
struct Countdown: View {
    let remaining: Int
    let total: Int

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return max(0, min(1, Double(remaining) / Double(total)))
    }

    private var tint: Color {
        remaining <= 30 ? Palette.seal : (remaining <= 60 ? Palette.brass : Palette.muted)
    }

    private var label: String {
        guard remaining > 0 else { return "00:00" }
        return String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(label)
                .font(Face.clerk(15, .medium))
                .tracking(1)
                .foregroundStyle(tint)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Palette.ruleFaint)
                    Rectangle().fill(tint)
                        .frame(width: geo.size.width * fraction)
                        .animation(.linear(duration: 0.3), value: fraction)
                }
            }
            .frame(width: 52, height: 2)
        }
        .accessibilityLabel("Time remaining \(label)")
    }
}

/// `№2607-1438` — stable per challenge, purely for the clerical fiction.
func caseNumber(from id: UUID) -> String {
    let digits = abs(id.hashValue)
    let f = Exam.dateFormatter.string(from: Date()).replacingOccurrences(of: "-", with: "")
    let mmdd = String(f.suffix(4))
    return "№\(mmdd)-\(String(format: "%04d", digits % 10000))"
}
