import AVFoundation
import SwiftUI

/// Short guided resets for when focus is gone: a minute to drop your shoulders, a few
/// minutes to settle a busy head, or a gentle start after days away. Recorded once and
/// bundled, so they play offline. Voice by elevenlabs.io.
enum FocusReset: String, CaseIterable, Identifiable {
    case oneMinute = "reset-one-minute"
    case settle = "reset-settle"
    case comingBack = "reset-coming-back"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneMinute: "One minute"
        case .settle: "Settle a busy mind"
        case .comingBack: "Coming back"
        }
    }

    /// When to pick this one, so it's obvious which to follow.
    var whenToUse: String {
        switch self {
        case .oneMinute: "You've drifted, or you're about to start and need a moment first."
        case .settle: "Your head's full, you feel scattered, or the work feels like too much."
        case .comingBack: "You've been away a few days and starting again feels heavy."
        }
    }

    var length: String {
        switch self {
        case .oneMinute: "1 min"
        case .settle: "3 min"
        case .comingBack: "2 min"
        }
    }

    var icon: String {
        switch self {
        case .oneMinute: "wind"
        case .settle: "cloud"
        case .comingBack: "sunrise"
        }
    }

    /// When the voice says to breathe in or out, in seconds from the start of the recording,
    /// and how long that breath lasts. Measured from the assembled audio, so the flower
    /// opens and closes with the voice. Re-measure if a recording is redone.
    var breaths: [BreathCue] {
        switch self {
        case .oneMinute: [BreathCue(17.57, 6.12, .inhale), BreathCue(23.69, 6.46, .exhale),
                          BreathCue(30.15, 6.12, .inhale), BreathCue(36.27, 6.04, .exhale)]
        case .settle: [BreathCue(26.1, 6.01, .inhale), BreathCue(32.11, 9.11, .exhale),
                       BreathCue(152.33, 5.8, .inhale), BreathCue(158.13, 6.27, .exhale)]
        case .comingBack: [BreathCue(21.8, 5.37, .inhale), BreathCue(27.17, 7.39, .exhale),
                           BreathCue(74.93, 7.1, .inhale), BreathCue(82.03, 6.16, .exhale)]
        }
    }

    /// What the voice says and when, for following along without sound.
    var captions: [Caption] {
        switch self {
        case .oneMinute: [
            Caption(0.50, 5.45, "Okay. Let's take a quick pause."),
            Caption(5.45, 11.85, "Drop your shoulders… they're probably up near your ears."),
            Caption(12.35, 17.07, "And unclench your jaw a little."),
            Caption(17.57, 22.19, "Breathe in through your nose…"),
            Caption(23.69, 27.65, "and out."),
            Caption(30.15, 34.77, "Once more. In…"),
            Caption(36.27, 40.81, "and let it all go."),
            Caption(42.31, 45.87, "That's it."),
            Caption(47.37, 53.01, "Have a look around the room. What can you hear?"),
            Caption(57.51, 64.43, "You don't have to figure everything out right now. Just the next little bit."),
            Caption(65.93, 67.86, "Alright. Back to it.")
        ]
        case .settle: [
            Caption(0.50, 6.43, "Hey. Let's slow things down for a few minutes."),
            Caption(6.93, 14.57, "Get comfortable. Feet on the floor… hands wherever they want to be."),
            Caption(16.07, 23.60, "You can close your eyes, or just rest them on one spot. Either's fine."),
            Caption(26.10, 30.61, "Take a big breath in…"),
            Caption(32.11, 37.72, "and out, nice and slow."),
            Caption(41.22, 48.24, "Now just breathe normally. You don't need to do anything special with it."),
            Caption(51.74, 61.13, "See if you can feel it somewhere. Your chest, maybe… or your stomach rising and falling."),
            Caption(68.63, 78.68, "Your mind's going to wander. Everyone's does. It'll drift to your to-do list, or something from earlier today."),
            Caption(82.18, 91.28, "When it does, that's okay. Just notice where it went… and come back to the breath."),
            Caption(100.78, 109.57, "Still with me? Good. And if you drifted off, that's fine too. Just come on back."),
            Caption(119.07, 127.96, "Now think about the thing you were trying to work on. Not the whole thing. Just the very start of it."),
            Caption(131.46, 141.59, "What's the first thing you'd actually do? Open the document. Write one sentence. Something that small."),
            Caption(147.09, 151.83, "Okay. Hold on to that."),
            Caption(152.33, 156.63, "One more breath in…"),
            Caption(158.13, 161.90, "and out."),
            Caption(164.40, 169.55, "Open your eyes whenever you're ready. Start with that one small thing.")
        ]
        case .comingBack: [
            Caption(0.50, 4.80, "Hey. Welcome back."),
            Caption(5.30, 13.21, "It's been a few days. And honestly, that's fine. It happens to everyone."),
            Caption(15.71, 21.30, "Before you start, just take a second with me."),
            Caption(21.80, 25.67, "Breathe in…"),
            Caption(27.17, 31.06, "and out."),
            Caption(34.56, 45.05, "You might be feeling a bit of… ugh, I don't want to. That's normal after a break. You don't have to fight it."),
            Caption(50.55, 59.84, "Getting back into it is usually quicker than it feels right now. The first few minutes are the hardest part."),
            Caption(62.34, 71.43, "That's why today's block is a little shorter. Just finish this one. That's the whole goal."),
            Caption(74.93, 80.53, "One more breath. In…"),
            Caption(82.03, 85.69, "and out."),
            Caption(88.19, 94.61, "You don't need to catch up on anything. Just this one block."),
            Caption(95.11, 97.28, "Okay. Whenever you're ready.")
        ]
        }
    }

    /// The one that fits right now, and why: coming back after time away, settling after a
    /// rough block, otherwise the quick one.
    @MainActor static func suggestion(for model: AppModel) -> (reset: FocusReset, reason: String) {
        if let plan = model.focusPlan {
            if let reentry = plan.reentry(sessions: model.sessions) {
                return (.comingBack, "You've been away \(reentry.daysAway) days.")
            }
            if plan.easing(sessions: model.sessions) > 0 { return (.settle, "Your last block was a tough one.") }
        }
        return (.oneMinute, "A quick one before you start.")
    }
}

