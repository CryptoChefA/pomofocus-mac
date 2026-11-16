import AppKit

/// Draws the menu-bar item as a cockpit "focus tank": a dark lens chip whose fill drains
/// as the session runs, with the time inside. The digits flip dark where the fill sits
/// under them, so they stay readable. White while focusing, green on a break, red (blinking)
/// in overtime, dim while paused. During the opening breath ritual the tank breathes with
/// you: it fills as you inhale and empties as you exhale.
enum MenuBarGlyph {
    enum Tone {
        case focus, rest, alert, paused, idle

        var color: NSColor {
            switch self {
            case .focus: return NSColor(white: 0.9, alpha: 1)
            case .rest: return NSColor(srgbRed: 0.275, green: 1.0, blue: 0.478, alpha: 1)
            case .alert: return NSColor(srgbRed: 1.0, green: 0.2, blue: 0.16, alpha: 1)
            case .paused: return NSColor(white: 0.55, alpha: 1)
            case .idle: return NSColor(white: 0.42, alpha: 1)
            }
        }
    }

    private static let lens = NSColor(srgbRed: 0.055, green: 0.063, blue: 0.059, alpha: 1)
    private static let ink = NSColor(srgbRed: 0.09, green: 0.05, blue: 0.02, alpha: 1)

    /// - Parameters:
    ///   - text: the legend, e.g. "24:13", "BREATHE", "DONE". `nil` draws the idle chip.
    ///   - fill: 0...1 of the tank that is still full (time left, or the breath).
    ///   - tone: which colour the chip takes.
    ///   - lit: blink phase; `false` dims the chip (used for overtime).
    /// The last chip drawn. The label is asked for an image on every clock tick and
    /// every pulse, but most of those produce the same picture.
    @MainActor private static var lastImage: (key: String, image: NSImage)?

    @MainActor
    static func image(text: String?, fill: Double, tone: Tone, isPaused: Bool = false, lit: Bool = true) -> NSImage {
        // Fill is quantised to 1/400 — finer than one pixel of the widest chip.
        let key = "\(text ?? "-")|\(Int((fill.isFinite ? fill : 0) * 400))|\(tone)|\(isPaused)|\(lit)"
        if let lastImage, lastImage.key == key { return lastImage.image }
        let image = render(text: text, fill: fill, tone: tone, isPaused: isPaused, lit: lit)
        lastImage = (key, image)
        return image
    }

    private static func render(text: String?, fill: Double, tone: Tone, isPaused: Bool, lit: Bool) -> NSImage {
        let height: CGFloat = 18
        let chipHeight: CGFloat = 16
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .bold)
        let label = text?.uppercased()
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .kern: 0.6]
        let textWidth = label.map { ceil(NSAttributedString(string: $0, attributes: attrs).size().width) } ?? 0
        let width = label == nil ? 26 : max(46, textWidth + 18)
        let alpha: CGFloat = lit ? 1 : 0.28
        let color = tone.color.withAlphaComponent(alpha)
        let clamped = CGFloat(min(1, max(0, fill.isFinite ? fill : 0)))

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let chip = NSRect(x: 0.5, y: (height - chipHeight) / 2 + 0.5, width: width - 1, height: chipHeight - 1)
            let body = NSBezierPath(roundedRect: chip, xRadius: 3.5, yRadius: 3.5)
            lens.setFill()
            body.fill()
            color.withAlphaComponent(alpha * 0.5).setStroke()
            body.lineWidth = 1
            body.stroke()

            guard let label else {
                // Idle: an empty tank. It needs a visible rim, or the chip disappears
                // into a dark menu bar and just looks like a gap.
                NSColor(white: 0.62, alpha: 1).setStroke()
                body.lineWidth = 1
                body.stroke()
                let pin = NSBezierPath(ovalIn: NSRect(x: chip.midX - 1.6, y: chip.midY - 1.6, width: 3.2, height: 3.2))
                NSColor(white: 0.78, alpha: 1).setFill()
                pin.fill()
                return true
            }

            let inner = chip.insetBy(dx: 2, dy: 2)
            let fillRect = NSRect(x: inner.minX, y: inner.minY, width: max(clamped > 0 ? 1.2 : 0, inner.width * clamped),
                                  height: inner.height)
            color.setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: 2, yRadius: 2).fill()

            // Legend twice: in the chip's colour, then in ink wherever the fill is under it
            func drawLabel(_ c: NSColor) {
                let str = NSAttributedString(string: label, attributes: [
                    .font: font, .foregroundColor: c, .kern: 0.6])
                let size = str.size()
                str.draw(at: NSPoint(x: chip.midX - (size.width - 0.6) / 2, y: chip.midY - size.height / 2))
            }
            drawLabel(color)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: fillRect).addClip()
            drawLabel(ink.withAlphaComponent(alpha))
            NSGraphicsContext.restoreGraphicsState()

            if isPaused {
                // Two bars at the right edge, like a pause key
                color.setFill()
                for offset in [CGFloat(-4.6), CGFloat(-2.0)] {
                    NSBezierPath(rect: NSRect(x: chip.maxX + offset, y: chip.midY - 2.4, width: 1.2, height: 4.8)).fill()
                }
            }
            return true
        }
        image.isTemplate = false      // the chip has its own dark lens, like the Annunciator lights
        return image
    }
}

