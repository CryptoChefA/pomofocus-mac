import Foundation

/// Every colour the interface draws with, as sRGB hex. Views never read this directly;
/// they go through `NonnaTheme`, which follows whichever palette is active.
struct ThemePalette: Equatable, Sendable {
    var isDark: Bool
    var background: String
    var paper: String
    var raised: String
    var sunken: String
    var ink: String
    var secondaryInk: String
    var line: String
    var strongLine: String
    /// Focus colour, buttons, highlights.
    var accent: String
    var accentHighlight: String
    /// Text and icons drawn on top of the accent.
    var onAccent: String
    /// Short-break colour.
    var rest: String
    /// Long-break colour.
    var longRest: String
}

/// A theme someone builds themselves: a base, a background, and two colours. Everything
/// else (surfaces, lines, text) is derived so it always hangs together.
struct CustomThemeSpec: Codable, Equatable, Sendable {
    var isDark = true
    var background = "060708"
    var accent = "BDA56F"
    var rest = "738B80"

    static let lightStarter = CustomThemeSpec(isDark: false, background: "F5F2EA", accent: "A0833F", rest: "5E7F70")

    var palette: ThemePalette {
        let bg = RGB(hex: background)
        let accentColor = RGB(hex: accent)
        let restColor = RGB(hex: rest)
        let ink = RGB(hex: isDark ? "F1EFE9" : "1D1B17")
        let white = RGB(r: 1, g: 1, b: 1), black = RGB(r: 0, g: 0, b: 0)
        return ThemePalette(
            isDark: isDark,
            background: bg.hex,
            paper: (isDark ? bg.mixed(with: white, 0.035) : bg.mixed(with: white, 0.5)).hex,
            raised: (isDark ? bg.mixed(with: white, 0.07) : bg.mixed(with: white, 0.85)).hex,
            sunken: (isDark ? bg.mixed(with: black, 0.3) : bg.mixed(with: black, 0.04)).hex,
            ink: ink.hex,
            secondaryInk: bg.mixed(with: ink, isDark ? 0.52 : 0.58).hex,
            line: bg.mixed(with: ink, isDark ? 0.12 : 0.13).hex,
            strongLine: bg.mixed(with: ink, isDark ? 0.19 : 0.22).hex,
            accent: accentColor.hex,
            accentHighlight: (isDark ? accentColor.mixed(with: white, 0.3) : accentColor.mixed(with: black, 0.22)).hex,
            // Whichever of near-black or near-white reads better on the accent.
            onAccent: accentColor.contrast(with: RGB(hex: "0E0D0B")) >= accentColor.contrast(with: RGB(hex: "FFFDF8")) ? "0E0D0B" : "FFFDF8",
            rest: restColor.hex,
            longRest: restColor.mixed(with: accentColor, 0.45).hex
        )
    }
}

/// A theme that came from a code: someone's custom theme, or a rare one from the developer.
struct SharedTheme: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    /// A line from whoever made it, like "For Sam, from Alex". Rare themes only.
    var note: String?
    var spec: CustomThemeSpec
    /// Signed by the developer's key; can't be made by anyone else.
    var isRare: Bool

    /// The value stored in `themeID` while this theme is in use.
    var themeID: String { SharedTheme.prefix + id.uuidString }
    static let prefix = "saved:"
}

