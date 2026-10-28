import AppKit
import QuartzCore
import SwiftUI

// MARK: - Autumn

/// Autumn's scene: maple and oak leaves in fall colours drifting down, a warm light from
/// the top corner. The leaves fall on the graphics chip, like Sakura's petals.
struct AutumnScene: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState

    @MainActor static let leafImages: [CGImage] = [
        ParticleImage.make(MapleLeaf(), color: Color(hex: "C8551E").opacity(0.85), size: 30),
        ParticleImage.make(MapleLeaf(), color: Color(hex: "A3322A").opacity(0.8), size: 26),
        ParticleImage.make(OvalLeaf(), color: Color(hex: "D99A2B").opacity(0.85), size: 24),
        ParticleImage.make(OvalLeaf(), color: Color(hex: "8A5A2E").opacity(0.75), size: 22),
    ].compactMap { $0 }

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(hex: "E9A25A").opacity(0.18), .clear], center: .topTrailing, startRadius: 10, endRadius: 700)
            if !reduceMotion {
                FallingParticles(images: Self.leafImages, birthRate: 0.4, speed: 28, running: activeState != .inactive)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A five-pointed maple leaf with a short stem.
struct MapleLeaf: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + x * w, y: rect.minY + y * h) }
        var path = Path()
        let outline: [(Double, Double)] = [
            (0.50, 0.02), (0.58, 0.20), (0.70, 0.14), (0.66, 0.32), (0.92, 0.24), (0.84, 0.40),
            (0.98, 0.48), (0.76, 0.56), (0.80, 0.68), (0.56, 0.62), (0.53, 0.80),
            (0.47, 0.80), (0.44, 0.62), (0.20, 0.68), (0.24, 0.56), (0.02, 0.48), (0.16, 0.40),
            (0.08, 0.24), (0.34, 0.32), (0.30, 0.14), (0.42, 0.20),
        ]
        path.move(to: p(outline[0].0, outline[0].1))
        for point in outline.dropFirst() { path.addLine(to: p(point.0, point.1)) }
        path.closeSubpath()
        // Stem.
        path.move(to: p(0.49, 0.80))
        path.addLine(to: p(0.47, 0.98))
        path.addLine(to: p(0.51, 0.98))
        path.addLine(to: p(0.53, 0.80))
        return path
    }
}

/// A simple pointed oval leaf.
struct OvalLeaf: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let top = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.05)
        let bottom = CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.05)
        path.move(to: top)
        path.addQuadCurve(to: bottom, control: CGPoint(x: rect.maxX + rect.width * 0.1, y: rect.midY))
        path.addQuadCurve(to: top, control: CGPoint(x: rect.minX - rect.width * 0.1, y: rect.midY))
        return path
    }
}

// MARK: - Black Ice

/// Black Ice's scene: frost crystals growing in from two corners (drawn once), a cold glow,
/// and a slow fall of fine snow.
struct BlackIceScene: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState

    @MainActor static let snowImages: [CGImage] = [
        ParticleImage.make(Circle(), color: Color(hex: "E9F6FF").opacity(0.8), size: 7),
        ParticleImage.make(Circle(), color: Color(hex: "8FDDFF").opacity(0.6), size: 5),
        ParticleImage.make(Snowflake(), color: Color(hex: "C9F0FF").opacity(0.7), size: 16),
    ].compactMap { $0 }

    var body: some View {
        ZStack {
            // Deep ice blue at the top, settling into pure black at the bottom.
            // Many close stops in one blue family, so the fade never passes through a
            // purplish midtone on its way to black.
            LinearGradient(colors: ["124066", "0F3757", "0C2E49", "09243A", "061A2B", "04111D", "02080F", "000000"].map { Color(hex: $0) },
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(hex: "4FB6D6").opacity(0.12), .clear], center: .top, startRadius: 10, endRadius: 620)
            FrostCorners()
            if !reduceMotion {
                FallingParticles(images: Self.snowImages, birthRate: 0.9, speed: 22, running: activeState != .inactive)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A six-armed snowflake.
struct Snowflake: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY), r = min(rect.width, rect.height) * 0.48
        var path = Path()
        for arm in 0..<6 {
            let a = Double(arm) * .pi / 3
            let tip = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            path.move(to: c)
            path.addLine(to: tip)
            for side in [-1.0, 1.0] {
                let base = CGPoint(x: c.x + cos(a) * r * 0.55, y: c.y + sin(a) * r * 0.55)
                let b = a + side * .pi / 4
                path.move(to: base)
                path.addLine(to: CGPoint(x: base.x + cos(b) * r * 0.3, y: base.y + sin(b) * r * 0.3))
            }
        }
        return path.strokedPath(StrokeStyle(lineWidth: max(1, r * 0.14), lineCap: .round))
    }
}

