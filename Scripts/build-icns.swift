import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: build-icns.swift <AppIcon.iconset> <AppIcon.icns>\n", stderr)
    exit(2)
}

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let representations = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png"),
]

func appendBigEndian(_ value: Int, to data: inout Data) {
    data.append(contentsOf: [
        UInt8((value >> 24) & 0xFF),
        UInt8((value >> 16) & 0xFF),
        UInt8((value >> 8) & 0xFF),
        UInt8(value & 0xFF),
    ])
}

var payload = Data()

do {
    for (type, filename) in representations {
        let png = try Data(contentsOf: iconsetURL.appendingPathComponent(filename))
        payload.append(contentsOf: type.utf8)
        appendBigEndian(png.count + 8, to: &payload)
        payload.append(png)
    }

    var archive = Data("icns".utf8)
    appendBigEndian(payload.count + 8, to: &archive)
    archive.append(payload)
    try archive.write(to: outputURL, options: .atomic)
} catch {
    fputs("Unable to build ICNS: \(error.localizedDescription)\n", stderr)
    exit(3)
}
