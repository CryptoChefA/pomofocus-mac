import AppKit
import ImageIO
import Metal
import MetalKit
import SwiftUI

// MARK: - London

/// The London theme's scene: Westminster from across the Thames on a rainy night. The
/// skyline is eight still images (four depths, each with a matching layer of lights) made
/// by Scripts/london/render.sh; a Metal shader composes them with the moving parts: drifting
/// cloud, low cloud through the towers, the Eye turning at its real speed, the flag, the
/// river, the rain and, in a storm, lightning in the clouds. It all runs on the graphics
/// chip at 30 frames a second, and stops when the window isn't in front.
struct LondonScene: View {
    var framing: LondonFraming = .window
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    @AppStorage(LondonWeather.rainKey) private var rain = true
    @AppStorage(LondonWeather.stormKey) private var storm = false

    var body: some View {
        LondonSceneView(weather: LondonWeather(rain: rain, storm: storm), framing: framing, moving: !reduceMotion, running: activeState != .inactive)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Where the skyline sits. In a window it's composed like the prototype; in Cinema it drops
/// low, so the river runs along the bottom and the sky above stays open for the clock.
enum LondonFraming: Equatable {
    case window, cinema
}

/// The London theme's weather, chosen in Settings. A storm is heavier, windier rain with
/// lightning, so it only applies while rain is on.
struct LondonWeather: Equatable {
    var rain: Bool
    var storm: Bool

    static let rainKey = "london.rain"
    static let stormKey = "london.storm"
}

private struct LondonSceneView: NSViewRepresentable {
    let weather: LondonWeather
    let framing: LondonFraming
    let moving: Bool
    let running: Bool

    func makeNSView(context: Context) -> LondonMetalView { LondonMetalView() }

    func updateNSView(_ view: LondonMetalView, context: Context) {
        view.configure(weather: weather, framing: framing, moving: moving, running: running)
    }
}

/// Matches `Uniforms` in the shader: four float4s.
private struct LondonUniforms {
    var a: SIMD4<Float>   // drawable width, height, time, rain
    var b: SIMD4<Float>   // fit scale, x offset, y offset, night
    var c: SIMD4<Float>   // drift x, drift y, Eye angle, lightning
    var d: SIMD4<Float>   // hour hand, minute hand, wind, unused
}

@MainActor
private final class LondonMetalView: MTKView {
    /// Compiled once per launch; the textures are let go with the view.
    private static var pipeline: MTLRenderPipelineState?
    private static let layerNames = ["london-far", "london-back", "london-mid", "london-wheel",
                                     "london-far-lights", "london-back-lights", "london-mid-lights", "london-wheel-lights"]

    private var queue: MTLCommandQueue?
    private var textures: [MTLTexture] = []
    private var sampler: MTLSamplerState?
    private var weather = LondonWeather(rain: true, storm: false)
    private var framing = LondonFraming.window
    private var animating = true
    private var time = 0.0
    private var lastFrame: CFTimeInterval?
    private var lightning = LondonLightning()

    init() {
        super.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
        colorPixelFormat = .bgra8Unorm
        colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        framebufferOnly = true
        autoResizeDrawable = false
        preferredFramesPerSecond = 30
        clearColor = MTLClearColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1)
        prepare()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(weather: LondonWeather, framing: LondonFraming, moving: Bool, running: Bool) {
        self.weather = weather
        self.framing = framing
        animating = moving && running
        isPaused = !animating
        enableSetNeedsDisplay = !animating
        if !animating {
            lastFrame = nil
            needsDisplay = true
        }
    }

    // The scene is soft and atmospheric, so it renders at up to 1.5x rather than the full
    // Retina resolution: under half the pixels, and it looks the same.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        fitDrawable()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        fitDrawable()
    }

    private func fitDrawable() {
        let scale = min(window?.backingScaleFactor ?? 2, 1.5)
        guard bounds.width > 0, bounds.height > 0 else { return }
        drawableSize = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        if isPaused { needsDisplay = true }
    }

    private func prepare() {
        guard let device else { return }
        queue = device.makeCommandQueue()
        if Self.pipeline == nil, let library = try? device.makeLibrary(source: LondonShader.source, options: nil) {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "londonVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "londonFragment")
            descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
            Self.pipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
        }
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: samplerDescriptor)
        // The light layers get mipmaps: the shader reads the blurrier levels as glow.
        let loaded = Self.layerNames.compactMap { name in
            Self.texture(named: name, device: device, queue: queue, mipmapped: name.hasSuffix("-lights"))
        }
        if loaded.count == Self.layerNames.count { textures = loaded }
    }

