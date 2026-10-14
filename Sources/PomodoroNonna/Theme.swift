import AppKit
import SwiftUI

/// The colours of the current theme, resolved to SwiftUI colours once per change.
struct ResolvedTheme: Sendable {
    let palette: ThemePalette
    let background, paper, raised, sunken, ink, secondaryInk, line, strongLine: Color
    let accent, accentHighlight, onAccent, rest, longRest: Color

    init(_ p: ThemePalette) {
        palette = p
        background = Color(hex: p.background); paper = Color(hex: p.paper); raised = Color(hex: p.raised)
        sunken = Color(hex: p.sunken); ink = Color(hex: p.ink); secondaryInk = Color(hex: p.secondaryInk)
        line = Color(hex: p.line); strongLine = Color(hex: p.strongLine)
        accent = Color(hex: p.accent); accentHighlight = Color(hex: p.accentHighlight); onAccent = Color(hex: p.onAccent)
        rest = Color(hex: p.rest); longRest = Color(hex: p.longRest)
    }
}

/// Holds the active theme. It is observable, so any view that reads a `NonnaTheme`
/// colour redraws when the theme changes, and only then.
@Observable
final class ThemeManager: @unchecked Sendable {
    static let shared = ThemeManager()

    private(set) var resolved: ResolvedTheme
    private(set) var themeID: String
    private(set) var custom: CustomThemeSpec
    @ObservationIgnored private var appearanceObserver: NSObjectProtocol?

    private static let cacheKey = "pomofocus.theme.v1"

    private struct Cached: Codable { var themeID: String; var custom: CustomThemeSpec }

    private init() {
        // The last theme is cached in defaults, so the first frame is already right
        // instead of flashing dark while the data file loads.
        let cached = UserDefaults.standard.data(forKey: Self.cacheKey).flatMap { try? JSONDecoder().decode(Cached.self, from: $0) }
        themeID = cached?.themeID ?? ThemeChoice.obsidian.rawValue
        custom = cached?.custom ?? CustomThemeSpec()
        resolved = ResolvedTheme(ThemeChoice.resolve(cached?.themeID ?? "obsidian", custom: cached?.custom ?? CustomThemeSpec(),
                                                     systemIsDark: Self.systemIsDark))
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshForSystem() }
        }
    }

    static var systemIsDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle")?.lowercased() == "dark"
    }

    @MainActor
    func apply(themeID: String, custom: CustomThemeSpec) {
        let palette = ThemeChoice.resolve(themeID, custom: custom, systemIsDark: Self.systemIsDark)
        if themeID != self.themeID { self.themeID = themeID }
        if custom != self.custom { self.custom = custom }
        if palette != resolved.palette { resolved = ResolvedTheme(palette) }
        if let data = try? JSONEncoder().encode(Cached(themeID: themeID, custom: custom)) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    @MainActor
    private func refreshForSystem() {
        // macOS posts this before the new value lands in defaults.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            if themeID == ThemeChoice.system.rawValue { apply(themeID: themeID, custom: custom) }
        }
    }
}

enum NonnaTheme {
    private static var t: ResolvedTheme { ThemeManager.shared.resolved }

    static var cream: Color { t.background }
    static var paper: Color { t.paper }
    static var raisedPaper: Color { t.raised }
    static var sunken: Color { t.sunken }
    static var ink: Color { t.ink }
    static var secondaryInk: Color { t.secondaryInk }
    static var terracotta: Color { t.accent }
    static var darkTerracotta: Color { t.accentHighlight }
    /// Text and icons on top of the accent colour.
    static var onAccent: Color { t.onAccent }
    static var sage: Color { t.rest }
    static var gold: Color { t.longRest }
    static var line: Color { t.line }
    static var strongLine: Color { t.strongLine }
    static var isDark: Bool { t.palette.isDark }
    static var colorScheme: ColorScheme { isDark ? .dark : .light }
    static var shadow: Color { Color.black.opacity(isDark ? 0.46 : 0.1) }
    /// Master-caution red, used only for the overtime alert.
    static let alert = Color(hex: "FF453A")

