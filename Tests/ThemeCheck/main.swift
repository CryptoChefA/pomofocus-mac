import CryptoKit
import Foundation

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

func ratio(_ a: String, _ b: String) -> Double { RGB(hex: a).contrast(with: RGB(hex: b)) }

let presets = ThemeChoice.allCases.compactMap { choice in choice.palette.map { (choice.title, $0) } }
check(presets.count == 12, "twelve fixed presets")
for (name, p) in presets {
    check(ratio(p.ink, p.background) >= 12, "\(name): body text is crisp (\(ratio(p.ink, p.background)))")
    check(ratio(p.ink, p.paper) >= 10, "\(name): text on cards is crisp")
    check(ratio(p.secondaryInk, p.background) >= 3.6, "\(name): secondary text is readable (\(ratio(p.secondaryInk, p.background)))")
    check(ratio(p.onAccent, p.accent) >= 3.0, "\(name): button labels read on the accent (\(ratio(p.onAccent, p.accent)))")
    check(ratio(p.accent, p.background) >= 3.0, "\(name): the accent stands out (\(ratio(p.accent, p.background)))")
}
check(ratio(ThemePalette.layla.rest, ThemePalette.layla.background) >= 3.0, "Layla: break pink reads on the background")
check(RGB(hex: ThemePalette.layla.rest).luminance < RGB(hex: ThemePalette.layla.accent).luminance, "Layla: breaks are a darker pink than focus")
check(!ThemePalette.layla.isDark && !ThemePalette.ivory.isDark && !ThemePalette.sakura.isDark && ThemePalette.obsidian.isDark, "light and dark presets are flagged correctly")

// Match system follows macOS.
check(ThemeChoice.resolve("system", custom: CustomThemeSpec(), systemIsDark: true) == .obsidian, "system dark → Obsidian")
check(ThemeChoice.resolve("system", custom: CustomThemeSpec(), systemIsDark: false) == .ivory, "system light → Ivory")
check(ThemeChoice.resolve("nonsense", custom: CustomThemeSpec(), systemIsDark: false) == .obsidian, "unknown ids fall back to Obsidian")

// Custom themes derive readable surfaces for typical choices.
for spec in [CustomThemeSpec(), CustomThemeSpec.lightStarter,
             CustomThemeSpec(isDark: true, background: "101820", accent: "F2AA4C", rest: "6BA292"),
             CustomThemeSpec(isDark: false, background: "FFFFFF", accent: "2F6FED", rest: "2BA84A")] {
    let p = spec.palette
    check(ratio(p.ink, p.background) >= 12, "custom \(spec.background): body text is crisp")
    check(ratio(p.secondaryInk, p.background) >= 3.6, "custom \(spec.background): secondary text readable (\(ratio(p.secondaryInk, p.background)))")
    check(ratio(p.onAccent, p.accent) >= 3.0, "custom \(spec.accent): label on accent readable (\(ratio(p.onAccent, p.accent)))")
    check(p.background == RGB(hex: spec.background).hex, "custom keeps the chosen background")
}
check(RGB(hex: "BDA56F").hex == "BDA56F" && RGB(hex: "#0d0f11").hex == "0D0F11", "hex round-trips")

// Theme codes: anyone can share a custom theme; only the developer's key can make a rare one.
let mine = SharedTheme(id: UUID(), name: "Sam's theme", note: nil,
                       spec: CustomThemeSpec(isDark: true, background: "0A0B0C", accent: "C9A55A", rest: "6E9488"), isRare: false)
if case .success(let back) = ThemeCodes.theme(from: ThemeCodes.code(for: mine)) {
    check(back == mine, "a shared code brings back the same theme")
} else { check(false, "a shared code decodes") }
check(ThemeCodes.theme(from: "hello") == .failure(.notACode), "random text isn't a code")
check(ThemeCodes.theme(from: ThemeCodes.plainPrefix + "!!!") == .failure(.damaged), "a cut-off code is reported as damaged")

let devKey = Curve25519.Signing.PrivateKey()
let devPublic = devKey.publicKey.rawRepresentation.base64EncodedString()
var gift = mine; gift.name = "Garden"; gift.note = "For Layla"; gift.isRare = true
let rare = try! ThemeCodes.rareCode(for: gift, signingKey: devKey)
if case .success(let back) = ThemeCodes.theme(from: rare, publicKey: devPublic) {
    check(back.isRare && back.note == "For Layla" && back.spec == gift.spec, "a genuine rare code unlocks its theme")
} else { check(false, "a genuine rare code is accepted") }
let forged = try! ThemeCodes.rareCode(for: gift, signingKey: Curve25519.Signing.PrivateKey())
check(ThemeCodes.theme(from: forged, publicKey: devPublic) == .failure(.notGenuine), "a code signed by anyone else is refused")
var tampered = rare; tampered.insert("x", at: tampered.index(tampered.startIndex, offsetBy: 20))
check(ThemeCodes.theme(from: tampered, publicKey: devPublic) != .success(gift), "a changed rare code is refused")
check(ThemeChoice.resolve(gift.themeID, custom: CustomThemeSpec(), systemIsDark: false, saved: [gift]) == gift.spec.palette, "a saved theme resolves to its palette")

print("Theme checks passed")
