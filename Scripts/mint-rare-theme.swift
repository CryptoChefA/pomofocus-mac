#!/usr/bin/env swift
// Makes a rare Pomofocus theme code, signed with the developer's private key.
//
// The private key lives at ~/.pomofocus-dev/rare-theme-key, outside the repository, and is
// created on first run. Back it up somewhere safe: without it no new rare codes can be
// made. Never commit it or share it. The matching public key goes in
// Sources/PomodoroNonna/ThemeCodes.swift (`developerPublicKey`).
//
// Usage:
//   swift Scripts/mint-rare-theme.swift --name "Garden" --note "For Sam, from Alex" \
//       --light --background FBE9EE --accent C96B86 --rest 9E4A64
//   swift Scripts/mint-rare-theme.swift --public-key     # print the public key only
import CryptoKit
import Foundation

let keyURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pomofocus-dev/rare-theme-key")

func loadOrCreateKey() throws -> Curve25519.Signing.PrivateKey {
    if let data = try? Data(contentsOf: keyURL), let raw = Data(base64Encoded: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) {
        return try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
    }
    let key = Curve25519.Signing.PrivateKey()
    try FileManager.default.createDirectory(at: keyURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
    try Data(key.rawRepresentation.base64EncodedString().utf8).write(to: keyURL, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
    FileHandle.standardError.write(Data("Created a new signing key at \(keyURL.path). Back it up.\n".utf8))
    return key
}

func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

var options: [String: String] = [:]
var flags: Set<String> = []
var args = CommandLine.arguments.dropFirst()
while let arg = args.popFirst() {
    if ["--light", "--dark", "--public-key"].contains(arg) { flags.insert(arg); continue }
    guard arg.hasPrefix("--"), let value = args.popFirst() else { continue }
    options[String(arg.dropFirst(2))] = value
}

let key = try loadOrCreateKey()
if flags.contains("--public-key") {
    print(key.publicKey.rawRepresentation.base64EncodedString())
    exit(0)
}
guard let name = options["name"], let background = options["background"], let accent = options["accent"],
      let rest = options["rest"] else {
    FileHandle.standardError.write(Data("Needs --name, --background, --accent and --rest (hex), plus --light or --dark.\n".utf8))
    exit(1)
}

struct Payload: Codable {
    var id: UUID; var name: String; var note: String?; var dark: Bool
    var background: String; var accent: String; var rest: String
}
let payload = Payload(id: UUID(), name: name, note: options["note"], dark: !flags.contains("--light"),
                      background: background, accent: accent, rest: rest)
let encoder = JSONEncoder()
encoder.outputFormatting = .sortedKeys
let body = base64URL(try encoder.encode(payload))
let signature = try key.signature(for: Data(body.utf8))
print("PF-RARE-1." + body + "." + base64URL(signature))
