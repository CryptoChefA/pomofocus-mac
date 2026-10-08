import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: render-icon.swift <source.svg> <output.png>\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let canvasSize = NSSize(width: 1024, height: 1024)

guard let source = NSImage(contentsOf: sourceURL) else {
    fputs("Unable to load SVG at \(sourceURL.path)\n", stderr)
    exit(3)
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Unable to allocate icon bitmap\n", stderr)
    exit(4)
}

bitmap.size = canvasSize
NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Unable to create icon graphics context\n", stderr)
    exit(5)
}

NSGraphicsContext.current = context
context.imageInterpolation = .high
NSColor.clear.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()
source.draw(
    in: NSRect(origin: .zero, size: canvasSize),
    from: NSRect(origin: .zero, size: source.size),
    operation: .sourceOver,
    fraction: 1
)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Unable to encode icon PNG\n", stderr)
    exit(6)
}

do {
    try pngData.write(to: outputURL, options: .atomic)
} catch {
    fputs("Unable to write icon PNG: \(error.localizedDescription)\n", stderr)
    exit(7)
}