/// What plays quietly under the voice.
enum ResetAmbience: String, CaseIterable, Identifiable {
    case none, rain, binaural, music

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Just the voice"
        case .rain: "Rain"
        case .binaural: "Binaural beats"
        case .music: "Meditation music"
        }
    }

    var subtitle: String {
        switch self {
        case .none: "Nothing underneath"
        case .rain: "Rain against a window"
        case .binaural: "A slow 6 Hz beat. Use headphones"
        case .music: "Soft and slow, no beat"
        }
    }

    var icon: String {
        switch self {
        case .none: "person.wave.2"
        case .rain: "cloud.rain"
        case .binaural: "headphones"
        case .music: "music.note"
        }
    }

    var fileName: String? {
        switch self {
        case .none: nil
        case .rain: "rain"
        case .binaural: "ambience-binaural"
        case .music: "ambience-music"
        }
    }

    /// Low enough that the voice always sits on top.
    var volume: Double {
        switch self {
        case .none: 0
        case .rain: 0.32
        case .binaural: 0.22
        case .music: 0.3
        }
    }

    /// Shown only when its recording is in the app.
    var isAvailable: Bool {
        guard let fileName else { return true }
        return Bundle.main.url(forResource: fileName, withExtension: "m4a") != nil
    }
}

/// One breath the voice guides: when it starts, how long it lasts, and which way.
struct BreathCue: Equatable {
    let start: TimeInterval
    let length: TimeInterval
    let stage: BreathingStage

    init(_ start: TimeInterval, _ length: TimeInterval, _ stage: BreathingStage) {
        self.start = start
        self.length = length
        self.stage = stage
    }
}

/// One spoken line and when it's on screen.
struct Caption: Equatable {
    let start: TimeInterval
    let end: TimeInterval
    let text: String