/// The ready-made looks, plus "match system" and "custom".
enum ThemeChoice: String, CaseIterable, Identifiable, Sendable {
    case system, obsidian, ivory, midnight, forest, ember, sakura, layla, ecrin, piano, bespoke, autumn, blackIce, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Match system"
        case .obsidian: "Obsidian"
        case .ivory: "Ivory"
        case .midnight: "Midnight"
        case .forest: "Forest"
        case .ember: "Ember"
        case .sakura: "Sakura"
        case .layla: "Layla"
        case .ecrin: "Écrin"
        case .piano: "Piano"
        case .bespoke: "Bespoke"
        case .autumn: "Autumn"
        case .blackIce: "Black Ice"
        case .custom: "Custom"
        }
    }

    var subtitle: String {
        switch self {
        case .system: "Obsidian or Ivory, with macOS"
        case .obsidian: "Graphite and champagne gold"
        case .ivory: "Warm paper, quiet gold"
        case .midnight: "Deep navy, silver blue"
        case .forest: "Pine dark, soft sage"
        case .ember: "Warm dark, glowing coral"
        case .sakura: "Blossom pink, white sakura, falling petals"
        case .layla: "Tiffany baby pink"
        case .ecrin: "Jewel-box red and gold"
        case .piano: "Ivory dial, Roman numerals, blued hands"
        case .bespoke: "Black, graphite and white, tailored"
        case .autumn: "Limited edition: falling leaves"
        case .blackIce: "Black and ice blue, frost and snow"
        case .custom: "Build your own"
        }
    }

    /// Limited editions only appear in the picker in their season (or while in use).
    var isLimitedEdition: Bool { self == .autumn }

    func isAvailable(on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard self == .autumn else { return true }
        // September through November.
        return (9...11).contains(calendar.component(.month, from: date))
    }

    /// The palette for a fixed choice. `system` and `custom` are resolved elsewhere.
    var palette: ThemePalette? {
        switch self {
        case .obsidian: .obsidian
        case .ivory: .ivory
        case .midnight: .midnight
        case .forest: .forest
        case .ember: .ember
        case .sakura: .sakura
        case .layla: .layla
        case .ecrin: .ecrin
        case .piano: .piano
        case .bespoke: .bespoke
        case .autumn: .autumn
        case .blackIce: .blackIce
        case .system, .custom: nil
        }
    }

    static func resolve(_ id: String, custom: CustomThemeSpec, systemIsDark: Bool, saved: [SharedTheme] = []) -> ThemePalette {
        if id.hasPrefix(SharedTheme.prefix), let theme = saved.first(where: { $0.themeID == id }) {
            return theme.spec.palette
        }
        return switch ThemeChoice(rawValue: id) ?? .obsidian {
        case .system: systemIsDark ? .obsidian : .ivory
        case .custom: custom.palette
        case let choice: choice.palette ?? .obsidian
        }
    }
}

extension ThemePalette {
    static let obsidian = ThemePalette(
        isDark: true, background: "060708", paper: "0D0F11", raised: "14171A", sunken: "090B0D",
        ink: "F1EFE9", secondaryInk: "8A8F96", line: "24282D", strongLine: "343A40",
        accent: "BDA56F", accentHighlight: "D7C28F", onAccent: "060708", rest: "738B80", longRest: "A9A4B5")

    static let ivory = ThemePalette(
        isDark: false, background: "F5F2EA", paper: "FBF9F4", raised: "FFFFFF", sunken: "ECE7DC",
        ink: "1D1B17", secondaryInk: "6F6A61", line: "DDD6C8", strongLine: "C9C0AE",
        accent: "A0833F", accentHighlight: "7E6328", onAccent: "FFFDF8", rest: "5E7F70", longRest: "7D7894")

    static let midnight = ThemePalette(
        isDark: true, background: "05070D", paper: "0B0F18", raised: "121826", sunken: "080B13",
        ink: "EEF1F7", secondaryInk: "8590A3", line: "1E2636", strongLine: "2C3649",
        accent: "9DB2E8", accentHighlight: "C4D2F5", onAccent: "05070D", rest: "7FB0A8", longRest: "B4A7D6")

    static let forest = ThemePalette(
        isDark: true, background: "060A08", paper: "0C120F", raised: "131B17", sunken: "08100C",
        ink: "EDF2EE", secondaryInk: "879489", line: "1F2A24", strongLine: "2D3B33",
        accent: "9FBF8F", accentHighlight: "C7DDB9", onAccent: "060A08", rest: "8DB3A6", longRest: "C2B98A")

    static let ember = ThemePalette(
        isDark: true, background: "0A0605", paper: "120C0A", raised: "1A1310", sunken: "0E0907",
        ink: "F4EDE8", secondaryInk: "9A8D86", line: "2C221E", strongLine: "3D302A",
        accent: "E0895A", accentHighlight: "F2B28E", onAccent: "0A0605", rest: "8FA88F", longRest: "B79FC2")

    /// Layla's theme: the pastel baby pink of a Tiffany heart tag, a soft rose for focus
    /// that still reads clearly, and deeper rose and plum-pink for breaks.
    static let layla = ThemePalette(
        isDark: false, background: "FBE9EE", paper: "FFF5F8", raised: "FFFFFF", sunken: "F6DDE4",
        ink: "3A2229", secondaryInk: "86616C", line: "F1D2DA", strongLine: "E6BECA",
        accent: "C96B86", accentHighlight: "A9506A", onAccent: "FFFFFF", rest: "9E4A64", longRest: "8A4F7D")