    static func accent(for phase: TimerPhase) -> Color {
        switch phase {
        case .focus: terracotta
        case .shortBreak: sage
        case .longBreak: gold
        }
    }

    static func taskColor(for hex: String) -> Color {
        let refinedHex = switch hex.uppercased() {
        case "D7684D": "BDA56F"
        case "557A68": "738B80"
        case "C79545": "A9A4B5"
        case "6A7696": "788897"
        case "9A6078": "8F7581"
        case "607D8B": "6F858F"
        case "7C6D5C": "837765"
        default: hex
        }
        return Color(hex: refinedHex)
    }
}

enum NonnaMotion {
    static let quick = Animation.snappy(duration: 0.22, extraBounce: 0.02)
    static let selection = Animation.spring(duration: 0.42, bounce: 0.12)
    static let settle = Animation.spring(duration: 0.58, bounce: 0.08)
    static let page = Animation.easeInOut(duration: 0.28)
    static let numeric = Animation.easeInOut(duration: 0.24)
}

/// Gives cautions a slow, restrained pulse. With Reduce Motion on, it holds steady.
struct AlertFlash: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let period = 1.35

    func body(content: Content) -> some View {
        let flashing = active && !reduceMotion
        TimelineView(.animation(minimumInterval: Self.period, paused: !flashing)) { context in
            let lit = !flashing || Int(context.date.timeIntervalSinceReferenceDate / Self.period) % 2 == 0
            content
                .opacity(lit ? 1 : 0.62)
                .animation(flashing ? .easeInOut(duration: 0.72) : nil, value: lit)
        }
    }
}

extension View {
    func alertFlash(_ active: Bool) -> some View { modifier(AlertFlash(active: active)) }
}

struct NonnaBackground: View {
    var body: some View {
        ZStack {
            NonnaTheme.cream
            RadialGradient(
                colors: [NonnaTheme.terracotta.opacity(0.055), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 820
            )
            RadialGradient(
                colors: [Color(hex: "384752").opacity(0.055), .clear],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 760
            )
            LinearGradient(
                colors: [.white.opacity(0.012), .clear, .black.opacity(0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

struct NonnaCard<Content: View>: View {
    var padding: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(NonnaTheme.paper.opacity(0.94))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.075), NonnaTheme.line.opacity(0.78)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
            }
            .shadow(color: NonnaTheme.shadow, radius: 18, y: 10)
    }
}

struct NonnaButtonStyle: ButtonStyle {
    var color: Color = NonnaTheme.terracotta
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        NonnaButtonBody(configuration: configuration, color: color, prominent: prominent)
    }
}

private struct NonnaButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let color: Color
    let prominent: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(prominent ? NonnaTheme.onAccent : NonnaTheme.ink)
            .padding(.horizontal, 17)
            .frame(minHeight: 40)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(prominent ? color : NonnaTheme.raisedPaper)
                    .overlay {
                        LinearGradient(
                            colors: [.white.opacity(isHovering ? 0.11 : 0.055), .clear, .black.opacity(0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(
                        prominent ? Color.white.opacity(isHovering ? 0.19 : 0.1) : (isHovering ? NonnaTheme.strongLine : NonnaTheme.line),
                        lineWidth: 0.8
                    )
            }
            .shadow(
                color: prominent ? color.opacity(isHovering ? 0.24 : 0.12) : .black.opacity(isHovering ? 0.24 : 0.08),
                radius: isHovering ? 16 : 9,
                y: isHovering ? 7 : 4
            )
            .scaleEffect(configuration.isPressed ? 0.97 : (isHovering ? 1.018 : 1))
            .offset(y: configuration.isPressed ? 1 : 0)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : NonnaMotion.quick, value: configuration.isPressed)
            .animation(reduceMotion ? nil : NonnaMotion.quick, value: isHovering)
            .onHover { isHovering = $0 }
    }
}

struct SectionHeading: View {
    let eyebrow: String
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(NonnaTheme.terracotta)
            Text(title)
                .font(.system(size: 29, weight: .semibold))
                .foregroundStyle(NonnaTheme.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
        }
    }
}

struct MetricCard: View {
    let icon: String
    let label: String
    let value: String
    let detail: String
    var tint: Color = NonnaTheme.terracotta

    var body: some View {
        NonnaCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(tint)
                        .frame(width: 24, height: 24)
                    Spacer()
                }
                Text(value)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(NonnaTheme.ink)
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(NonnaTheme.ink)
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
            }
        }
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(NonnaTheme.terracotta)
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .default))
                .foregroundStyle(NonnaTheme.ink)
            Text(message)
                .multilineTextAlignment(.center)
                .font(.system(size: 13, design: .default))
                .foregroundStyle(NonnaTheme.secondaryInk)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, minHeight: 190)
    }
}

