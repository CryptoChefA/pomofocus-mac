import AppKit
import QuartzCore
import SwiftUI

/// Petals, leaves or snow drifting down behind the interface. Core Animation's emitter does
/// the work on the graphics chip, so the app's own CPU stays idle while they fall. It
/// stops when the window goes to the background and never runs with Reduce Motion.
struct FallingParticles: NSViewRepresentable {
    /// Each image becomes one kind of particle.
    let images: [CGImage]
    /// Particles per second across the whole width.
    var birthRate: Float = 0.6
    /// Points per second downward.
    var speed: CGFloat = 16
    var running: Bool

    func makeNSView(context: Context) -> EmitterView {
        let view = EmitterView()
        view.configure(images: images, birthRate: birthRate, speed: speed)
        view.setRunning(running)
        return view
    }

    func updateNSView(_ view: EmitterView, context: Context) {
        view.setRunning(running)
    }

    final class EmitterView: NSView {
        private let emitter = CAEmitterLayer()
        private var prefill: CFTimeInterval = 0
        private var prefilled = false

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.addSublayer(emitter)
            emitter.isGeometryFlipped = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func configure(images: [CGImage], birthRate: Float, speed: CGFloat) {
            emitter.emitterShape = .line
            emitter.renderMode = .unordered
            // Long enough for the slowest particle to cross a tall window. Ones that have
            // left the bottom cost nothing to keep simulating.
            let lifetime = Float(1400 / max(speed * 0.6, 1))
            // Each kind comes in two batches that sway in opposite rhythms, so the field
            // never moves as one. Sideways motion only ever comes from the sway: a constant
            // sideways push would carry everything off the edges before it had fallen far.
            emitter.emitterCells = images.enumerated().flatMap { index, image in
                [-1.0, 1.0].map { side -> CAEmitterCell in
                    let cell = CAEmitterCell()
                    cell.name = "p\(index)\(side > 0 ? "a" : "b")"
                    cell.contents = image
                    cell.birthRate = birthRate / Float(max(images.count * 2, 1))
                    cell.lifetime = lifetime
                    cell.velocity = speed
                    cell.velocityRange = speed * 0.4
                    // Pointed down in layout(), once we know which way the layer's y-axis runs.
                    cell.emissionRange = .pi / 8
                    cell.spin = 0.35
                    cell.spinRange = 1.2
                    cell.scale = 0.5
                    cell.scaleRange = 0.18
                    cell.alphaRange = 0.25
                    return cell
                }
            }
            prefill = CFTimeInterval(min(lifetime * 0.8, 90))
            addSway(kinds: images.count)
        }

        /// A slow push back and forth for each batch, each on its own rhythm. Because the
        /// push reverses, the sideways speed it builds up stays small: the particles wander
        /// a little either way as they fall instead of sliding off one side.
        private func addSway(kinds: Int) {
            for index in 0..<kinds {
                for (suffix, sign) in [("a", 1.0), ("b", -1.0)] {
                    let sway = CABasicAnimation(keyPath: "emitterCells.p\(index)\(suffix).xAcceleration")
                    let strength = 7.0 + Double(index % 3) * 1.5
                    sway.fromValue = sign * strength
                    sway.toValue = -sign * strength
                    sway.duration = 3.6 + Double(index) * 0.9
                    sway.autoreverses = true
                    sway.repeatCount = .infinity
                    sway.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    emitter.add(sway, forKey: "sway\(index)\(suffix)")
                }
            }
        }

        /// Start with the sky already full instead of waiting for the first ones to arrive.
        /// This only works once the layer is in a window, in its parent's time.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, !prefilled, let parent = emitter.superlayer else { return }
            prefilled = true
            emitter.beginTime = parent.convertTime(CACurrentMediaTime(), from: nil) - prefill
            // The layer tree above decides which way is down; check again now that it exists.
            needsLayout = true
        }

        /// In the background no new particles are made; the ones already falling finish
        /// their fall, so nothing jumps when the window comes back.
        func setRunning(_ running: Bool) {
            emitter.birthRate = running ? 1 : 0
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            emitter.frame = bounds
            // SwiftUI hosts this view in a flipped coordinate space, so "down" can be +y or
            // -y depending on the layer tree. Ask, then start the line above the top edge
            // and point every particle down.
            let flipped = emitter.contentsAreFlipped()
            emitter.emitterPosition = CGPoint(x: bounds.midX, y: flipped ? -24 : bounds.maxY + 24)
            emitter.emitterSize = CGSize(width: bounds.width * 1.2, height: 1)
            let down: CGFloat = flipped ? .pi / 2 : -.pi / 2
            if let cells = emitter.emitterCells, cells.first?.emissionLongitude != down {
                cells.forEach { $0.emissionLongitude = down }
                emitter.emitterCells = cells
            }
            CATransaction.commit()
        }
    }
}

/// Renders a shape once into a small image for the emitter.
@MainActor
enum ParticleImage {
    static func make<S: Shape>(_ shape: S, color: Color, size: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: shape.fill(color).frame(width: size, height: size))
        renderer.scale = 2
        return renderer.cgImage
    }
}