    private static func texture(named name: String, device: MTLDevice, queue: MTLCommandQueue?, mipmapped: Bool) -> MTLTexture? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = image.width, height = image.height
        // Premultiplied, which is what the shader's blending and the glow mipmaps expect.
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let bytes = context.data else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: mipmapped)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: bytes, bytesPerRow: width * 4)
        if mipmapped, let buffer = queue?.makeCommandBuffer(), let blit = buffer.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: texture)
            blit.endEncoding()
            buffer.commit()
            buffer.waitUntilCompleted()
        }
        return texture
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let pipeline = Self.pipeline, let queue, let sampler, textures.count == Self.layerNames.count,
              let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
              let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        let now = CACurrentMediaTime()
        let dt = animating ? lastFrame.map { min(0.1, now - $0) } ?? 0 : 0
        lastFrame = now
        time += dt
        let stormy = weather.rain && weather.storm
        lightning.step(dt: dt, storm: stormy && animating)

        let size = drawableSize
        // Cover the window, with room for the drift. In Cinema the frame is fitted to the
        // width and lowered so the river sits near the bottom edge (the sky above is drawn
        // as far up as it needs to go), leaving the upper half clear for the clock.
        let scale: Double, offsetY: Double
        switch framing {
        case .window:
            scale = max(size.width / 1600, size.height / 1000) * 1.03
            offsetY = (size.height - 1000 * scale) * 0.55
        case .cinema:
            scale = max(size.width / 1600, size.height / 1150) * 1.03
            offsetY = size.height * 0.88 - 703 * scale
        }
        let tau = Double.pi * 2
        // The view drifts ever so slightly, as if you were sitting at the window.
        let driftX = sin(time * tau / 31) * 3.2 + sin(time * tau / 12.7) * 0.7
        let driftY = sin(time * tau / 23) * 1.2
        let date = Date()
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minute = Double(parts.minute ?? 0), hour = Double((parts.hour ?? 0) % 12) + minute / 60
        // The real Eye takes 30 minutes a turn; this one keeps the same time.
        let eyeAngle = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 1800) / 1800 * tau
        // The rain comes and goes a little on its own.
        let rain = weather.rain ? (stormy ? 1.6 : 1) * (0.78 + 0.14 * sin(time * 0.13) + 0.1 * sin(time * 0.047 + 1.3)) : 0
        var uniforms = LondonUniforms(
            a: SIMD4(Float(size.width), Float(size.height), Float(time), Float(rain)),
            b: SIMD4(Float(scale), Float((size.width - 1600 * scale) / 2), Float(offsetY), 1),
            c: SIMD4(Float(driftX), Float(driftY), Float(eyeAngle), Float(lightning.level)),
            d: SIMD4(Float(hour / 12 * tau), Float(minute / 60 * tau), stormy ? 0.22 : 0.1, 0))

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<LondonUniforms>.stride, index: 0)
        for (index, texture) in textures.enumerated() { encoder.setFragmentTexture(texture, index: index) }
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

/// Lightning inside the cloud: every so often two to five quick flickers, then a slow fade.
private struct LondonLightning {
    private(set) var level = 0.0
    private var target = 0.0
    private var clock = 0.0
    private var nextStrike = 4.0
    private var pulses: [(at: Double, to: Double)] = []

    mutating func step(dt: Double, storm: Bool) {
        clock += dt
        if storm, clock >= nextStrike {
            let pattern: [(Double, Double)] = [(0, 0.8), (0.07, 0.15), (0.15, 1), (0.26, 0.3), (0.34, 0.65)]
            let count = Int.random(in: 2...5)
            pulses = pattern.prefix(count).map { (clock + $0.0, $0.1 * Double.random(in: 0.55...1)) }
            pulses.append((clock + pattern[count - 1].0 + 0.09, 0))
            nextStrike = clock + Double.random(in: 9...24)
        }
        while let first = pulses.first, first.at <= clock {
            target = first.to
            pulses.removeFirst()
        }
        if !storm { target = 0; pulses = [] }
        level += (target - level) * (target > level ? min(1, dt * 40) : min(1, dt * 3.5))
    }
}

