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

/// The ready-made looks, plus "match system" and "custom".
enum ThemeChoice: String, CaseIterable, Identifiable, Sendable {
    case system, obsidian, ivory, midnight, forest, ember, sakura, layla, ecrin, custom

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
        case .sakura: "Soft blush, rose accents"
        case .layla: "Tiffany baby pink"
        case .ecrin: "Jewel-box red and gold"
        case .custom: "Build your own"
        }
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
        case .system, .custom: nil
        }
    }

    static func resolve(_ id: String, custom: CustomThemeSpec, systemIsDark: Bool) -> ThemePalette {
        switch ThemeChoice(rawValue: id) ?? .obsidian {
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

    static let sakura = ThemePalette(
        isDark: false, background: "FAF4F3", paper: "FFFAF9", raised: "FFFFFF", sunken: "F1E6E4",
        ink: "2A1E21", secondaryInk: "7D6C70", line: "E8D8D6", strongLine: "D6C0BE",
        accent: "C46E7E", accentHighlight: "9E4E5D", onAccent: "FFFFFF", rest: "6E9488", longRest: "8A82B0")
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