/// Frost that lives: crystals grow in from two corners the way ice spreads over a cold
/// window, hold with a faint shimmer, thaw back from their tips, and grow again in a new
/// pattern. Core Animation does the moving: the finished crystals sit behind a mask made
/// of one short stroke per line, and the window server lengthens each mask stroke along
/// its line, so growing and thawing cost the app nothing per frame. The cycle rests while
/// the window is in the background, and with Reduce Motion the frost simply stays.
private struct FrostCorners: NSViewRepresentable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState

    func makeNSView(context: Context) -> FrostView { FrostView() }

    func updateNSView(_ view: FrostView, context: Context) {
        view.mode = reduceMotion ? .still : activeState == .inactive ? .resting : .living
    }
}

@MainActor
private final class FrostView: NSView {
    enum Mode { case living, resting, still }

    var mode: Mode = .living {
        didSet { if mode != oldValue { restart() } }
    }

    private var corners: [FrostCorner] = []
    private var seed: UInt64 = 77
    private var laidOut = CGSize.zero
    private var cycle: Task<Void, Never>?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        guard bounds.size != laidOut, bounds.width > 0, bounds.height > 0 else { return }
        laidOut = bounds.size
        rebuild(keepingProgress: true)
        restart()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for corner in corners { corner.setContentsScale(scale) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            cycle?.cancel()
            cycle = nil
        } else {
            viewDidChangeBackingProperties()
            restart()
        }
    }

    /// Lays the two corners out for the current size. The same seed gives the same lines,
    /// so after a resize each line carries on from where it was.
    private func rebuild(keepingProgress: Bool) {
        let size = bounds.size
        let scale = max(0.7, min(1.3, min(size.width, size.height) / 820))
        let extent = min(470 * scale, min(size.width, size.height))
        let previous = keepingProgress ? corners : []
        for corner in corners { corner.container.removeFromSuperlayer() }
        let placed = [
            (FrostPattern.Corner.topLeading, CGRect(x: 0, y: 0, width: extent, height: extent), seed),
            (FrostPattern.Corner.bottomTrailing, CGRect(x: size.width - extent, y: size.height - extent, width: extent, height: extent), seed &+ 11),
        ]
        corners = placed.enumerated().map { index, place in
            let corner = FrostCorner(pattern: FrostPattern(extent: extent, scale: scale, corner: place.0, seed: place.2), frame: place.1)
            if index < previous.count { corner.copyProgress(from: previous[index]) }
            corner.setContentsScale(window?.backingScaleFactor ?? 2)
            layer?.addSublayer(corner.container)
            return corner
        }
    }

    private func restart() {
        cycle?.cancel()
        cycle = nil
        guard !corners.isEmpty, window != nil else { return }
        switch mode {
        case .still:
            for corner in corners { corner.stay() }
        case .resting:
            // Finish growing if need be, then hold: the shimmer stops so nothing keeps
            // moving in a window nobody is looking at.
            for corner in corners {
                corner.shimmer(false, over: 0.6)
                corner.reveal(to: 1, over: 9, curve: .easeOut)
            }
        case .living:
            cycle = Task { @MainActor [weak self] in
                while let self, !Task.isCancelled {
                    for corner in corners { corner.reveal(to: 1, over: 9, curve: .easeOut) }
                    try? await Task.sleep(for: .seconds(9))
                    guard !Task.isCancelled else { return }
                    for corner in corners { corner.shimmer(true) }
                    try? await Task.sleep(for: .seconds(16))
                    guard !Task.isCancelled else { return }
                    for corner in corners {
                        corner.shimmer(false, over: 1)
                        corner.reveal(to: 0, over: 5, curve: .easeIn)
                    }
                    try? await Task.sleep(for: .seconds(5.3))
                    guard !Task.isCancelled else { return }
                    // A fresh pattern, still folded into the corner, ready to grow.
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    rebuild(keepingProgress: false)
                    try? await Task.sleep(for: .seconds(0.8))
                }
            }
        }
    }
}