// MARK: - Shader

private enum LondonShader {
    static let source = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms { float4 a; float4 b; float4 c; float4 d; };
    struct Out { float4 position [[position]]; };

    constant float2 VSIZE = float2(1600., 1000.);
    constant float TOP = 370., LH = 342.;        // the band of the frame the layer images cover
    constant float WATER = 703.;
    constant float3 EYE = float3(1112., 553., 118.);   // hub, and half the wheel image's size
    constant float2 FLAG = float2(262.8, 392.);
    constant float2 DIAL = float2(642., 545.1);
    constant float2 LAMPS[3] = { float2(818., 528.), float2(1250., 552.), float2(1352.8, 444.) };

    vertex Out londonVertex(uint id [[vertex_id]]) {
        float2 p = float2(float((id << 1) & 2), float(id & 2));
        Out o; o.position = float4(p * 2. - 1., 0., 1.); return o;
    }

    float hash(float2 p) { p = fract(p * float2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
    float noise(float2 p) {
        float2 i = floor(p), f = fract(p), u = f * f * (3. - 2. * f);
        return mix(mix(hash(i), hash(i + float2(1, 0)), u.x), mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), u.x), u.y);
    }
    float fbm(float2 p) { float v = 0., a = .5; for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.03 + float2(17.1, 9.2); a *= .5; } return v; }

    float2 layerUV(float2 v) { return float2(v.x / VSIZE.x, (v.y - TOP) / LH); }
    bool inside(float2 t) { return t.x >= 0. && t.x <= 1. && t.y >= 0. && t.y <= 1.; }
    float4 layer(texture2d<float> t, sampler s, float2 v) { float2 uv = layerUV(v); return inside(uv) ? t.sample(s, uv, level(0.)) : float4(0.); }
    // A light layer: the sharp light plus two wider glows from its mipmaps.
    float3 lightOf(texture2d<float> t, sampler s, float2 v) {
        float2 uv = layerUV(v);
        if (!inside(uv)) return float3(0.);
        return t.sample(s, uv, level(0.)).rgb * .85 + t.sample(s, uv, level(2.5)).rgb * .3 + t.sample(s, uv, level(4.6)).rgb * .45;
    }
    // Layers are premultiplied: lay one over the scene, darkened for night and hazed by distance.
    float3 over(float3 col, float4 p, float3 amb, float3 haze, float h) { return col * (1. - p.a) + p.rgb * amb * (1. - h) + p.a * haze * h; }
    float hand(float2 p, float angle, float len, float width) {
        float2 dir = float2(sin(angle), -cos(angle));
        float t = clamp(dot(p, dir), 0., len);
        return 1. - smoothstep(width * .5, width * .5 + .45, length(p - dir * t));
    }

    float3 skyAt(float2 v, constant Uniforms &u) {
        float time = u.a.z, night = u.b.w, flash = u.c.w;
        float h = clamp(v.y / 700., 0., 1.);
        float2 cp = float2(v.x * .0014 + time * .0045, v.y * .0046);
        float c = fbm(cp + .7 * fbm(cp * 1.8 + float2(time * .006, 0.)));
        float thin = fbm(float2(v.x * .004 + time * .011, v.y * .012));
        float3 day = mix(float3(.45, .49, .53), float3(.72, .73, .72), pow(h, 1.2));
        day *= mix(1.05, .80, smoothstep(.36, .78, c));
        day = mix(day, float3(.81, .82, .81), smoothstep(.58, .9, thin) * .2 * (1. - h));
        // night: low cloud lit orange from the streets below, darker in the gaps
        float3 nite = mix(float3(.05, .055, .08), float3(.31, .205, .14), pow(h, 1.7));
        nite *= mix(.72, 1.35, smoothstep(.3, .75, c));
        nite += float3(.03, .02, .014) * smoothstep(.55, .9, thin) * h;
        // lightning lights the cloud from inside, brightest where it's thickest
        nite += flash * float3(.42, .46, .62) * (.3 + 1.1 * smoothstep(.3, .8, c)) * (1. - .35 * h);
        return mix(day, nite, night);
    }

    float3 view(float2 v, constant Uniforms &u,
                texture2d<float> farT, texture2d<float> backT, texture2d<float> midT, texture2d<float> wheelT,
                texture2d<float> farE, texture2d<float> backE, texture2d<float> midE, texture2d<float> wheelE, sampler s) {
        float time = u.a.z, rain = u.a.w, night = u.b.w, flash = u.c.w;
        float2 sway = u.c.xy;
        float3 sky = skyAt(v + sway * .08, u);
        float3 haze = mix(mix(float3(.67, .69, .69), sky, .3), mix(float3(.12, .10, .095), sky, .45), night);
        float3 amb = mix(float3(1.), float3(.19, .18, .21), night) + flash * float3(.2, .22, .28);
        float3 col = sky;
        float2 vf = v + sway * .25;
        col = over(col, layer(farT, s, vf), amb, haze, .6);
        col += lightOf(farE, s, vf) * night * .6;
        for (int i = 0; i < 3; i++) {
            float d = length(vf - LAMPS[i]); float p = .5 + .5 * sin(time * 1.9 + float(i) * 2.1);
            col += float3(.8, .12, .08) * exp(-d * d / 5.) * (.15 + .65 * p * p) * (1. + 1.4 * night);
        }
        // low cloud drifting through the tops of the tallest towers, glowing where lights are inside it
        float mist = fbm(float2(v.x * .0035 - time * .016, v.y * .013 + time * .002));
        float band = smoothstep(380., 470., v.y) * (1. - smoothstep(505., 610., v.y));
        float3 mistCol = mix(float3(.69, .71, .71), float3(.17, .125, .10), night)
                       + farE.sample(s, clamp(layerUV(vf), 0., 1.), level(5.5)).rgb * night * 1.6
                       + flash * float3(.3, .33, .42);
        col = mix(col, mistCol, band * smoothstep(.42, .78, mist) * .85);
        float2 vb = v + sway * .45;
        col = over(col, layer(backT, s, vb), amb, haze, .36);
        col += lightOf(backE, s, vb) * night * .8;
        col = mix(col, haze, .07 * rain);                  // a veil of rain between near and far
        float2 vm = v + sway * .7;
        float2 q = vm - EYE.xy; float ca = cos(u.c.z), sa = sin(u.c.z);
        q = float2(ca * q.x - sa * q.y, sa * q.x + ca * q.y);
        float2 wc = q / EYE.z * .5 + .5;
        if (inside(wc)) {
            col = over(col, wheelT.sample(s, wc, level(0.)), amb, haze, .22);
            col += (wheelE.sample(s, wc, level(0.)).rgb * 1.2 + wheelE.sample(s, wc, level(3.)).rgb * 1.4) * night;
        }
        col = over(col, layer(midT, s, vm), amb, haze, .13);
        col += lightOf(midE, s, vm) * night;
        // Big Ben's hands, at the real time
        float2 dq = vm - DIAL;
        if (length(dq) < 9.6) {
            float k = max(hand(dq, u.d.x, 4.55, 1.4), hand(dq, u.d.y, 7.3, 1.));
            col = mix(col, float3(.05, .045, .04), k * .92);
        }
        // the Union Flag over Victoria Tower, lifting in the wind
        float2 f = (vm - FLAG) / float2(19., 10.);
        float wave = sin(f.x * 5.5 - time * 3.4);
        f.y -= wave * .09 * f.x;
        if (f.x > 0. && f.x < 1. && f.y > 0. && f.y < 1.) {
            float2 g = (f - .5) * float2(2., 1.);
            float3 fc = float3(.14, .2, .38);
            float diag = min(abs(g.y - g.x * .5), abs(g.y + g.x * .5));
            if (diag < .1) fc = float3(.86);
            if (diag < .04) fc = float3(.7, .14, .16);
            if (abs(g.x) < .2 || abs(g.y) < .1) fc = float3(.86);
            if (abs(g.x) < .12 || abs(g.y) < .06) fc = float3(.72, .13, .15);
            fc *= (.84 + .16 * wave) * mix(1., .5, night);
            col = mix(fc, haze, .25);
        }
        return col;
    }

    float streaks(float2 p, float cell, float len, float speed, float seed, float time, float wind) {
        p.x += p.y * wind;
        float c = floor(p.x / cell);
        float r = hash(float2(c, seed));
        float y = p.y / len - time * speed * (.75 + .5 * r) + r * 17.;
        float on = step(.62, hash(float2(c * 1.3 + seed, floor(y))));
        float s = fract(y);
        float x = abs(fract(p.x / cell) - .5 - (r - .5) * .5);
        return on * (1. - smoothstep(.02, .09, x)) * smoothstep(0., .25, s) * (1. - smoothstep(.25, .55, s));
    }

    fragment float4 londonFragment(Out in [[stage_in]], constant Uniforms &u [[buffer(0)]],
                                   texture2d<float> farT [[texture(0)]], texture2d<float> backT [[texture(1)]],
                                   texture2d<float> midT [[texture(2)]], texture2d<float> wheelT [[texture(3)]],
                                   texture2d<float> farE [[texture(4)]], texture2d<float> backE [[texture(5)]],
                                   texture2d<float> midE [[texture(6)]], texture2d<float> wheelE [[texture(7)]],
                                   sampler s [[sampler(0)]]) {
        float2 res = u.a.xy, px = in.position.xy;
        float time = u.a.z, rain = u.a.w, night = u.b.w;
        float2 sway = u.c.xy;
        float2 v = (px - u.b.yz) / u.b.x;
        float2 vm = v + sway * .7;
        float3 col;
        if (vm.y < WATER) col = view(v, u, farT, backT, midT, wheelT, farE, backE, midE, wheelE, s);
        else {
            // the Thames: dark water reflecting the bank, broken up by the current and the rain
            float d = vm.y - WATER;
            float far01 = smoothstep(0., 280., d);
            float rip = noise(float2(v.x * .02 + time * .12, d * .25 - time * .7)) + .5 * noise(float2(v.x * .06 - time * .09, d * .7 - time * 1.3));
            float wob = (rip - .75) * (1.5 + d * .06);
            float3 refl = view(float2(v.x + wob, 2. * WATER - vm.y - sway.y * .7 + wob * .3), u, farT, backT, midT, wheelT, farE, backE, midE, wheelE, s);
            col = mix(mix(float3(.30, .31, .29), float3(.02, .025, .03), night), refl * .9, mix(.8, .42, far01));
            col += (rip - .75) * mix(.06, .02, night) * (1. - far01 * .5);
            // at night every light pulls into a long shimmering column on the water
            if (night > .01) {
                float3 sum = float3(0.);
                for (int i = 0; i < 6; i++) {
                    float k = float(i) - 2.5;
                    float2 rq = float2(vm.x + wob * (1.6 + abs(k) * .5), 2. * WATER - vm.y + k * (2. + d * .07));
                    float2 uv = layerUV(rq);
                    if (inside(uv)) sum += midE.sample(s, uv, level(1.5)).rgb + backE.sample(s, layerUV(rq - sway * .25), level(2.)).rgb * .5;
                }
                col += sum / 6. * night * 1.5 * (1. - far01 * .35) * (.7 + .6 * rip);
            }
            // rain landing on the river
            float2 rp = float2(v.x, d * 2.6) / (5. + d * .05);
            float2 cell = floor(rp);
            float hs = hash(cell), ph = time * .8 + hs * 7.3, t = fract(ph);
            float2 ctr = float2(hash(cell + floor(ph) * 3.1), hash(cell + floor(ph) * 7.7 + 1.)) * .6 + .2;
            float ring = abs(length(fract(rp) - ctr) - t * .4);
            col += (1. - smoothstep(0., .06, ring)) * (1. - t) * step(.5, hs) * mix(.07, .035, night) * rain;
        }
        // rain falling outside, near and far
        float2 rv = v + sway;
        float r = streaks(rv, 3.2, 26., 22., 1., time, u.d.z) * .07 + streaks(rv, 6., 60., 13., 7., time, u.d.z) * .11;
        col = mix(col, mix(float3(.87, .89, .9), float3(.55, .45, .38), night) + u.c.w * .3, r * rain * mix(1., .8, night));
        // the warm room behind you, faintly reflected in the glass, and a soft vignette
        float2 t = px / res;
        col += float3(.07, .04, .015) * mix(1., 1.6, night) * (1. - smoothstep(0., .75, length((t - float2(.95, 1.05)) * float2(1.3, 1.))));
        col *= 1. - mix(.3, .4, night) * smoothstep(.45, 1.35, length((t - .5) * float2(1.3, 1.)));
        return float4(saturate(col), 1.);
    }
    """#
}
