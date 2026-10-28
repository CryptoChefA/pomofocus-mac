import CryptoKit
import Foundation

/// Turns themes into short codes and back.
///
/// - Plain: `PF-THEME-1.<payload>`, made by anyone from a custom theme.
/// - Rare: `PF-RARE-1.<payload>.<signature>`, signed with the developer's Ed25519 key. The
///   app only holds the public half, which can check a code but never make one, so rare
///   themes stay rare even though the app is open source.
enum ThemeCodes {
    static let plainPrefix = "PF-THEME-1."
    static let rarePrefix = "PF-RARE-1."

    /// The developer's public key (Curve25519 / Ed25519, raw, base64). The private key lives
    /// only on the developer's Mac, outside this repository.
    static let developerPublicKey = "/M9NeDZAeZFYOblzXhDO3cxieQtvsR8mpI3pfl1IVPw="

    private struct Payload: Codable {
        var id: UUID
        var name: String
        var note: String?
        var dark: Bool
        var background: String
        var accent: String
        var rest: String
    }

    enum Problem: Error, Equatable {
        case notACode, damaged, notGenuine

        var message: String {
            switch self {
            case .notACode: "That doesn't look like a Pomofocus theme code."
            case .damaged: "That code is incomplete. Copy the whole thing and try again."
            case .notGenuine: "That rare code isn't genuine, so it can't be added."
            }
        }
    }

    // MARK: Making codes

    static func code(for theme: SharedTheme) -> String {
        plainPrefix + encode(payload(for: theme))
    }

    /// Developer only: signs a rare theme. Used by Scripts/mint-rare-theme.swift.
    static func rareCode(for theme: SharedTheme, signingKey: Curve25519.Signing.PrivateKey) throws -> String {
        let body = encode(payload(for: theme))
        let signature = try signingKey.signature(for: Data(body.utf8))
        return rarePrefix + body + "." + base64URL(signature)
    }

    // MARK: Reading codes

    static func theme(from rawCode: String, publicKey: String = developerPublicKey) -> Result<SharedTheme, Problem> {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if code.hasPrefix(plainPrefix) {
            guard let payload = decode(String(code.dropFirst(plainPrefix.count))) else { return .failure(.damaged) }
            return .success(theme(from: payload, rare: false))
        }
        if code.hasPrefix(rarePrefix) {
            let parts = code.dropFirst(rarePrefix.count).split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 2, let signature = data(fromBase64URL: String(parts[1])),
                  let keyData = Data(base64Encoded: publicKey),
                  let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else { return .failure(.damaged) }
            guard key.isValidSignature(signature, for: Data(parts[0].utf8)) else { return .failure(.notGenuine) }
            guard let payload = decode(String(parts[0])) else { return .failure(.damaged) }
            return .success(theme(from: payload, rare: true))
        }
        return .failure(.notACode)
    }

    // MARK: Helpers

    private static func payload(for theme: SharedTheme) -> Payload {
        Payload(id: theme.id, name: theme.name, note: theme.note, dark: theme.spec.isDark,
                background: theme.spec.background, accent: theme.spec.accent, rest: theme.spec.rest)
    }

    private static func theme(from payload: Payload, rare: Bool) -> SharedTheme {
        func clean(_ hex: String) -> String {
            let digits = hex.uppercased().filter { "0123456789ABCDEF".contains($0) }
            return digits.count == 6 ? digits : "808080"
        }
        let spec = CustomThemeSpec(isDark: payload.dark, background: clean(payload.background),
                                   accent: clean(payload.accent), rest: clean(payload.rest))
        let name = String(payload.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        let note = payload.note.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)) }
        return SharedTheme(id: payload.id, name: name.isEmpty ? "Shared theme" : name,
                           note: note?.isEmpty == true ? nil : note, spec: spec, isRare: rare)
    }

    private static func encode(_ payload: Payload) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return base64URL((try? encoder.encode(payload)) ?? Data())
    }

    private static func decode(_ text: String) -> Payload? {
        guard let data = data(fromBase64URL: text) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func data(fromBase64URL text: String) -> Data? {
        var base = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base.count % 4 != 0 { base += "=" }
        return Data(base64Encoded: base)
    }
}
