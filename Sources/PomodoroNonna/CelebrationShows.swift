import AppKit
import QuartzCore
import SwiftUI

// Fireworks and balloons for the end-of-session celebration. Like the confetti, every
// particle is animated by Core Animation; the app only lights the fuse.

/// Rockets rise from the bottom, burst into sparks in the theme's colours, and fade.
struct FireworksShow: NSViewRepresentable {
    let colors: [NSColor]

    func makeNSView(context: Context) -> ShowView {
        ShowView { view in view.fireworks(colors: colors) }
    }

    func updateNSView(_ view: ShowView, context: Context) {}
}

/// Balloons float up from below, swaying, and drift off the top.
struct BalloonRise: NSViewRepresentable {
    let colors: [NSColor]

    func makeNSView(context: Context) -> ShowView {
        ShowView { view in view.balloons(colors: colors) }
    }

    func updateNSView(_ view: ShowView, context: Context) {}
}

final class ShowView: NSView {
    private let start: (ShowView) -> Void
    private var started = false

    init(start: @escaping (ShowView) -> Void) {
        self.start = start
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        guard !started, bounds.width > 0, layer != nil else { return }
        started = true
        start(self)
    }

    /// Hosted views can have a flipped y-axis; directions are worked out from this.
    private var layerIsFlipped: Bool { layer?.contentsAreFlipped() ?? false }
    private var up: CGFloat { layerIsFlipped ? -.pi / 2 : .pi / 2 }
    private var bottomY: CGFloat { layerIsFlipped ? bounds.height + 20 : -20 }
    /// Gravity pulls toward the bottom of the screen.
    private func gravity(_ strength: CGFloat) -> CGFloat { layerIsFlipped ? strength : -strength }

    // MARK: Fireworks

    func fireworks(colors: [NSColor]) {
        let scale = window?.backingScaleFactor ?? 2
        guard let spark = Self.dot(diameter: 6, scale: scale), let trail = Self.dot(diameter: 3, scale: scale) else { return }
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .line
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: bottomY)
        emitter.emitterSize = CGSize(width: bounds.width * 0.7, height: 1)
        emitter.renderMode = .additive

        let flight: Float = 1.25
        emitter.emitterCells = colors.prefix(4).map { color in
            // The rocket: a faint streak climbing fast and slowing.
            let rocket = CAEmitterCell()
            rocket.contents = trail
            rocket.contentsScale = scale
            rocket.color = color.cgColor
            rocket.birthRate = 0.9
            rocket.lifetime = flight
            rocket.velocity = bounds.height * 0.62
            rocket.velocityRange = bounds.height * 0.12
            rocket.emissionLongitude = up
            rocket.emissionRange = .pi / 12
            rocket.yAcceleration = gravity(bounds.height * 0.18)
            rocket.alphaSpeed = -0.2

            // At the top of its climb it bursts.
            let burst = CAEmitterCell()
            burst.birthRate = 1
            burst.velocity = 0
            burst.lifetime = 0.25
            burst.beginTime = CFTimeInterval(flight - 0.05)
            burst.duration = 0.08

            let sparks = CAEmitterCell()
            sparks.contents = spark
            sparks.contentsScale = scale
            sparks.color = color.cgColor
            sparks.birthRate = 2200
            sparks.lifetime = 1.9
            sparks.lifetimeRange = 0.5
            sparks.velocity = 150
            sparks.velocityRange = 60
            sparks.emissionRange = .pi * 2
            sparks.yAcceleration = gravity(70)
            sparks.alphaSpeed = -0.55
            sparks.scale = 0.7
            sparks.scaleSpeed = -0.25
            sparks.spin = 2
            burst.emitterCells = [sparks]
            rocket.emitterCells = [burst]
            return rocket
        }
        layer?.addSublayer(emitter)
        // A short volley, then let the last bursts finish.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4.5))
            emitter.birthRate = 0
        }
    }

    // MARK: Balloons

    func balloons(colors: [NSColor]) {
        let scale = window?.backingScaleFactor ?? 2
        guard let balloon = Self.balloon(scale: scale) else { return }
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .line
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: bottomY - (layerIsFlipped ? -40 : 40))
        emitter.emitterSize = CGSize(width: bounds.width * 1.05, height: 1)
        emitter.renderMode = .unordered
        emitter.emitterCells = colors.enumerated().map { index, color in
            let cell = CAEmitterCell()
            cell.name = "b\(index)"
            cell.contents = balloon
            cell.contentsScale = scale
            cell.color = color.cgColor
            cell.birthRate = 1.2
            cell.lifetime = Float(bounds.height / 110) + 3
            cell.velocity = 150
            cell.velocityRange = 50
            cell.emissionLongitude = up
            cell.emissionRange = .pi / 18
            cell.scale = 0.85
            cell.scaleRange = 0.3
            cell.spinRange = 0.25
            return cell
        }
        // Each colour sways on its own slow rhythm as it rises.
        for index in colors.indices {
            let sway = CABasicAnimation(keyPath: "emitterCells.b\(index).xAcceleration")
            sway.fromValue = index.isMultiple(of: 2) ? -14 : 14
            sway.toValue = index.isMultiple(of: 2) ? 14 : -14
            sway.duration = 1.6 + Double(index) * 0.35
            sway.autoreverses = true
            sway.repeatCount = .infinity
            sway.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            emitter.add(sway, forKey: "sway\(index)")
        }
        layer?.addSublayer(emitter)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.8))
            emitter.birthRate = 0
        }
    }

    // MARK: Shapes (white, tinted per cell)

    private static func dot(diameter: CGFloat, scale: CGFloat) -> CGImage? {
        image(size: CGSize(width: diameter, height: diameter), scale: scale) { context, rect in
            context.fillEllipse(in: rect)
        }
    }

    /// A glossy balloon with a knot and a short string.
    private static func balloon(scale: CGFloat) -> CGImage? {
        image(size: CGSize(width: 34, height: 60), scale: scale) { context, rect in
            let w = rect.width, h = rect.height
            // Drawn with y up: body at the top, string hanging below.
            let body = CGRect(x: w * 0.06, y: h * 0.36, width: w * 0.88, height: h * 0.62)
            context.fillEllipse(in: body)
            context.move(to: CGPoint(x: w * 0.5, y: h * 0.37))
            context.addLine(to: CGPoint(x: w * 0.42, y: h * 0.31))
            context.addLine(to: CGPoint(x: w * 0.58, y: h * 0.31))
            context.fillPath()
            context.setLineWidth(1 * scale)
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.7).cgColor)
            context.move(to: CGPoint(x: w * 0.5, y: h * 0.31))
            context.addCurve(to: CGPoint(x: w * 0.5, y: 0), control1: CGPoint(x: w * 0.35, y: h * 0.2), control2: CGPoint(x: w * 0.65, y: h * 0.1))
            context.strokePath()
            // A soft highlight.
            context.setFillColor(NSColor.white.withAlphaComponent(0.35).cgColor)
            context.fillEllipse(in: CGRect(x: w * 0.24, y: h * 0.72, width: w * 0.18, height: h * 0.14))
        }
    }

    private static func image(size: CGSize, scale: CGFloat, draw: (CGContext, CGRect) -> Void) -> CGImage? {
        let pixel = CGSize(width: size.width * scale, height: size.height * scale)
        guard let context = CGContext(data: nil, width: Int(pixel.width), height: Int(pixel.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(NSColor.white.cgColor)
        draw(context, CGRect(origin: .zero, size: pixel))
        return context.makeImage()
    }
}
