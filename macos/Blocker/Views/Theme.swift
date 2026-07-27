import SwiftUI
import AppKit

// Visual language: a calm, modern control panel.
//
// Layered neutral surfaces give depth, one indigo accent carries every primary
// action, and colour is otherwise reserved for meaning — green for granted,
// amber for caution, red for denied. Type is SF throughout: rounded for figures
// and headings so numbers read as numbers, default for prose. Generous corner
// radii and soft shadows, no hairline-rule scaffolding.
//
// The Chrome extension mirrors these tokens in ChromeExt/theme.css.

enum Palette {
    /// Resolves per appearance, so light mode is genuinely light rather than a
    /// washed-out copy of the dark palette.
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

    // Surfaces, lightest content sitting on the darkest canvas
    static let canvas    = dynamic(light: hex(0xF2F3F7), dark: hex(0x121318))
    static let surface   = dynamic(light: hex(0xFFFFFF), dark: hex(0x1C1E26))
    static let elevated  = dynamic(light: hex(0xFFFFFF), dark: hex(0x242731))
    static let sunken    = dynamic(light: hex(0xE9EBF1), dark: hex(0x0D0E12))

    // Text
    static let text      = dynamic(light: hex(0x14161C), dark: hex(0xF2F3F7))
    static let secondary = dynamic(light: hex(0x5A6070), dark: hex(0xA3AABC))
    static let tertiary  = dynamic(light: hex(0x8990A2), dark: hex(0x6E7688))

    // Lines and separators
    static let stroke      = dynamic(light: hex(0x14161C, alpha: 0.10), dark: hex(0xFFFFFF, alpha: 0.10))
    static let strokeFaint = dynamic(light: hex(0x14161C, alpha: 0.06), dark: hex(0xFFFFFF, alpha: 0.06))

    // Meaning
    static let accent  = dynamic(light: hex(0x5B5BD6), dark: hex(0x8A8AF0))
    static let success = dynamic(light: hex(0x1B8F62), dark: hex(0x45CE96))
    static let warning = dynamic(light: hex(0xB5771A), dark: hex(0xE8B04B))
    static let danger  = dynamic(light: hex(0xD03A52), dark: hex(0xFF7087))

    static let shadow = dynamic(light: hex(0x14161C, alpha: 0.10), dark: hex(0x000000, alpha: 0.45))

    static func tint(for category: BlockedTarget.Category) -> Color {
        category == .strict ? danger : accent
    }
}

// MARK: - Type

enum Face {
    /// Headings and anything with a number in it — rounded digits read cleanly
    /// at a glance, which is what a dashboard is for.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

enum Metrics {
    static let gutter: CGFloat = 16
    static let block: CGFloat = 18      // space between major sections
    static let radius: CGFloat = 12
    static let smallRadius: CGFloat = 8
}

// MARK: - Structure

/// The one container everything sits in: filled, rounded, hairline-stroked,
/// with just enough shadow to lift it off the canvas.
struct Card<Content: View>: View {
    var padding: CGFloat = 14
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .strokeBorder(tint?.opacity(0.35) ?? Palette.stroke, lineWidth: 1)
            )
            .shadow(color: Palette.shadow, radius: 8, x: 0, y: 2)
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Face.display(13, .semibold))
                .foregroundStyle(Palette.text)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(Face.body(11))
                    .foregroundStyle(Palette.tertiary)
            }
        }
    }
}

/// Filled, rounded status pill.
struct Chip: View {
    let text: String
    var tint: Color = Palette.accent
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(Face.body(10.5, .semibold))
            .foregroundStyle(filled ? .white : tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(filled ? tint : tint.opacity(0.14))
            )
            .fixedSize()
    }
}

/// The verdict mark at the end of a challenge.
struct Verdict: View {
    let granted: Bool
    var title: String?

    private var tint: Color { granted ? Palette.success : Palette.danger }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(0.14)).frame(width: 64, height: 64)
                Image(systemName: granted ? "checkmark" : "xmark")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(tint)
            }
            Text(title ?? (granted ? "Granted" : "Denied"))
                .font(Face.display(21, .bold))
                .foregroundStyle(tint)
        }
    }
}

struct EmptyNotice: View {
    let title: String
    var subtitle: String?
    var systemImage: String = "tray"

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Palette.tertiary)
            Text(title)
                .font(Face.display(14, .medium))
                .foregroundStyle(Palette.secondary)
            if let subtitle {
                Text(subtitle)
                    .font(Face.body(11.5))
                    .foregroundStyle(Palette.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 34)
    }
}

// MARK: - Controls

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Palette.accent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Face.body(12, .semibold))
            .foregroundStyle(isEnabled ? .white : Palette.tertiary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                    .fill(isEnabled ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Palette.sunken))
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Tinted rather than filled — secondary weight without turning grey.
struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = Palette.accent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Face.body(12, .medium))
            .foregroundStyle(isEnabled ? tint : Palette.tertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.22 : 0.12))
            )
            .contentShape(Rectangle())
    }
}

/// Bare text action for tertiary moves like "cancel" or "give up".
struct GhostButtonStyle: ButtonStyle {
    var tint: Color = Palette.secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Face.body(12, .medium))
            .foregroundStyle(configuration.isPressed ? Palette.text : tint)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
    }
}

/// Small circular icon button — remove, close, and similar.
struct IconButtonStyle: ButtonStyle {
    var tint: Color = Palette.tertiary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(configuration.isPressed ? Palette.danger : tint)
            .frame(width: 18, height: 18)
            .background(Circle().fill(Palette.strokeFaint))
            .contentShape(Circle())
    }
}

/// Inset, rounded field — a real input, not an underline.
struct SoftFieldStyle: ViewModifier {
    var focused = false

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(Face.body(12.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                    .fill(Palette.sunken)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                    .strokeBorder(focused ? Palette.accent.opacity(0.7) : Palette.stroke, lineWidth: 1)
            )
    }
}

extension View {
    func softField(focused: Bool = false) -> some View {
        modifier(SoftFieldStyle(focused: focused))
    }
}

// MARK: - Figures

/// Big number over a caption — the unit the dashboard is built from.
struct Stat: View {
    let value: String
    let label: String
    var tint: Color = Palette.text
    var systemImage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.8))
            }
            Text(value)
                .font(Face.display(22, .bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(Face.body(10.5))
                .foregroundStyle(Palette.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A proportion drawn as a rounded track — used for accuracy and time left.
struct Meter: View {
    let fraction: Double
    var tint: Color = Palette.accent
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.sunken)
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(height, geo.size.width * max(0, min(1, fraction))))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Clock

/// Countdown as a ring — reads as time remaining at a glance, which a bar does
/// not when it is the only clock on screen.
struct Countdown: View {
    let remaining: Int
    let total: Int

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return max(0, min(1, Double(remaining) / Double(total)))
    }

    private var tint: Color {
        remaining <= 30 ? Palette.danger : (remaining <= 60 ? Palette.warning : Palette.accent)
    }

    private var label: String {
        guard remaining > 0 else { return "0:00" }
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.sunken, lineWidth: 4)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: fraction)
            Text(label)
                .font(Face.mono(12, .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 46, height: 46)
        .accessibilityLabel("Time remaining \(label)")
    }
}

/// `M:SS` for cooldowns and grants, where a ring would be overkill.
func clockText(_ seconds: Int) -> String {
    if seconds >= 3600 {
        return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
    }
    if seconds >= 60 {
        return "\(seconds / 60)m"
    }
    return "\(max(0, seconds))s"
}
