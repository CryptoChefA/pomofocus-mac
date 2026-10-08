import AVFoundation
import Foundation

@MainActor
final class AmbientSoundPlayer {
    private var player: AVAudioPlayer?
    private var activeSound: AmbientSound = .off

    func start(_ sound: AmbientSound, volume: Double) {
        guard sound != .off else {
            stop()
            return
        }

        if activeSound == sound, let player {
            player.volume = Float(volume)
            player.play()
            return
        }

        do {
            let nextPlayer = try AVAudioPlayer(data: Self.audioData(for: sound))
            nextPlayer.numberOfLoops = -1
            nextPlayer.volume = Float(volume)
            nextPlayer.prepareToPlay()
            nextPlayer.play()
            player = nextPlayer
            activeSound = sound
        } catch {
            player = nil
            activeSound = .off
        }
    }

    func pause() {
        player?.pause()
    }

    func setVolume(_ volume: Double) {
        player?.volume = Float(volume)
    }

    func stop() {
        player?.stop()
        player = nil
        activeSound = .off
    }

    private static let sampleRate = 44_100
    /// Only the soundscape in use stays in memory (each is 0.7–2 MB of PCM). Switching
    /// sounds releases the previous one instead of accumulating all four.
    private static var cache: (sound: AmbientSound, data: Data)?

    private static func audioData(for sound: AmbientSound) -> Data {
        if let cache, cache.sound == sound { return cache.data }
        let samples: [Int16] = switch sound {
        case .off: []
        case .ticking: tickingSamples(seconds: 8)
        case .rain: rainSamples(seconds: 24)
        case .ocean: oceanSamples(seconds: 16)
        case .brownNoise: brownNoiseSamples(seconds: 16)
        }
        let data = waveData(samples: samples)
        cache = (sound, data)
        return data
    }

    private static func tickingSamples(seconds: Int) -> [Int16] {
        let count = sampleRate * seconds
        return (0..<count).map { index in
            let position = index % sampleRate
            guard position < sampleRate / 28 else { return 0 }
            let time = Double(position) / Double(sampleRate)
            let envelope = exp(-time * 105)
            let tone = sin(2 * .pi * 1_650 * time) * 0.55 + sin(2 * .pi * 930 * time) * 0.28
            return pcm(tone * envelope * 0.72)
        }
    }

