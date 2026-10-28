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
    private(set) var saved: [SharedTheme]
    @ObservationIgnored private var appearanceObserver: NSObjectProtocol?

    private static let cacheKey = "pomofocus.theme.v1"

    private struct Cached: Codable { var themeID: String; var custom: CustomThemeSpec; var saved: [SharedTheme]? }

    private init() {
        // The last theme is cached in defaults, so the first frame is already right
        // instead of flashing dark while the data file loads.
        let cached = UserDefaults.standard.data(forKey: Self.cacheKey).flatMap { try? JSONDecoder().decode(Cached.self, from: $0) }
        themeID = cached?.themeID ?? ThemeChoice.obsidian.rawValue
        custom = cached?.custom ?? CustomThemeSpec()
        saved = cached?.saved ?? []
        resolved = ResolvedTheme(ThemeChoice.resolve(cached?.themeID ?? "obsidian", custom: cached?.custom ?? CustomThemeSpec(),
                                                     systemIsDark: Self.systemIsDark, saved: cached?.saved ?? []))
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
    func apply(themeID: String, custom: CustomThemeSpec, saved: [SharedTheme]? = nil) {
        let saved = saved ?? self.saved
        let palette = ThemeChoice.resolve(themeID, custom: custom, systemIsDark: Self.systemIsDark, saved: saved)
        if themeID != self.themeID { self.themeID = themeID }
        if custom != self.custom { self.custom = custom }
        if saved != self.saved { self.saved = saved }
        if palette != resolved.palette { resolved = ResolvedTheme(palette) }
        if let data = try? JSONEncoder().encode(Cached(themeID: themeID, custom: custom, saved: saved)) {
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
            ZStack {
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
            // Window-sized gradients are shaded on the graphics chip. Drawn on the CPU they
            // were the single biggest cost of a theme change.
            .drawingGroup()
            switch ThemeManager.shared.themeID {
            case ThemeChoice.sakura.rawValue: SakuraBlossoms()
            case ThemeChoice.autumn.rawValue: AutumnScene()
            case ThemeChoice.blackIce.rawValue: BlackIceScene()
            case ThemeChoice.bespoke.rawValue: Pinstripe()
            default: EmptyView()
            }
        }
        .ignoresSafeArea()
    }
}

/// The Sakura theme's scene: white cherry-blossom branches reaching in from two corners,
/// drawn once, and a handful of petals drifting slowly down. Only the petals move, at a
/// gentle frame rate, and they stop when the window isn't in front or Reduce Motion is on.
private struct SakuraBlossoms: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        ZStack {
            Canvas { context, size in SakuraArt.drawBranches(in: &context, size: size) }
            if !reduceMotion {
                FallingParticles(images: SakuraArt.petalImages, birthRate: 0.5, speed: 20,
                                 running: activeState != .inactive)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum SakuraArt {
    static let petalWhite = Color(hex: "FFF7F8")
    static let petalBlush = Color(hex: "FBE1E5")
    static let heart = Color(hex: "E07F92")
    static let stamen = Color(hex: "E9B35F")
    static let bud = Color(hex: "D9677F")
    static let bark = Color(hex: "6E4540")

    /// A small, repeatable random sequence, so the scene looks the same every launch.
    struct Seeded {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
    }

    // MARK: Branches

    static func drawBranches(in context: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        let scale = max(0.7, min(1.3, min(w, h) / 820))
        // Top right: a bough from the corner, with a twig hanging down the right edge.
        branch(&context, from: CGPoint(x: w + 20, y: -20), via: CGPoint(x: w * 0.86, y: h * 0.10),
               to: CGPoint(x: w * 0.64, y: h * 0.07), width: 6 * scale, seed: 3, scale: scale)
        branch(&context, from: CGPoint(x: w * 0.93, y: h * 0.05), via: CGPoint(x: w * 0.99, y: h * 0.24),
               to: CGPoint(x: w * 0.95, y: h * 0.40), width: 3.5 * scale, seed: 7, scale: scale)
        // Bottom left: the same, mirrored.
        branch(&context, from: CGPoint(x: -20, y: h + 20), via: CGPoint(x: w * 0.16, y: h * 0.86),
               to: CGPoint(x: w * 0.40, y: h * 0.95), width: 6 * scale, seed: 11, scale: scale)
        branch(&context, from: CGPoint(x: w * 0.06, y: h * 0.97), via: CGPoint(x: w * 0.0, y: h * 0.76),
               to: CGPoint(x: w * 0.06, y: h * 0.58), width: 3.5 * scale, seed: 19, scale: scale)
    }

    private static func branch(_ context: inout GraphicsContext, from start: CGPoint, via control: CGPoint, to end: CGPoint,
                               width: Double, seed: UInt64, scale: Double) {
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        context.stroke(path, with: .color(bark.opacity(0.55)), style: StrokeStyle(lineWidth: width, lineCap: .round))
        context.stroke(path, with: .color(bark.opacity(0.35)), style: StrokeStyle(lineWidth: width * 0.45, lineCap: .round))

        var random = Seeded(state: seed)
        func point(_ t: Double) -> CGPoint {
            let a = (1 - t) * (1 - t), b = 2 * (1 - t) * t, c = t * t
            return CGPoint(x: a * start.x + b * control.x + c * end.x, y: a * start.y + b * control.y + c * end.y)
        }
        // Blossoms crowd along the bough, a little off the line, with buds between.
        let count = 11
        for index in 0..<count {
            let t = 0.12 + 0.88 * Double(index) / Double(count - 1)
            let base = point(t)
            let spread = (18 + random.next() * 22) * scale
            let angle = random.next() * .pi * 2
            let center = CGPoint(x: base.x + cos(angle) * spread * 0.6, y: base.y + sin(angle) * spread * 0.6)
            if random.next() < 0.22 {
                drawBud(&context, at: center, radius: (5 + random.next() * 3) * scale, turn: random.next() * 360)
            } else {
                drawBlossom(&context, at: center, radius: (13 + random.next() * 10) * scale,
                            turn: random.next() * 72, blush: random.next() < 0.35)
            }
        }
    }

    /// Five petals, each rounded with the small notch at its tip that makes it a sakura.
    static func petalPath(radius r: Double) -> Path {
        var path = Path()
        path.move(to: .zero)
        path.addCurve(to: CGPoint(x: -r * 0.1, y: -r),
                      control1: CGPoint(x: -r * 0.62, y: -r * 0.28), control2: CGPoint(x: -r * 0.58, y: -r * 1.0))
        path.addLine(to: CGPoint(x: 0, y: -r * 0.84))
        path.addLine(to: CGPoint(x: r * 0.1, y: -r))
        path.addCurve(to: .zero,
                      control1: CGPoint(x: r * 0.58, y: -r * 1.0), control2: CGPoint(x: r * 0.62, y: -r * 0.28))
        return path
    }

    private static func drawBlossom(_ context: inout GraphicsContext, at center: CGPoint, radius: Double, turn: Double, blush: Bool) {
        var flower = context
        flower.translateBy(x: center.x, y: center.y)
        flower.rotate(by: .degrees(turn))
        let petal = petalPath(radius: radius)
        for index in 0..<5 {
            var leaf = flower
            leaf.rotate(by: .degrees(Double(index) * 72))
            leaf.fill(petal, with: .color(blush ? petalBlush : petalWhite))
            leaf.stroke(petal, with: .color(heart.opacity(0.18)), lineWidth: 0.6)
        }
        // A pink heart with a ring of stamens.
        flower.fill(Path(ellipseIn: CGRect(x: -radius * 0.22, y: -radius * 0.22, width: radius * 0.44, height: radius * 0.44)),
                    with: .color(heart.opacity(0.85)))
        for index in 0..<7 {
            let a = Double(index) / 7 * .pi * 2
            let tip = CGPoint(x: cos(a) * radius * 0.36, y: sin(a) * radius * 0.36)
            var line = Path()
            line.move(to: .zero)
            line.addLine(to: tip)
            flower.stroke(line, with: .color(heart.opacity(0.6)), lineWidth: 0.6)
            flower.fill(Path(ellipseIn: CGRect(x: tip.x - 1.2, y: tip.y - 1.2, width: 2.4, height: 2.4)), with: .color(stamen))
        }
    }

    private static func drawBud(_ context: inout GraphicsContext, at center: CGPoint, radius: Double, turn: Double) {
        var shape = context
        shape.translateBy(x: center.x, y: center.y)
        shape.rotate(by: .degrees(turn))
        shape.fill(Path(ellipseIn: CGRect(x: -radius * 0.6, y: -radius, width: radius * 1.2, height: radius * 1.6)), with: .color(bud.opacity(0.9)))
        shape.fill(Path(ellipseIn: CGRect(x: -radius * 0.45, y: radius * 0.3, width: radius * 0.9, height: radius * 0.6)), with: .color(bark.opacity(0.6)))
    }

    // MARK: Falling petals

    /// White and blush petals for the emitter, rendered once.
    @MainActor static let petalImages: [CGImage] = [
        ParticleImage.make(SakuraPetal(), color: petalWhite.opacity(0.9), size: 26),
        ParticleImage.make(SakuraPetal(), color: petalBlush.opacity(0.9), size: 22),
    ].compactMap { $0 }

}

struct NonnaCard<Content: View>: View {
    var padding: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            // The paper and its shadow are one plain shape behind the content, not a shadow
            // of the content. A shadow of the content would be blurred again on the CPU every
            // frame anything inside the card moved, which is what made the timer card stutter
            // when the phase changed. The picture is the same: the card is this shape.
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(NonnaTheme.paper.opacity(0.94))
                    .shadow(color: NonnaTheme.shadow, radius: 18, y: 10)
            }
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
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
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

/// One cell of a stat grid: icon chip, label, number, and a fading trend line. It draws
/// no background or border of its own; the grid around it supplies those, so several
/// cells read as one surface split by hairlines.
struct MetricCard: View {
    let icon: String
    let label: String
    let value: String
    let detail: String
    var tint: Color = NonnaTheme.terracotta
    var trends: [MetricTrend] = []
    /// Room kept clear at the top right for controls laid over the cell.
    var trailingInset: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                IconChip(systemName: icon, tint: tint)
                Spacer(minLength: trailingInset)
            }
            .padding(.bottom, 16)

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NonnaTheme.secondaryInk)
                .lineLimit(1)
                .padding(.bottom, 4)

            Text(value)
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(NonnaTheme.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75), value: value)
                .padding(.bottom, 10)

            // Always the same height, so cells in a row line up with or without a trend.
            TrendTicker(trends: trends)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A round, tinted chip holding one symbol: soft fill, slightly stronger ring, full-tint glyph.
struct IconChip: View {
    let systemName: String
    var tint: Color = NonnaTheme.terracotta
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.41, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.2), in: Circle())
            .overlay { Circle().stroke(tint.opacity(0.4), lineWidth: 0.8) }
            .accessibilityHidden(true)
    }
}

/// A one-point rule that fades to nothing at both ends, for splitting a surface into
/// cells without boxing each one in.
struct FadingHairline: View {
    enum Axis { case horizontal, vertical }
    var axis: Axis = .horizontal
    var color: Color = NonnaTheme.line

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: axis == .vertical ? 1 : nil, height: axis == .horizontal ? 1 : nil)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.22),
                        .init(color: .black, location: 0.78),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: axis == .horizontal ? .leading : .top,
                    endPoint: axis == .horizontal ? .trailing : .bottom
                )
            }
            .accessibilityHidden(true)
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


/// One falling sakura petal: rounded, with the notch at its tip.
struct SakuraPetal: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) * 0.48
        let transform = CGAffineTransform(translationX: rect.midX, y: rect.midY + r * 0.5)
        return SakuraArt.petalPath(radius: r).applying(transform)
    }
}