    init(_ start: TimeInterval, _ end: TimeInterval, _ text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// A reset under way: the voice, the ambience under it, and where it's up to. The
/// ambience fades in first, the voice follows, and the ambience fades out after it.
@MainActor
@Observable
final class FocusResetSession: NSObject, AVAudioPlayerDelegate {
    let reset: FocusReset
    let ambience: ResetAmbience
    private(set) var isPlaying = false
    private(set) var finished = false
    @ObservationIgnored private var voice: AVAudioPlayer?
    @ObservationIgnored private let bed = AmbientSoundPlayer()
    @ObservationIgnored private var fade: Task<Void, Never>?
    @ObservationIgnored private var bedVolume = 0.0
    /// Seconds of ambience before the voice starts, so it doesn't begin abruptly.
    private static let leadIn: TimeInterval = 2.5

    init(reset: FocusReset, ambience: ResetAmbience) {
        self.reset = reset
        self.ambience = ambience
        super.init()
        if let url = Bundle.main.url(forResource: reset.rawValue, withExtension: "m4a") {
            voice = try? AVAudioPlayer(contentsOf: url)
            voice?.delegate = self
            voice?.prepareToPlay()
        }
    }

    var duration: TimeInterval { voice?.duration ?? 0 }
    var elapsed: TimeInterval { voice?.currentTime ?? 0 }

    func begin() {
        isPlaying = true
        if let name = ambience.fileName {
            bed.start(loopNamed: name, volume: 0)
            fadeBed(to: ambience.volume, over: Self.leadIn + 1)
        }
        voice?.play(atTime: (voice?.deviceCurrentTime ?? 0) + (ambience == .none ? 0.6 : Self.leadIn))
    }

    func togglePause() {
        guard let voice, !finished else { return }
        if voice.isPlaying {
            voice.pause()
            fade?.cancel()
            bed.pause()
        } else {
            voice.play()
            if let name = ambience.fileName { bed.start(loopNamed: name, volume: bedVolume) }
        }
        isPlaying = voice.isPlaying
    }

    func end() {
        fade?.cancel()
        voice?.stop()
        bed.stop()
        isPlaying = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        MainActor.assumeIsolated {
            isPlaying = false
            finished = true
            // Let the ambience carry on for a moment, then fade away.
            fadeBed(to: 0, over: 8, after: 4)
        }
    }

    private func fadeBed(to target: Double, over seconds: Double, after delay: Double = 0) {
        guard ambience.fileName != nil else { return }
        fade?.cancel()
        let start = bedVolume
        fade = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            let steps = max(1, Int(seconds * 20))
            for step in 1...steps {
                guard !Task.isCancelled, let self else { return }
                let t = Double(step) / Double(steps)
                // Ease in and out, so the fade has no audible start or end.
                let eased = t * t * (3 - 2 * t)
                self.bedVolume = start + (target - start) * eased
                self.bed.setVolume(self.bedVolume)
                try? await Task.sleep(for: .milliseconds(50))
            }
            if target == 0 { self?.bed.stop() }
        }
    }
}

/// The Focus reset section, in two short steps: pick a mode, then what you'd like to
/// hear, then begin. One question at a time, nothing else on screen.
struct FocusResetView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var picked: FocusReset?
    @State private var choosingAudio = false

    var body: some View {
        let suggestion = FocusReset.suggestion(for: model)
        let mode = picked ?? suggestion.reset
        let audio = ResetAmbience(rawValue: model.settings.resetAmbience).flatMap { $0.isAvailable ? $0 : nil } ?? .rain
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(choosingAudio ? "Step 2 of 2" : "Step 1 of 2")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(NonnaTheme.secondaryInk)
                    Text(choosingAudio ? "What would you like to hear?" : "How are you feeling?")
                        .font(.system(size: 30, weight: .regular, design: .serif))
                }

