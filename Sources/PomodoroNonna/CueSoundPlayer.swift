import AVFoundation
import Foundation

/// Timer cues as a small bell "ding", generated locally like the ambient soundscapes.
/// Every cue is the same bell voice, so they sound like one family. Pitch, count, and
/// level tell them apart.
@MainActor
final class CueSoundPlayer {
    enum Cue: Hashable {
        case start
        case pause
        case resume
        case complete
        case presence
        case overtimeReminder
    }

    private var players: [AVAudioPlayer] = []
    private var cache: [Cue: Data] = [:]

    func play(_ cue: Cue) {
        players.removeAll { !$0.isPlaying }
        let data: Data
        if let cached = cache[cue] {
            data = cached
        } else {
            data = Self.waveData(samples: Self.render(Self.strikes(for: cue)))
            cache[cue] = data
        }
        guard let player = try? AVAudioPlayer(data: data) else { return }
        player.volume = Self.volume(for: cue)
        player.prepareToPlay()
        player.play()
        players.append(player)
    }

    // MARK: - Voicing

    private struct Strike {
        let frequency: Double
        let offset: Double
        let level: Double
        let decay: Double
    }

    private static func strikes(for cue: Cue) -> [Strike] {
        switch cue {
        case .start, .resume:
            [Strike(frequency: 1_174.66, offset: 0, level: 0.9, decay: 0.42)]
        case .pause:
            [Strike(frequency: 880, offset: 0, level: 0.8, decay: 0.26)]
        case .complete:
            [
                Strike(frequency: 1_174.66, offset: 0, level: 0.9, decay: 0.5),
                Strike(frequency: 1_567.98, offset: 0.24, level: 0.9, decay: 0.75)
            ]
        case .presence:
            [Strike(frequency: 1_567.98, offset: 0, level: 0.7, decay: 0.34)]
        case .overtimeReminder:
            [Strike(frequency: 1_174.66, offset: 0, level: 0.85, decay: 0.38)]
        }
    }

    private static func volume(for cue: Cue) -> Float {
        switch cue {
        case .complete: 0.62
        case .start, .overtimeReminder: 0.5
        case .resume, .pause: 0.4
        case .presence: 0.3
        }
    }

    // MARK: - Synthesis

    private static let sampleRate = 44_100

    /// A struck bell: a clear fundamental plus two inharmonic partials that fade faster,
    /// which is what makes it read as "ding" rather than a beep.
    private static func render(_ strikes: [Strike]) -> [Int16] {
        let tail = strikes.map { $0.offset + $0.decay * 6 }.max() ?? 1
        let count = Int(tail * Double(sampleRate))
        var buffer = [Double](repeating: 0, count: count)

        for strike in strikes {
            let first = Int(strike.offset * Double(sampleRate))
            guard first < count else { continue }
            for index in first..<count {
                let time = Double(index - first) / Double(sampleRate)
                let attack = min(1, time / 0.002)
                let body = sin(2 * .pi * strike.frequency * time) * exp(-time / strike.decay)
                let shimmer = sin(2 * .pi * strike.frequency * 2.76 * time) * exp(-time / (strike.decay * 0.45)) * 0.32
                let sparkle = sin(2 * .pi * strike.frequency * 5.4 * time) * exp(-time / (strike.decay * 0.2)) * 0.14
                buffer[index] += (body + shimmer + sparkle) * attack * strike.level * 0.6
            }
        }

        return buffer.map { sample in
            Int16(max(-1, min(1, tanh(sample))) * Double(Int16.max))
        }
    }

    private static func waveData(samples: [Int16]) -> Data {
        let byteCount = UInt32(samples.count * MemoryLayout<Int16>.size)
        var data = Data()
        func ascii(_ string: String) { data.append(contentsOf: string.utf8) }
        func little<T: FixedWidthInteger>(_ value: T) {
            var encoded = value.littleEndian
            Swift.withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
        }
        ascii("RIFF")
        little(UInt32(36) + byteCount)
        ascii("WAVE")
        ascii("fmt ")
        little(UInt32(16))
        little(UInt16(1))
        little(UInt16(1))
        little(UInt32(sampleRate))
        little(UInt32(sampleRate * 2))
        little(UInt16(2))
        little(UInt16(16))
        ascii("data")
        little(byteCount)
        samples.withUnsafeBytes { data.append(contentsOf: $0) }   // little-endian host
        return data
    }
}
