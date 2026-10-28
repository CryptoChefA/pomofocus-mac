import AVFoundation
import Foundation

/// Plays the focus ambience. Each sound is a short recorded (or pre-rendered) loop in the
/// app bundle, decoded once into memory and looped by the audio engine with no gap, so
/// there's never a click where the loop starts again. Only the sound in use is loaded.
@MainActor
final class AmbientSoundPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var activeSound: AmbientSound = .off
    private var isAttached = false
    private var isPaused = false
    private var configurationObserver: NSObjectProtocol?

    init() {
        // Plugging in or removing headphones stops the engine; pick up where it was.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartAfterRouteChange() }
        }
    }

    private func restartAfterRouteChange() {
        guard activeSound != .off else { return }
        let sound = activeSound
        let volume = Double(node.volume)
        let wasPaused = isPaused
        activeSound = .off
        start(sound, volume: volume)
        if wasPaused { pause() }
    }

    func start(_ sound: AmbientSound, volume: Double) {
        guard sound != .off else {
            stop()
            return
        }

        isPaused = false
        if activeSound == sound {
            node.volume = Float(volume)
            if !engine.isRunning { try? engine.start() }
            node.play()
            return
        }

        guard let buffer = Self.loop(for: sound) else {
            stop()
            return
        }
        node.stop()
        if !isAttached {
            engine.attach(node)
            isAttached = true
        }
        engine.disconnectNodeOutput(node)
        engine.connect(node, to: engine.mainMixerNode, format: buffer.format)
        node.scheduleBuffer(buffer, at: nil, options: .loops)
        node.volume = Float(volume)
        do {
            try engine.start()
        } catch {
            stop()
            return
        }
        node.play()
        activeSound = sound
    }

    func pause() {
        isPaused = true
        node.pause()
        engine.pause()
    }

    func setVolume(_ volume: Double) {
        node.volume = Float(volume)
    }

    func stop() {
        node.stop()
        engine.stop()
        activeSound = .off
    }

    private static func loop(for sound: AmbientSound) -> AVAudioPCMBuffer? {
        guard let name = sound.fileName,
              let url = Bundle.main.url(forResource: name, withExtension: "m4a"),
              let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        else { return nil }
        do {
            try file.read(into: buffer)
        } catch {
            return nil
        }
        return buffer
    }
}