/// One corner of frost: the finished crystals in four strokes (a soft halo, fine twigs,
/// the main crystals, and a brighter copy of the crystals that breathes), seen through a
/// mask of one stroke per line that grows and shrinks along it.
@MainActor
private final class FrostCorner {
    let pattern: FrostPattern
    let container = CALayer()
    private let mask = CALayer()
    private let shimmer: CAShapeLayer
    private var reveals: [CAShapeLayer] = []
    private var everything: [CALayer] { [container, mask, shimmer] + reveals + (container.sublayers ?? []) }

    init(pattern: FrostPattern, frame: CGRect) {
        self.pattern = pattern
        container.frame = frame
        let bounds = CGRect(origin: .zero, size: frame.size)
        mask.frame = bounds

        func strokes(_ keep: (FrostPattern.Segment) -> Bool, _ hex: UInt32, _ alpha: CGFloat, _ width: CGFloat) -> CAShapeLayer {
            let path = CGMutablePath()
            for segment in pattern.segments where keep(segment) {
                path.move(to: segment.start)
                path.addLine(to: segment.end)
            }
            let shape = CAShapeLayer()
            shape.frame = bounds
            shape.path = path
            shape.fillColor = nil
            shape.lineCap = .round
            shape.lineWidth = width
            shape.strokeColor = CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                                        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
            return shape
        }
        container.addSublayer(strokes({ _ in true }, 0xBFEAFF, 0.09, 3.4))
        container.addSublayer(strokes({ $0.depth < 2 }, 0xD6F2FF, 0.34, 0.7))
        container.addSublayer(strokes({ $0.depth >= 2 }, 0xE9F6FF, 0.5, 1.1))
        shimmer = strokes({ $0.depth >= 2 }, 0xFFFFFF, 0.22, 1.6)
        shimmer.opacity = 0
        container.addSublayer(shimmer)

        // Each line is revealed by its own stroke, a touch wider than the halo so the
        // halo's soft edge comes with it.
        let margin: CGFloat = 3.5
        for segment in pattern.segments {
            let box = CGRect(x: min(segment.start.x, segment.end.x) - margin, y: min(segment.start.y, segment.end.y) - margin,
                             width: abs(segment.end.x - segment.start.x) + margin * 2, height: abs(segment.end.y - segment.start.y) + margin * 2)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: segment.start.x - box.minX, y: segment.start.y - box.minY))
            path.addLine(to: CGPoint(x: segment.end.x - box.minX, y: segment.end.y - box.minY))
            let reveal = CAShapeLayer()
            reveal.frame = box
            reveal.path = path
            reveal.fillColor = nil
            reveal.strokeColor = CGColor(gray: 1, alpha: 1)
            reveal.lineCap = .round
            reveal.lineWidth = 4.6
            reveal.strokeEnd = 0
            mask.addSublayer(reveal)
            reveals.append(reveal)
        }
        container.mask = mask
    }

    func setContentsScale(_ scale: CGFloat) {
        for layer in everything { layer.contentsScale = scale }
    }

    /// Picks up each line's current reveal from the same pattern laid out at another size.
    func copyProgress(from other: FrostCorner) {
        guard other.reveals.count == reveals.count else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (reveal, previous) in zip(reveals, other.reveals) {
            reveal.strokeEnd = (previous.presentation() ?? previous).strokeEnd
        }
        shimmer.opacity = (other.shimmer.presentation() ?? other.shimmer).opacity
        CATransaction.commit()
    }

    /// Moves the whole pattern's growth to `target` over `duration`: the ice's reach runs
    /// along `curve`, and every line grows (or thaws) as the reach passes over it. A line
    /// never jumps: it keeps what it shows until the moving front catches up with it.
    func reveal(to target: Double, over duration: TimeInterval, curve: UnitCurve) {
        let steps = 48
        let from = 1 - target
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (reveal, segment) in zip(reveals, pattern.segments) {
            let now = (reveal.presentation() ?? reveal).strokeEnd
            let final = CGFloat(min(1, max(0, (target * pattern.fullReach - segment.reachAtStart) / segment.length)))
            let values = (0...steps).map { step -> CGFloat in
                let growth = from + (target - from) * curve.value(at: Double(step) / Double(steps))
                let grown = CGFloat(min(1, max(0, (growth * pattern.fullReach - segment.reachAtStart) / segment.length)))
                return target > from ? max(grown, now) : min(grown, now)
            }
            reveal.removeAnimation(forKey: "reveal")
            reveal.strokeEnd = final
            guard values.contains(where: { $0 != now }) else { continue }
            let animation = CAKeyframeAnimation(keyPath: "strokeEnd")
            animation.values = values
            animation.duration = duration
            animation.calculationMode = .linear
            reveal.add(animation, forKey: "reveal")
        }
        CATransaction.commit()
    }

    func shimmer(_ on: Bool, over fade: TimeInterval = 0) {
        let now = (shimmer.presentation() ?? shimmer).opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shimmer.removeAnimation(forKey: "breathe")
        shimmer.opacity = 0
        if on {
            let breathe = CABasicAnimation(keyPath: "opacity")
            breathe.fromValue = now
            breathe.toValue = 1
            breathe.duration = 2.8
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            shimmer.add(breathe, forKey: "breathe")
        } else if now > 0, fade > 0 {
            let settle = CABasicAnimation(keyPath: "opacity")
            settle.fromValue = now
            settle.toValue = 0
            settle.duration = fade
            settle.timingFunction = CAMediaTimingFunction(name: .easeOut)
            shimmer.add(settle, forKey: "breathe")
        }
        CATransaction.commit()
    }

    /// Fully grown and still, for Reduce Motion.
    func stay() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for reveal in reveals {
            reveal.removeAllAnimations()
            reveal.strokeEnd = 1
        }
        shimmer.removeAllAnimations()
        shimmer.opacity = 0
        CATransaction.commit()
    }
}