/// The menu-bar item's look, chosen in Settings → Menu bar.
enum MenuBarStyle: String, CaseIterable, Identifiable {
    /// The timer chip above, with the time inside.
    case chip
    /// Three bars, one third of the block each, that empty from the right as time runs.
    case bars
    /// An image you choose.
    case icon
    /// Just the time left or the percentage, in your colour. Nothing else.
    case minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chip: "Timer chip"
        case .bars: "Three bars"
        case .icon: "Your icon"
        case .minimal: "Minimal"
        }
    }
}

/// The simpler menu-bar looks: three bars, or your own icon, with the time beside them if
/// you want it. With the colour on "auto" they're template images, so macOS draws them in
/// the menu bar's own colour, light or dark, and highlights them when the panel opens.
enum MenuBarMark {
    /// What the bars show, worked out from the timer.
    struct Bars: Equatable {
        /// 0...1 of each bar still full, left to right.
        var levels: [Double]
        /// Dimmer while paused, and on the off beat of the overtime blink.
        var alpha: Double
    }

    @MainActor private static var lastImage: (key: String, image: NSImage)?

    /// - Parameters:
    ///   - color: nil follows the menu bar (a template image).
    ///   - icon: your image instead of the bars.
    @MainActor
    static func image(bars: Bars, color: NSColor?, icon: NSImage?, iconFollowsMenuBar: Bool, text: String?,
                      showsMark: Bool = true) -> NSImage {
        // Levels are quantised to the half point a bar can actually show.
        let levels = bars.levels.map { Int(($0.isFinite ? $0 : 0) * 26) }
        let key = "\(levels)|\(Int(bars.alpha * 100))|\(color?.description ?? "auto")|\(icon.map { ObjectIdentifier($0).hashValue } ?? 0)|\(iconFollowsMenuBar)|\(text ?? "-")|\(showsMark)"
        if let lastImage, lastImage.key == key { return lastImage.image }
        let image = render(bars: bars, color: color, icon: icon, iconFollowsMenuBar: iconFollowsMenuBar, text: text,
                           showsMark: showsMark)
        lastImage = (key, image)
        return image
    }