    /// Écrin, French for a jewel case: the deep red leather of a fine jewellery box, gold
    /// tooling, a cream satin lining for text, rose gold for breaks and a ruby glow for
    /// long breaks.
    static let ecrin = ThemePalette(
        isDark: true, background: "160406", paper: "21070A", raised: "2C0B0F", sunken: "0F0204",
        ink: "F6ECDD", secondaryInk: "B8968C", line: "3A1418", strongLine: "4D1E22",
        accent: "D4B06A", accentHighlight: "EBD3A0", onAccent: "160406", rest: "E0A08C", longRest: "E0566A")

    /// Sakura, a Japanese spring: a dusty cherry-blossom pink behind white sakura branches
    /// and slowly falling petals, near-black sumi ink, a deep beni red for focus, matcha
    /// green for breaks and ai indigo for long breaks. Deeper and dustier than Layla's
    /// baby pink, and the blossoms do the rest.
    /// Autumn, a limited edition for the fall: warm parchment, oak-brown ink, burnt-orange
    /// focus, olive breaks and a deep cranberry for long breaks, with leaves falling.
    static let autumn = ThemePalette(
        isDark: false, background: "F3E7D6", paper: "FBF4EA", raised: "FFFFFF", sunken: "EADBC6",
        ink: "24170F", secondaryInk: "6E5644", line: "E0CFB8", strongLine: "CFB99C",
        accent: "B4501E", accentHighlight: "8C3A12", onAccent: "FFFFFF", rest: "66692A", longRest: "8C2E2A")

    /// Black Ice: near-black with glacier blues, frost creeping in from the corners and a
    /// slow fall of snow.
    static let blackIce = ThemePalette(
        isDark: true, background: "000000", paper: "050A11", raised: "0B141F", sunken: "000000",
        ink: "E9F6FF", secondaryInk: "7F97AD", line: "152435", strongLine: "1F3449",
        accent: "8FDDFF", accentHighlight: "C9F0FF", onAccent: "03060A", rest: "4FB6D6", longRest: "5D86E0")

    /// Piano, after a dress watch: an ivory dial, black Roman numerals and a railway minute
    /// track, with hands in blued steel; black-key graphite for breaks.
    static let piano = ThemePalette(
        isDark: false, background: "F6F4EE", paper: "FBFAF6", raised: "FFFFFF", sunken: "ECE9E0",
        ink: "101114", secondaryInk: "5C5D62", line: "DEDAD0", strongLine: "C8C3B6",
        accent: "22409A", accentHighlight: "152C70", onAccent: "FFFFFF", rest: "2B2D33", longRest: "5A6B85")

    /// Bespoke: a dark, tailored look. Near-black like a midnight suit, graphite greys,
    /// crisp white and a silver accent; a faint pinstripe in the background.
    static let bespoke = ThemePalette(
        isDark: true, background: "0B0B0C", paper: "141416", raised: "1C1C1F", sunken: "070708",
        ink: "EDEDED", secondaryInk: "8E8E93", line: "26262A", strongLine: "38383D",
        accent: "D8D8DC", accentHighlight: "FFFFFF", onAccent: "0B0B0C", rest: "7A7A80", longRest: "A8A8AE")

    static let sakura = ThemePalette(
        isDark: false, background: "F0C2C7", paper: "FCF1F2", raised: "FFFFFF", sunken: "E8B4BA",
        ink: "180A0D", secondaryInk: "6A3A43", line: "E2A9B0", strongLine: "D4969E",
        accent: "A32E4C", accentHighlight: "7E1E37", onAccent: "FFFFFF", rest: "4A6A2C", longRest: "33507A")
}

/// Minimal sRGB maths for deriving custom palettes.
struct RGB: Equatable, Sendable {
    var r: Double, g: Double, b: Double

    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        if cleaned.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        } else {
            r = 0.5; g = 0.5; b = 0.5
        }
    }

    var hex: String {
        func byte(_ v: Double) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    func mixed(with other: RGB, _ amount: Double) -> RGB {
        RGB(r: r + (other.r - r) * amount, g: g + (other.g - g) * amount, b: b + (other.b - b) * amount)
    }

    /// Relative luminance (WCAG).
    var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// WCAG contrast ratio between two colours (1…21).
    func contrast(with other: RGB) -> Double {
        let a = luminance + 0.05, b = other.luminance + 0.05
        return max(a, b) / min(a, b)
    }
}