    private static func rainSamples(seconds: Int) -> [Int16] {
        var random = SeededRandom(seed: 0x4E4F4E4E41)
        let count = sampleRate * seconds
        var rain = [Double](repeating: 0, count: count)
        var fast = 0.0
        var middle = 0.0
        var distant = 0.0

        // A very quiet, band-limited rain bed. Most of what you hear comes from
        // the individual impacts below, avoiding the broadband "radio static" sound.
        for index in 0..<count {
            let white = random.signed()
            fast += (white - fast) * 0.16
            middle += (fast - middle) * 0.024
            distant += (white - distant) * 0.0018
            let phase = Double(index) / Double(count) * 2 * .pi
            let intensity = 0.72 + sin(phase * 2) * 0.10 + sin(phase * 5 + 1.4) * 0.06
            rain[index] = ((fast - middle) * 0.042 + distant * 0.018) * intensity
        }

        // Layer hundreds of short, differently pitched window and leaf impacts.
        // Each droplet has a quick noise transient, a damped water resonance,
        // and a faint reflection so the result feels spatial rather than synthetic.
        var cursor = Int(Double(sampleRate) * 0.12)
        while cursor < count {
            let interval = 0.028 + pow(random.unit(), 1.7) * 0.17
            cursor += max(1, Int(interval * Double(sampleRate)))
            guard cursor < count else { break }

            let isLargeDrop = random.unit() < 0.12
            let amplitude = isLargeDrop
                ? 0.10 + random.unit() * 0.09
                : 0.035 + random.unit() * 0.075
            let frequency = (isLargeDrop ? 520.0 : 880.0) + random.unit() * (isLargeDrop ? 900.0 : 1_850.0)
            let decay = (isLargeDrop ? 0.055 : 0.025) + random.unit() * (isLargeDrop ? 0.055 : 0.035)
            let length = min(count - cursor, Int(decay * 6.5 * Double(sampleRate)))
            let echoDelay = Int((0.026 + random.unit() * 0.035) * Double(sampleRate))
            let phaseOffset = random.unit() * 2 * .pi

            for offset in 0..<length {
                let time = Double(offset) / Double(sampleRate)
                let envelope = exp(-time / decay)
                let attack = min(1, time / 0.0025)
                let phase = 2 * .pi * (frequency * time - frequency * 0.18 * time * time) + phaseOffset
                let resonance = sin(phase) * 0.72 + sin(phase * 1.61) * 0.18
                let impact = random.signed() * exp(-time * 115)
                let value = amplitude * attack * envelope * (resonance + impact * 0.32)
                rain[cursor + offset] += value

                let echoIndex = cursor + offset + echoDelay
                if echoIndex < count {
                    rain[echoIndex] += value * 0.11
                }
            }
        }

        // Blend the tail into the opening texture for a soft, unobtrusive loop.
        let blendCount = min(sampleRate, count / 8)
        if blendCount > 0 {
            for offset in 0..<blendCount {
                let amount = Double(offset) / Double(blendCount)
                let tailIndex = count - blendCount + offset
                rain[tailIndex] = rain[tailIndex] * (1 - amount) + rain[offset] * amount
            }
        }

        return rain.map { pcm(tanh($0 * 1.35) * 0.88) }
    }

    private static func oceanSamples(seconds: Int) -> [Int16] {
        var random = SeededRandom(seed: 0x4D415245)
        var smooth = 0.0
        var deeper = 0.0
        var samples = [Int16]()
        samples.reserveCapacity(sampleRate * seconds)
        let total = sampleRate * seconds

        for index in 0..<total {
            let white = random.signed()
            smooth = smooth * 0.94 + white * 0.06
            deeper = deeper * 0.995 + smooth * 0.005
            let phase = Double(index) / Double(total)
            let swell = 0.22 + pow((sin(phase * 4 * .pi - .pi / 2) + 1) / 2, 1.8) * 0.68
            let foam = white * 0.05 + smooth * 0.38 + deeper * 0.42
            samples.append(pcm(foam * swell))
        }
        return samples
    }

    private static func brownNoiseSamples(seconds: Int) -> [Int16] {
        var random = SeededRandom(seed: 0x42524F574E)
        var brown = 0.0
        var samples = [Int16]()
        samples.reserveCapacity(sampleRate * seconds)

        for _ in 0..<(sampleRate * seconds) {
            brown = (brown + random.signed() * 0.018) / 1.018
            let normalized = brown * 3.2
            samples.append(pcm(normalized))
        }
        return samples
    }

    private static func pcm(_ sample: Double) -> Int16 {
        Int16(max(-1, min(1, sample)) * Double(Int16.max))
    }

    private static func waveData(samples: [Int16]) -> Data {
        let byteCount = UInt32(samples.count * MemoryLayout<Int16>.size)
        var data = Data(capacity: 44 + Int(byteCount))
        data.appendASCII("RIFF")
        data.appendLittleEndian(UInt32(36) + byteCount)
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(UInt32(sampleRate * 2))
        data.appendLittleEndian(UInt16(2))
        data.appendLittleEndian(UInt16(16))
        data.appendASCII("data")
        data.appendLittleEndian(byteCount)
        // One bulk copy instead of a million single-sample appends (Apple silicon is
        // little-endian, which is what WAV expects).
        data.reserveCapacity(data.count + Int(byteCount))
        samples.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }
}

private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func unit() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }

    mutating func signed() -> Double { unit() * 2 - 1 }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
