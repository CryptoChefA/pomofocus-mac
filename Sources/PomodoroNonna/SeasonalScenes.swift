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
/// pattern. The crystals are one shape driven by one value, so a frame of growth is a
/// few hundred short lines; the shimmer is a layer's opacity, which costs nothing. The
/// cycle rests while the window is in the background, and with Reduce Motion the frost
/// simply stays.
private struct FrostCorners: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    @State private var growth = 0.0
    @State private var shimmer = false
    @State private var seed: UInt64 = 77

    private var resting: Bool { reduceMotion || activeState == .inactive }

    var body: some View {
        GeometryReader { proxy in
            // Each corner draws in a square of its own, so a frame of growth only touches
            // the corners, never a window-sized layer.
            let scale = max(0.7, min(1.3, min(proxy.size.width, proxy.size.height) / 820))
            let extent = min(470 * scale, min(proxy.size.width, proxy.size.height))
            ZStack {
                FrostCorner(pattern: FrostPattern(extent: extent, scale: scale, corner: .topLeading, seed: seed),
                            growth: growth, shimmer: shimmer)
                    .frame(width: extent, height: extent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                FrostCorner(pattern: FrostPattern(extent: extent, scale: scale, corner: .bottomTrailing, seed: seed &+ 11),
                            growth: growth, shimmer: shimmer)
                    .frame(width: extent, height: extent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .task(id: resting) {
            if reduceMotion {
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) {
                    growth = 1
                    shimmer = false
                }
                return
            }
            if activeState == .inactive {
                // Finish growing if need be, then hold: the shimmer stops so nothing keeps
                // moving in a window nobody is looking at.
                withAnimation(.easeOut(duration: 0.6)) { shimmer = false }
                withAnimation(.easeOut(duration: 9)) { growth = 1 }
                return
            }
            while !Task.isCancelled {
                withAnimation(.easeOut(duration: 9)) { growth = 1 }
                try? await Task.sleep(for: .seconds(9))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) { shimmer = true }
                try? await Task.sleep(for: .seconds(16))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 1)) { shimmer = false }
                withAnimation(.easeIn(duration: 5)) { growth = 0 }
                try? await Task.sleep(for: .seconds(5.3))
                guard !Task.isCancelled else { return }
                // A fresh pattern, still folded into the corner, ready to grow.
                var fresh = Transaction()
                fresh.disablesAnimations = true
                withTransaction(fresh) { seed = seed &* 6364136223846793005 &+ 1442695040888963407 }
                try? await Task.sleep(for: .seconds(0.8))
            }
        }
    }
}

/// One corner of frost at one stage of growth, in four strokes: a soft halo, fine twigs,
/// the main crystals, and a brighter copy of the crystals that breathes.
private struct FrostCorner: View {
    let pattern: FrostPattern
    let growth: Double
    let shimmer: Bool

    var body: some View {
        ZStack {
            ZStack {
                FrostShape(pattern: pattern, growth: growth, detail: .all)
                    .stroke(Color(hex: "BFEAFF").opacity(0.09), style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
                FrostShape(pattern: pattern, growth: growth, detail: .twigs)
                    .stroke(Color(hex: "D6F2FF").opacity(0.34), style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
                FrostShape(pattern: pattern, growth: growth, detail: .trunks)
                    .stroke(Color(hex: "E9F6FF").opacity(0.5), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            }
            // Flattened on the graphics chip, so a frame of growth never rasterises on the CPU.
            .drawingGroup()
            if shimmer {
                FrostShape(pattern: pattern, growth: growth, detail: .trunks)
                    .stroke(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .transition(.opacity)
            }
        }
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

/// A frost pattern at one stage of growth: every line has grown as far as the ice has
/// reached, so the whole pattern spreads outward from the corner at once, and thaws back
/// from the tips when growth falls.
struct FrostShape: Shape {
    enum Detail { case all, trunks, twigs }

    let pattern: FrostPattern
    var growth: Double
    let detail: Detail

    var animatableData: Double {
        get { growth }
        set { growth = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let reach = growth * pattern.fullReach
        for segment in pattern.segments {
            switch detail {
            case .all: break
            case .trunks where segment.depth < 2: continue
            case .twigs where segment.depth >= 2: continue
            default: break
            }
            let grown = min(1, max(0, (reach - segment.reachAtStart) / segment.length))
            guard grown > 0 else { continue }
            path.move(to: segment.start)
            path.addLine(to: CGPoint(x: segment.start.x + (segment.end.x - segment.start.x) * grown,
                                     y: segment.start.y + (segment.end.y - segment.start.y) * grown))
        }
        return path
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