    private static let height: CGFloat = 18
    private static let barWidth: CGFloat = 2.6
    private static let barHeight: CGFloat = 12.5
    private static let barGap: CGFloat = 2.4
    private static let iconSide: CGFloat = 16
    private static var font: NSFont { NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium) }

    private static func render(bars: Bars, color: NSColor?, icon: NSImage?, iconFollowsMenuBar: Bool, text: String?,
                               showsMark: Bool) -> NSImage {
        let markWidth = !showsMark ? 0 : (icon == nil ? barWidth * 3 + barGap * 2 : iconSide)
        let textWidth = text.map { ceil(NSAttributedString(string: $0, attributes: [.font: font]).size().width) } ?? 0
        let gap: CGFloat = showsMark ? 5 : 0
        let width = ceil(markWidth + (text == nil ? 0 : gap + textWidth)) + 2
        // A template image is drawn in the menu bar's colour by macOS; anything else in
        // the colour chosen. Your own icon, unless it follows the menu bar, keeps its colours
        // and the time beside it takes the menu bar's text colour.
        let template = icon == nil ? color == nil : iconFollowsMenuBar
        let alpha = CGFloat(min(1, max(0.15, bars.alpha)))

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let ink = template ? NSColor.black : (color ?? NSColor.labelColor)
            var x: CGFloat = 1
            if !showsMark {
                // Minimal: the text alone.
            } else if let icon {
                let size = icon.size
                let scale = min(iconSide / max(1, size.width), iconSide / max(1, size.height))
                let drawn = NSSize(width: size.width * scale, height: size.height * scale)
                let rect = NSRect(x: x + (iconSide - drawn.width) / 2, y: (height - drawn.height) / 2,
                                  width: drawn.width, height: drawn.height)
                icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
                x += iconSide
            } else {
                let bottom = (height - barHeight) / 2
                for (index, level) in bars.levels.prefix(3).enumerated() {
                    let bar = NSRect(x: x, y: bottom, width: barWidth, height: barHeight)
                    // The emptied part stays as a faint outline of the bar, so the shape
                    // always reads as three bars.
                    ink.withAlphaComponent(alpha * 0.28).setFill()
                    NSBezierPath(rect: bar).fill()
                    let filled = barHeight * CGFloat(min(1, max(0, level.isFinite ? level : 0)))
                    ink.withAlphaComponent(alpha).setFill()
                    NSBezierPath(rect: NSRect(x: bar.minX, y: bottom, width: barWidth, height: filled)).fill()
                    x += barWidth + (index < 2 ? barGap : 0)
                }
            }
            if let text {
                let textColor = template ? NSColor.black : (icon != nil ? NSColor.labelColor : ink)
                let string = NSAttributedString(string: text, attributes: [
                    .font: font, .foregroundColor: textColor.withAlphaComponent(alpha)])
                let size = string.size()
                string.draw(at: NSPoint(x: x + gap, y: (height - size.height) / 2))
            }
            return true
        }
        image.isTemplate = template
        return image
    }
}

/// Your own menu-bar icon, kept as a small PNG next to the app's data.
enum MenuBarIconStore {
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Pomofocus", isDirectory: true)
            .appendingPathComponent("menubar-icon.png")
    }

    @MainActor private static var cached: (date: Date, image: NSImage)?

    /// The saved icon, read again only when the file changes.
    @MainActor static var image: NSImage? {
        guard let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else {
            cached = nil
            return nil
        }
        if let cached, cached.date == date { return cached.image }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cached = (date, image)
        return image
    }

    /// Saves a chosen picture as a 64-pixel square PNG (sharp at 16 points on a Retina
    /// menu bar), keeping its shape and transparency.
    @MainActor static func save(from source: URL) throws {
        guard let picture = NSImage(contentsOf: source), picture.size.width > 0, picture.size.height > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let side = 64
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw CocoaError(.fileWriteUnknown)
        }
        rep.size = NSSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        let scale = min(CGFloat(side) / picture.size.width, CGFloat(side) / picture.size.height)
        let drawn = NSSize(width: picture.size.width * scale, height: picture.size.height * scale)
        picture.draw(in: NSRect(x: (CGFloat(side) - drawn.width) / 2, y: (CGFloat(side) - drawn.height) / 2,
                                width: drawn.width, height: drawn.height))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url, options: .atomic)
        cached = nil
    }

    @MainActor static func remove() {
        try? FileManager.default.removeItem(at: url)
        cached = nil
    }
}