                Group {
                    if choosingAudio {
                        VStack(spacing: 10) {
                            ForEach(ResetAmbience.allCases.filter(\.isAvailable)) { option in
                                row(icon: option.icon, title: option.title, detail: option.subtitle,
                                    trailing: nil, tag: nil, selected: option == audio) {
                                    model.updateSettings { $0.resetAmbience = option.rawValue }
                                }
                            }
                        }
                        .transition(.opacity)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(FocusReset.allCases) { reset in
                                row(icon: reset.icon, title: reset.title, detail: reset.whenToUse,
                                    trailing: reset.length, tag: reset == suggestion.reset ? "Suggested" : nil,
                                    selected: reset == mode) {
                                    picked = reset
                                }
                            }
                        }
                        .transition(.opacity)
                    }
                }

                HStack(spacing: 12) {
                    if choosingAudio {
                        Button("Back") { step(toAudio: false) }
                            .buttonStyle(NonnaButtonStyle(prominent: false))
                        Button {
                            model.activeReset = FocusResetSession(reset: mode, ambience: audio)
                        } label: {
                            Label("Begin", systemImage: "play.fill")
                                .frame(minWidth: 120)
                        }
                        .buttonStyle(NonnaButtonStyle())
                        .keyboardShortcut(.defaultAction)
                    } else {
                        Button {
                            step(toAudio: true)
                        } label: {
                            Text("Next")
                                .frame(minWidth: 120)
                        }
                        .buttonStyle(NonnaButtonStyle())
                        .keyboardShortcut(.defaultAction)
                    }
                    Spacer()
                    Text("Voice by elevenlabs.io")
                        .font(.system(size: 11))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
            }
            .padding(30)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func step(toAudio: Bool) {
        withAnimation(reduceMotion ? nil : NonnaMotion.quick) { choosingAudio = toAudio }
    }

    /// One choice: icon, name, a line about it, and a ring when it's the one picked.
    private func row(icon: String, title: String, detail: String, trailing: String?, tag: String?,
                     selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(selected ? NonnaTheme.onAccent : NonnaTheme.terracotta)
                    .frame(width: 38, height: 38)
                    .background(selected ? NonnaTheme.terracotta : NonnaTheme.raisedPaper, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                        if let tag {
                            Text(tag)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(NonnaTheme.terracotta)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(NonnaTheme.terracotta.opacity(0.14), in: Capsule())
                        }
                    }
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NonnaTheme.paper.opacity(selected ? 1 : 0.55),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? NonnaTheme.terracotta.opacity(0.75) : NonnaTheme.line, lineWidth: selected ? 1.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The reset itself: the whole window in the theme's background colour, the breathing
/// flower in the middle, captions under it if they're on, and dimmed controls that brighten
/// when the pointer moves. Space pauses, Esc leaves.
struct FocusResetSessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: FocusResetSession
    @State private var showsControls = true
    @State private var hideControls: Task<Void, Never>?
    /// Fades the whole scene in on arrival and out on leaving; the window switches back
    /// only once it's gone.
    @State private var shown = false
    @State private var leaving = false

    var body: some View {
        ZStack {
            // A click anywhere brings the controls back.
            NonnaTheme.cream.ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { revealControls() }

            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                let at = session.elapsed
                VStack(spacing: 40) {
                    Spacer()
                    ResetBreath(cue: session.finished ? nil : session.reset.breaths.first { at >= $0.start && at < $0.start + $0.length })
                    captionLine(at: at)
                        .frame(height: 70, alignment: .top)
                    Spacer()
                }
                .padding(.horizontal, 60)
            }

            VStack {
                HStack {
                    Button {
                        leave()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .background(NonnaTheme.paper.opacity(0.8), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .help("Leave (Esc)")
                    Spacer()
                }
                Spacer()
                if session.finished {
                    VStack(spacing: 14) {
                        Text("Nicely done.")
                            .font(.system(size: 24, weight: .regular, design: .serif))
                        Button {
                            leave(toTimer: true)
                        } label: {
                            Label("Back to the timer", systemImage: "timer")
                        }
                        .buttonStyle(NonnaButtonStyle())
                        .keyboardShortcut(.defaultAction)
                    }
                    .transition(.opacity)
                } else {
                    HStack(spacing: 16) {
                        Button {
                            session.togglePause()
                        } label: {
                            Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 40, height: 40)
                                .background(NonnaTheme.paper.opacity(0.8), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.space, modifiers: [])
                        .help(session.isPlaying ? "Pause (Space)" : "Resume (Space)")
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            let left = max(0, Int((session.duration - session.elapsed).rounded()))
                            Text(String(format: "%d:%02d", left / 60, left % 60))
                                .font(.system(size: 12, weight: .medium).monospacedDigit())
                                .foregroundStyle(NonnaTheme.secondaryInk)
                        }
                    }
                }
            }
            .padding(28)
            .foregroundStyle(NonnaTheme.ink)
            // Resting, the controls dim but stay visible and clickable, so there's always a
            // way out.
            .opacity(showsControls || session.finished || !session.isPlaying ? 1 : 0.28)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: showsControls)
        }
        .foregroundStyle(NonnaTheme.ink)
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(!leaving)
        .onContinuousHover { _ in revealControls() }
        .onAppear {
            session.begin()
            revealControls()
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.8)) { shown = true }
        }
        .onDisappear { session.end() }
        .animation(reduceMotion ? nil : NonnaMotion.settle, value: session.finished)
    }

    @ViewBuilder
    private func captionLine(at time: TimeInterval) -> some View {
        if model.settings.resetCaptions {
            let line = session.reset.captions.first { time >= $0.start && time < $0.end }
            Text(line?.text ?? " ")
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(NonnaTheme.ink.opacity(0.85))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
                .id(line?.text ?? "")
                .transition(.opacity)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: line?.text)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    /// The controls brighten while the pointer moves and dim after a few still seconds.
    private func revealControls() {
        showsControls = true
        hideControls?.cancel()
        hideControls = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { showsControls = false }
        }
    }

    private func leave(toTimer: Bool = false) {
        guard !leaving else { return }
        leaving = true
        session.end()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) { shown = false }
        Task {
            if !reduceMotion { try? await Task.sleep(for: .milliseconds(450)) }
            model.activeReset = nil
            if toTimer { model.focusScreenRequest += 1 }
        }
    }
}

/// The breathing flower from the pre-focus ritual, driven by the recording: it opens over
/// a breath in and closes over a breath out, taking as long as the voice does.
private struct ResetBreath: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let cue: BreathCue?
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 26) {
            BreathingFlower(expanded: expanded, accent: NonnaTheme.terracotta)
                .frame(width: 280, height: 280)
            Text(cue?.stage.prompt ?? " ")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(NonnaTheme.secondaryInk)
                .contentTransition(.opacity)
                .animation(reduceMotion ? nil : NonnaMotion.quick, value: cue?.stage)
        }
        .onAppear { follow(cue) }
        .onChange(of: cue) { _, next in follow(next) }
        .accessibilityElement(children: .combine)
    }

    private func follow(_ cue: BreathCue?) {
        // Between breaths the flower rests closed.
        let open = cue?.stage == .inhale
        let length = cue?.length ?? 2
        withAnimation(reduceMotion ? nil : .easeInOut(duration: length)) { expanded = open }
    }
}