/// The lines of one corner's frost, each with how far from the corner it starts growing,
/// so the whole pattern can be drawn at any stage of freezing.
struct FrostPattern: Equatable {
    struct Segment: Equatable {
        let start: CGPoint
        let end: CGPoint
        /// Distance along the growth from the corner to this line's root.
        let reachAtStart: Double
        let length: Double
        /// 3 for a main crystal, down to 0 for the finest twig.
        let depth: Int
    }

    enum Corner { case topLeading, bottomTrailing }

    let segments: [Segment]
    /// The reach at which the last tip finishes.
    let fullReach: Double

    /// Six crystals from the corner of a square `extent` points on a side.
    init(extent: CGFloat, scale: CGFloat, corner: Corner, seed: UInt64) {
        var random = SakuraArt.Seeded(state: seed)
        var segments: [Segment] = []
        let origin = corner == .topLeading ? CGPoint(x: 0, y: 0) : CGPoint(x: extent, y: extent)
        let base = corner == .topLeading ? 45.0 : 225.0
        for _ in 0..<6 {
            let angle = (base - 38 + random.next() * 76) * .pi / 180
            Self.grow(&segments, from: origin, reach: 0, angle: angle,
                      length: (110 + random.next() * 130) * scale, depth: 3, random: &random)
        }
        self.segments = segments
        fullReach = max(1, segments.map { $0.reachAtStart + $0.length }.max() ?? 1)
    }