/// Sixty minute marks as a single shape: one path and one fill instead of sixty views.
/// Each mark is a capsule centred `radius` points from the middle, pointing outward,
/// matching the old `Capsule().offset(y: -radius).rotationEffect(...)` layout.
struct DialTicks: Shape {
    let radius: CGFloat
    /// `true` draws only the five-minute marks, `false` only the minute marks.
    let major: Bool
    let majorSize: CGSize
    let minorSize: CGSize

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let size = major ? majorSize : minorSize
        let mark = CGRect(x: -size.width / 2, y: -radius - size.height / 2, width: size.width, height: size.height)
        let capsule = Path(roundedRect: mark, cornerRadius: size.width / 2)
        var path = Path()
        for tick in 0..<60 where (tick % 5 == 0) == major {
            let turn = CGAffineTransform(rotationAngle: CGFloat(tick) * .pi / 30)
                .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
            path.addPath(capsule, transform: turn)
        }
        return path
    }
}

/// A clock readout whose digits roll as they change, like `.numericText()`, but built
/// from per-character offset and opacity transitions. Those are plain layer transforms
/// the GPU composites; `.numericText()` re-renders its interpolated glyphs on the CPU
/// at display refresh rate after every tick, which was most of the app's running cost.
struct RollingClockText: View {
    let text: String
    var countsDown = true
    /// How far a digit travels as it rolls in or out.
    var travel: CGFloat = 18
    var animation: Animation? = NonnaMotion.numeric

    var body: some View {
        let characters = Array(text)
        HStack(spacing: 0) {
            // Slots are keyed from the right, so "9:59" → "10:00" keeps seconds in place.
            ForEach(characters.indices, id: \.self) { index in
                let slot = characters.count - index
                ZStack {
                    Text(String(characters[index]))
                        .id("\(slot)-\(characters[index])")
                        .transition(.asymmetric(
                            insertion: .offset(y: countsDown ? -travel : travel).combined(with: .opacity),
                            removal: .offset(y: countsDown ? travel : -travel).combined(with: .opacity)
                        ))
                }
                .id(slot)
            }
        }
        .animation(animation, value: text)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// True when the content area is too narrow for side-by-side cards. Sections read this to
/// stack their columns, so the window can be made small without anything clipping.
private struct CompactLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var compactLayout: Bool {
        get { self[CompactLayoutKey.self] }
        set { self[CompactLayoutKey.self] = newValue }
    }
}

/// Columns side by side when there's room, stacked when the window is narrow. One layout
/// value keeps each card's identity, so the switch animates instead of rebuilding.
struct AdaptiveColumns<Content: View>: View {
    let compact: Bool
    var spacing: CGFloat = 18
    @ViewBuilder let content: Content

    init(_ compact: Bool, spacing: CGFloat = 18, @ViewBuilder content: () -> Content) {
        self.compact = compact
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        let layout = compact
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: .top, spacing: spacing))
        layout { content }
    }
}