    private static func grow(_ segments: inout [Segment], from start: CGPoint, reach: Double, angle: Double,
                             length: Double, depth: Int, random: inout SakuraArt.Seeded) {
        let end = CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
        segments.append(Segment(start: start, end: end, reachAtStart: reach, length: length, depth: depth))
        guard depth > 0 else { return }
        // Side branches leave at the ice angle (60°), shorter each time.
        let branches = 2 + Int(random.next() * 3)
        for index in 0..<branches {
            let t = 0.22 + 0.7 * Double(index) / Double(branches)
            let origin = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
            let side = random.next() < 0.5 ? -1.0 : 1.0
            grow(&segments, from: origin, reach: reach + length * t, angle: angle + side * .pi / 3,
                 length: length * (0.26 + random.next() * 0.22), depth: depth - 1, random: &random)
        }
    }
}

/// Black Ice signs its name in an icy script. The glow breathes: a blurred copy of the
/// text sits behind it and fades up and down, so only a layer's opacity moves each frame.
struct IcyGreeting: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    @State private var bright = false

    private var breathing: Bool { !reduceMotion && activeState != .inactive }

    var body: some View {
        let script = Text(text).font(.custom("SnellRoundhand-Bold", size: 24))
        script
            .foregroundStyle(Color(hex: "E9F6FF"))
            .shadow(color: Color(hex: "8FDDFF").opacity(0.8), radius: 6)
            .shadow(color: Color(hex: "4FB6D6").opacity(0.5), radius: 14)
            .background {
                script
                    .foregroundStyle(Color(hex: "A8E6FF"))
                    .blur(radius: 10)
                    .opacity(bright ? 0.7 : 0)
            }
            .onChange(of: breathing, initial: true) { _, breathing in
                if breathing {
                    withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { bright = true }
                } else {
                    withAnimation(.easeOut(duration: 0.6)) { bright = false }
                }
            }
    }
}

/// Frost over the dial while a Black Ice timer is paused: the block is literally frozen.
struct FrostOverlay: View {
    var body: some View {
        ZStack {
            Circle().fill(Color(hex: "C9F0FF").opacity(0.10))
            Canvas { context, size in
                var random = SakuraArt.Seeded(state: 5)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2
                for _ in 0..<9 {
                    let a = random.next() * .pi * 2
                    let start = CGPoint(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius)
                    var line = Path()
                    line.move(to: start)
                    let inward = a + .pi + (random.next() - 0.5) * 0.6
                    let length = radius * (0.3 + random.next() * 0.35)
                    let end = CGPoint(x: start.x + cos(inward) * length, y: start.y + sin(inward) * length)
                    line.addLine(to: end)
                    for t in [0.35, 0.6, 0.8] {
                        let o = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
                        for side in [-1.0, 1.0] {
                            let b = inward + side * .pi / 3
                            line.move(to: o)
                            line.addLine(to: CGPoint(x: o.x + cos(b) * length * 0.18, y: o.y + sin(b) * length * 0.18))
                        }
                    }
                    context.stroke(line, with: .color(Color(hex: "E9F6FF").opacity(0.55)), lineWidth: 1)
                }
            }
            .clipShape(Circle())
            Circle().stroke(Color(hex: "C9F0FF").opacity(0.5), lineWidth: 1.5)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Bespoke

/// A faint chalk pinstripe, like the cloth of a dark suit. Drawn once.
struct Pinstripe: View {
    var body: some View {
        Canvas { context, size in
            var x: CGFloat = 0
            while x < size.width {
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(.white.opacity(0.028)), lineWidth: 0.6)
                x += 14
            }
        }
        .overlay {
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
