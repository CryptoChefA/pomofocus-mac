import AppKit
import IOKit.pwr_mgt
import SwiftUI

// MARK: - Controller

/// Cinema: the running timer as a full-screen, screensaver-like scene, laid out for wide
/// and ultrawide displays. It fades in over whichever screen the pointer is on, keeps the
/// display awake, and gets out of the way with Esc.
///
/// Everything that moves continuously (the drifting glow, the progress tape, the live
/// marker) is a Core Animation layer animation, composited by the window server. The app
/// itself only redraws once a second, when the digits roll.
@MainActor
final class CinematicController {
    static let shared = CinematicController()

    private var window: CinematicWindow?
    private var sleepAssertion: IOPMAssertionID = 0
    private var previousPresentation: NSApplication.PresentationOptions = []
    private var screenObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?

    var isActive: Bool { window != nil }

    func toggle(model: AppModel) {
        if isActive { exit() } else { enter(model: model) }
    }

    func enter(model: AppModel) {
        guard window == nil else { return }
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) })
            ?? NSScreen.main ?? NSScreen.screens.first else { return }

        let window = CinematicWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(NonnaTheme.cream)
        window.isOpaque = true
        window.hasShadow = false
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        window.setFrame(screen.frame, display: false)
        window.contentView = NSHostingView(
            rootView: CinematicView(onExit: { [weak self] in self?.exit() })
                .environment(model)
        )
        window.onKey = { [weak self, weak model] key in
            guard let self, let model else { return false }
            return self.handle(key, model: model)
        }
        window.alphaValue = 0
        self.window = window

        previousPresentation = NSApp.presentationOptions
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // Presentation options only take while Pomofocus is frontmost: switch to your
        // notes and the menu bar and Dock come back; switch back and the scene is edge to
        // edge again. Activation can land a moment later, so apply on arrival too.
        applyPresentation()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPresentation() }
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.9
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 1
        }

        IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Pomofocus Cinema is showing the timer" as CFString,
            &sleepAssertion
        )

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refitToScreen() }
        }
    }

    func exit() {
        guard let window else { return }
        self.window = nil
        if sleepAssertion != 0 {
            IOPMAssertionRelease(sleepAssertion)
            sleepAssertion = 0
        }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        screenObserver = nil
        activationObserver = nil
        NSApp.presentationOptions = previousPresentation

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.55
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            window.orderOut(nil)
            window.contentView = nil   // release the scene and its layers
        }
    }

    private func applyPresentation() {
        guard window != nil, NSApp.isActive else { return }
        NSApp.presentationOptions = [.autoHideDock, .autoHideMenuBar]
    }

    private func refitToScreen() {
        guard let window else { return }
        let screen = window.screen ?? NSScreen.main
        if let frame = screen?.frame { window.setFrame(frame, display: true) }
    }

    private func handle(_ key: CinematicWindow.Key, model: AppModel) -> Bool {
        switch key {
        case .escape:
            exit()
        case .space:
            if model.isBreathing {
                model.skipBreathing()
            } else if model.status == .idle, model.canAdvanceCycle {
                model.advanceToNextPhase()
            } else if model.status == .idle {
                model.start()
            } else {
                model.togglePause()
            }
        case .next:
            guard model.canAdvanceCycle else { return false }
            model.advanceToNextPhase()
        case .end:
            guard model.canEndSession else { return false }
            model.endSession()
        }
        return true
    }
}

final class CinematicWindow: NSWindow {
    enum Key { case escape, space, next, end }

    var onKey: ((Key) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        let key: Key? = switch event.keyCode {
        case 53: .escape        // esc
        case 49: .space         // space
        case 124, 36: .next     // → or return
        case 14: .end           // e
        default: nil
        }
        if let key, onKey?(key) == true { return }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        _ = onKey?(.escape)
    }
}

// MARK: - Scene

struct CinematicView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onExit: () -> Void

    @State private var appeared = false
    @State private var controlsVisible = true
    @State private var hideControls: Task<Void, Never>?
    @State private var drift: CGSize = .zero

    private var isAlerting: Bool { model.isOvertime && model.settings.overtimeAlert }
    private var isFlashing: Bool { isAlerting && model.status == .overtime }

    private var accent: Color {
        if isAlerting { return NonnaTheme.alert }
        if let next = model.awaitingNextPhase { return NonnaTheme.accent(for: next) }
        return NonnaTheme.accent(for: model.phase)
    }

    var body: some View {
        GeometryReader { proxy in
            // One unit drives every size, so the scene is composed the same on a laptop,
            // a 16:9 display, or a 32:9 ultrawide.
            let unit = min(proxy.size.height, proxy.size.width / 2.1)
            let sideMargin = max(unit * 0.09, proxy.size.width * 0.055)

            ZStack {
                CinematicBackdrop(accent: NSColor(accent), animates: !reduceMotion)

                VStack(spacing: 0) {
                    topBar(unit: unit)
                        .reveal(appeared, delay: 0.35, reduceMotion: reduceMotion)
                    Spacer(minLength: 0)
                    centerpiece(unit: unit)
                        .reveal(appeared, delay: 0.1, reduceMotion: reduceMotion)
                    Spacer(minLength: 0)
                    horizon(unit: unit)
                        .reveal(appeared, delay: 0.55, reduceMotion: reduceMotion)
                }
                .padding(.horizontal, sideMargin)
                .padding(.top, unit * 0.06)
                .padding(.bottom, unit * 0.075)
                .offset(drift)

                controls(unit: unit)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, unit * 0.2)
                    .opacity(controlsVisible ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: controlsVisible)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .background(NonnaTheme.cream)
        .foregroundStyle(NonnaTheme.ink)
        .preferredColorScheme(.dark)
        .onContinuousHover { phase in
            if case .active = phase { revealControls() }
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 1.3)) { appeared = true }
            revealControls()
        }
        .task {
            // A few points of slow drift now and then, so nothing sits on the same
            // pixels for hours on an OLED or a panel prone to image retention.
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(75))
                withAnimation(.easeInOut(duration: 8)) {
                    drift = CGSize(width: .random(in: -9...9), height: .random(in: -6...6))
                }
            }
        }
    }

    // MARK: Top bar

    private func topBar(unit: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: unit * 0.012) {
                Text("POMOFOCUS")
                    .foregroundStyle(NonnaTheme.terracotta)
                Text("·")
                    .foregroundStyle(NonnaTheme.secondaryInk.opacity(0.6))
                Text("CINEMA")
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            .font(.system(size: max(10, unit * 0.0115), weight: .semibold, design: .monospaced))
            .tracking(max(1.8, unit * 0.0035))

            Spacer()

            TimelineView(.everyMinute) { context in
                HStack(spacing: unit * 0.012) {
                    Text(context.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())
                        .foregroundStyle(NonnaTheme.secondaryInk)
                    Text(context.date.formatted(date: .omitted, time: .shortened))
                        .foregroundStyle(NonnaTheme.ink.opacity(0.82))
                }
                .font(.system(size: max(10, unit * 0.0115), weight: .medium, design: .monospaced))
                .tracking(max(1.2, unit * 0.002))
            }
        }
    }

    // MARK: Centerpiece

    private func centerpiece(unit: CGFloat) -> some View {
        VStack(spacing: unit * 0.022) {
            HStack(spacing: unit * 0.01) {
                Circle()
                    .fill(accent)
                    .frame(width: unit * 0.007, height: unit * 0.007)
                    .shadow(color: accent.opacity(0.7), radius: unit * 0.006)
                Text(eyebrow)
                    .font(.system(size: max(11, unit * 0.014), weight: .semibold, design: .monospaced))
                    .tracking(max(2.4, unit * 0.005))
                    .foregroundStyle(accent)
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : NonnaMotion.quick, value: eyebrow)
            }
            .alertFlash(isFlashing)

            ZStack {
                if model.isBreathing {
                    Text(model.breathingStage.prompt)
                        .font(.system(size: unit * 0.085, weight: .light))
                        .tracking(-unit * 0.001)
                        .id(model.breathingStage)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                } else {
                    RollingClockText(
                        text: clockText,
                        countsDown: !model.isOvertime,
                        travel: unit * 0.07,
                        animation: reduceMotion ? nil : .easeInOut(duration: 0.42)
                    )
                    .font(.system(size: unit * 0.235, weight: .light))
                    .tracking(-unit * 0.008)
                    .monospacedDigit()
                    .foregroundStyle(isAlerting ? NonnaTheme.alert : NonnaTheme.ink)
                    .shadow(color: isAlerting ? NonnaTheme.alert.opacity(0.35) : .clear, radius: isAlerting ? unit * 0.03 : 0)
                    .alertFlash(isFlashing)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                }
            }
            .frame(height: unit * 0.26)
            .animation(reduceMotion ? nil : NonnaMotion.settle, value: model.isBreathing)
            .animation(reduceMotion ? nil : .easeInOut(duration: 1.1), value: model.breathingStage)

            VStack(spacing: unit * 0.012) {
                if !model.intention.isEmpty, model.phase == .focus || model.awaitingNextPhase == .focus {
                    Text(model.intention)
                        .font(.system(size: max(15, unit * 0.03), weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(NonnaTheme.ink.opacity(0.78))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: unit * 1.4)
                }
                if model.phase == .focus, let task = model.selectedTask {
                    HStack(spacing: unit * 0.008) {
                        Circle()
                            .fill(NonnaTheme.taskColor(for: task.colorHex))
                            .frame(width: unit * 0.0055, height: unit * 0.0055)
                        Text(task.name.uppercased())
                    }
                    .font(.system(size: max(10, unit * 0.0105), weight: .medium, design: .monospaced))
                    .tracking(max(1.5, unit * 0.003))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                }
            }
            .frame(minHeight: unit * 0.07, alignment: .top)
        }
    }

    // MARK: Horizon

    private func horizon(unit: CGFloat) -> some View {
        VStack(spacing: unit * 0.02) {
            HorizonTape(
                fraction: tapeFraction,
                secondsToFull: tapeSecondsToFull,
                minutes: max(1, (model.isBreathing ? AppModel.breathingTotalSeconds : model.plannedSeconds) / 60),
                accent: NSColor(accent),
                isAlerting: isFlashing,
                isPaused: model.status == .paused,
                stateKey: tapeKey,
                animates: !reduceMotion
            )
            .frame(height: max(26, unit * 0.034))

            HStack(alignment: .firstTextBaseline) {
                Text(leftCaption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                cycleAndToday(unit: unit)
                    .frame(maxWidth: .infinity)
                Text(rightCaption)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: max(10, unit * 0.011), weight: .medium, design: .monospaced))
            .tracking(max(1.4, unit * 0.0026))
            .foregroundStyle(NonnaTheme.secondaryInk)
            .lineLimit(1)
        }
    }

    private func cycleAndToday(unit: CGFloat) -> some View {
        let every = max(1, model.settings.longBreakEvery)
        let completed = model.completedFocusCycleCount
        let remainder = completed % every
        let filled = completed > 0 && remainder == 0 ? every : remainder
        let goal = max(1, model.settings.dailyGoalMinutes * 60)
        let live = model.phase == .focus && model.status != .idle ? model.elapsedSeconds : 0
        let today = model.todayRecordedFocusSeconds + live
        return HStack(spacing: unit * 0.016) {
            HStack(spacing: unit * 0.004) {
                ForEach(0..<every, id: \.self) { index in
                    Capsule()
                        .fill(index < filled ? NonnaTheme.terracotta : NonnaTheme.strongLine)
                        .frame(width: index < filled ? unit * 0.014 : unit * 0.007, height: max(2, unit * 0.0028))
                }
            }
            Text("TODAY \(today.focusDurationString.uppercased()) / \(goal.focusDurationString.uppercased())")
        }
    }

    // MARK: Controls

    private func controls(unit: CGFloat) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                if model.isBreathing {
                    Button("Skip breaths") { model.skipBreathing() }
                        .buttonStyle(NonnaButtonStyle(color: accent))
                } else if model.canAdvanceCycle {
                    Button {
                        model.advanceToNextPhase()
                    } label: {
                        Label(model.nextActionTitle, systemImage: "arrow.right")
                    }
                    .buttonStyle(NonnaButtonStyle(color: model.cycleNextPhase.map { NonnaTheme.accent(for: $0) } ?? accent))
                } else if model.status == .idle {
                    Button {
                        model.start()
                    } label: {
                        Label(model.phase == .focus ? "Begin focus" : "Begin rest", systemImage: "play.fill")
                    }
                    .buttonStyle(NonnaButtonStyle(color: accent))
                } else {
                    Button {
                        model.togglePause()
                    } label: {
                        Label(model.status == .paused ? "Resume" : "Pause",
                              systemImage: model.status == .paused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(NonnaButtonStyle(color: accent))
                }

                if model.canEndSession {
                    Button {
                        model.endSession()
                    } label: {
                        Label("End session", systemImage: "stop.fill")
                    }
                    .buttonStyle(NonnaButtonStyle(prominent: false))
                }

                Button(action: onExit) {
                    Label("Leave cinema", systemImage: "arrow.down.right.and.arrow.up.left")
                }
                .buttonStyle(NonnaButtonStyle(prominent: false))
            }

            Text("SPACE  \(model.status == .idle ? "BEGIN" : "PAUSE")   ·   →  NEXT   ·   E  END SESSION   ·   ESC  LEAVE")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(NonnaTheme.secondaryInk.opacity(0.7))
        }
        .allowsHitTesting(controlsVisible)
    }

    private func revealControls() {
        if !controlsVisible { controlsVisible = true }
        hideControls?.cancel()
        hideControls = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.8))
            guard !Task.isCancelled else { return }
            controlsVisible = false
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    // MARK: Words and numbers

    private var eyebrow: String {
        if model.awaitingNextPhase != nil { return "BREAK COMPLETE" }
        if model.isBreathing { return "BREATH \(model.breathingCycle) OF \(AppModel.breathingCycleCount)" }
        switch model.status {
        case .idle: return "\(model.phase.compactTitle) · READY"
        case .paused: return "\(model.phase.compactTitle) · PAUSED"
        case .overtime: return model.phase == .focus ? "FOCUS OVERTIME" : "BREAK OVERTIME"
        case .running: return model.phase.compactTitle
        }
    }

    private var clockText: String {
        if model.status == .idle, model.awaitingNextPhase == nil { return model.remainingSeconds.clockString }
        return (model.isOvertime ? "+" : "") + model.displaySeconds.clockString
    }

    private var minutesLeftText: String {
        let minutes = Int((Double(model.remainingSeconds) / 60).rounded(.up))
        return minutes <= 1 ? "UNDER A MINUTE LEFT" : "\(minutes) MIN LEFT"
    }

    private var leftCaption: String {
        if model.isBreathing { return "SETTLING IN" }
        if model.awaitingNextPhase != nil { return "BLOCK FINISHED" }
        guard model.status != .idle, let started = model.activeTimerStartedAt else {
            return "\(model.plannedSeconds / 60) MIN \(model.phase == .focus ? "FOCUS" : "REST")"
        }
        return "STARTED \(started.formatted(date: .omitted, time: .shortened))"
    }

    private var rightCaption: String {
        if model.isBreathing { return "\(model.breathingRemaining)S OF BREATHING" }
        if let next = model.awaitingNextPhase {
            return "NEXT · \(next == .focus ? "FOCUS" : "REST")"
        }
        let percent = Int((model.progress * 100).rounded(.down))
        switch model.status {
        case .idle:
            return "SPACE TO BEGIN"
        case .paused:
            return "\(percent)% · \(minutesLeftText)"
        case .overtime:
            return "PLANNED \(model.plannedSeconds / 60) MIN · OVER BY \(max(0, model.elapsedSeconds - model.plannedSeconds).clockString)"
        case .running:
            let end = Date().addingTimeInterval(TimeInterval(model.remainingSeconds))
            return "\(percent)% · \(minutesLeftText) · ENDS \(end.formatted(date: .omitted, time: .shortened))"
        }
    }

    // MARK: Tape state

    /// Exact progress now, from the session's active intervals.
    private var tapeFraction: Double {
        if model.isBreathing {
            let total = Double(AppModel.breathingTotalSeconds)
            return min(1, max(0, (total - Double(model.breathingRemaining)) / total))
        }
        if model.awaitingNextPhase != nil || model.isOvertime { return 1 }
        guard model.status != .idle, model.plannedSeconds > 0 else { return 0 }
        let elapsed = model.activityIntervals.reduce(0.0) { $0 + $1.duration() }
        return min(1, max(0, elapsed / Double(model.plannedSeconds)))
    }

    /// Seconds until the tape is full, when it is moving; `nil` holds it still.
    private var tapeSecondsToFull: Double? {
        if model.isBreathing { return Double(model.breathingRemaining) }
        guard model.status == .running, !model.isOvertime else { return nil }
        let elapsed = model.activityIntervals.reduce(0.0) { $0 + $1.duration() }
        return max(0.1, Double(model.plannedSeconds) - elapsed)
    }

    /// Changes only when the motion itself changes (start, pause, resume, phase, …), so
    /// the tape's Core Animation runs untouched between them.
    private var tapeKey: String {
        "\(model.phase.rawValue)|\(model.status.rawValue)|\(model.plannedSeconds)|\(model.activityIntervals.count)|\(model.isOvertime)|\(model.isBreathing)|\(model.awaitingNextPhase?.rawValue ?? "-")"
    }
}

private extension View {
    /// The staggered fade-and-rise each part of the scene makes as Cinema opens.
    func reveal(_ shown: Bool, delay: Double, reduceMotion: Bool) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .animation(reduceMotion ? nil : .easeOut(duration: 1.2).delay(delay), value: shown)
    }
}

// MARK: - Backdrop

/// Two soft pools of the phase colour drifting very slowly behind a vignette. Pure Core
/// Animation: once added, the window server runs it without waking the app.
private struct CinematicBackdrop: NSViewRepresentable {
    let accent: NSColor
    let animates: Bool

    func makeNSView(context: Context) -> CinematicBackdropView { CinematicBackdropView() }

    func updateNSView(_ view: CinematicBackdropView, context: Context) {
        view.apply(accent: accent, animates: animates)
    }
}

final class CinematicBackdropView: NSView {
    private let glowA = CAGradientLayer()
    private let glowB = CAGradientLayer()
    private let vignette = CAGradientLayer()
    private var accent: NSColor = .clear
    private var animates = true

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for glow in [glowA, glowB] {
            glow.type = .radial
            glow.startPoint = CGPoint(x: 0.5, y: 0.5)
            glow.endPoint = CGPoint(x: 1, y: 1)
            glow.locations = [0, 0.42, 1]
            layer?.addSublayer(glow)
        }
        vignette.type = .radial
        vignette.startPoint = CGPoint(x: 0.5, y: 0.5)
        vignette.endPoint = CGPoint(x: 1, y: 1)
        vignette.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.62).cgColor]
        vignette.locations = [0, 0.5, 1]
        layer?.addSublayer(vignette)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply(accent: NSColor, animates: Bool) {
        let changedMotion = animates != self.animates
        self.animates = animates
        if accent != self.accent {
            self.accent = accent
            CATransaction.begin()
            CATransaction.setAnimationDuration(1.4)
            glowA.colors = [accent.withAlphaComponent(0.15).cgColor, accent.withAlphaComponent(0.045).cgColor, NSColor.clear.cgColor]
            glowB.colors = [accent.withAlphaComponent(0.1).cgColor, accent.withAlphaComponent(0.03).cgColor, NSColor.clear.cgColor]
            CATransaction.commit()
        }
        if changedMotion { layoutGlows() }
    }

    override func layout() {
        super.layout()
        layoutGlows()
    }

    private func layoutGlows() {
        let bounds = self.bounds
        guard bounds.width > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glowA.bounds = CGRect(x: 0, y: 0, width: bounds.width * 0.62, height: bounds.height * 1.45)
        glowA.position = CGPoint(x: bounds.width * 0.3, y: bounds.height * 0.58)
        glowB.bounds = CGRect(x: 0, y: 0, width: bounds.width * 0.5, height: bounds.height * 1.2)
        glowB.position = CGPoint(x: bounds.width * 0.74, y: bounds.height * 0.38)
        vignette.frame = bounds.insetBy(dx: -bounds.width * 0.08, dy: -bounds.height * 0.2)
        CATransaction.commit()

        glowA.removeAllAnimations()
        glowB.removeAllAnimations()
        guard animates else { return }
        glowA.add(drift(by: CGSize(width: bounds.width * 0.07, height: bounds.height * 0.06), from: glowA.position, duration: 43), forKey: "drift")
        glowB.add(drift(by: CGSize(width: -bounds.width * 0.06, height: bounds.height * 0.07), from: glowB.position, duration: 59), forKey: "drift")
        glowA.add(breathe(duration: 17), forKey: "breathe")
        glowB.add(breathe(duration: 23), forKey: "breathe")
    }

    private func drift(by offset: CGSize, from origin: CGPoint, duration: CFTimeInterval) -> CAAnimation {
        let animation = CABasicAnimation(keyPath: "position")
        animation.fromValue = NSValue(point: origin)
        animation.toValue = NSValue(point: CGPoint(x: origin.x + offset.width, y: origin.y + offset.height))
        animation.duration = duration
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return animation
    }

    private func breathe(duration: CFTimeInterval) -> CAAnimation {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 0.7
        animation.duration = duration
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return animation
    }
}

// MARK: - Horizon tape

/// The dial, unrolled for a wide screen: a hairline with a mark for every minute of the
/// block, a fill in the phase colour, and a glowing marker at "now". Between state changes
/// the fill and marker glide by a single Core Animation that runs to the end of the block.
private struct HorizonTape: NSViewRepresentable {
    let fraction: Double
    let secondsToFull: Double?
    let minutes: Int
    let accent: NSColor
    let isAlerting: Bool
    let isPaused: Bool
    let stateKey: String
    let animates: Bool

    func makeNSView(context: Context) -> HorizonTapeView { HorizonTapeView() }

    func updateNSView(_ view: HorizonTapeView, context: Context) {
        view.apply(
            fraction: fraction,
            secondsToFull: animates ? secondsToFull : nil,
            minutes: minutes,
            accent: accent,
            isAlerting: isAlerting,
            isPaused: isPaused,
            key: stateKey + (animates ? "" : "|still")
        )
    }
}

final class HorizonTapeView: NSView {
    private let track = CALayer()
    private let minorTicks = CAShapeLayer()
    private let majorTicks = CAShapeLayer()
    private let fill = CAGradientLayer()
    private let marker = CALayer()
    private let markerCore = CALayer()

    private var anchorFraction = 0.0
    private var anchorDate = Date()
    private var secondsToFull: Double?
    private var key = ""
    private var minutes = 25
    private var accent: NSColor = .white
    private var isAlerting = false
    private var isPaused = false

    private let fillHeight: CGFloat = 2.5
    private let markerSize: CGFloat = 11

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        track.backgroundColor = NSColor(NonnaTheme.line).cgColor
        minorTicks.fillColor = NSColor(NonnaTheme.strongLine).cgColor
        majorTicks.fillColor = NSColor(NonnaTheme.secondaryInk).withAlphaComponent(0.7).cgColor
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.startPoint = CGPoint(x: 0, y: 0.5)
        fill.endPoint = CGPoint(x: 1, y: 0.5)
        fill.cornerRadius = fillHeight / 2
        marker.bounds = CGRect(x: 0, y: 0, width: markerSize, height: markerSize)
        marker.cornerRadius = markerSize / 2
        marker.shadowOpacity = 0.95
        marker.shadowRadius = 10
        marker.shadowOffset = .zero
        markerCore.bounds = CGRect(x: 0, y: 0, width: 4, height: 4)
        markerCore.cornerRadius = 2
        markerCore.position = CGPoint(x: markerSize / 2, y: markerSize / 2)
        markerCore.backgroundColor = NSColor(NonnaTheme.ink).cgColor
        marker.addSublayer(markerCore)
        for sublayer in [track, minorTicks, majorTicks, fill, marker] { layer?.addSublayer(sublayer) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for sublayer in [track, minorTicks, majorTicks, fill, marker, markerCore] as [CALayer] {
            sublayer.contentsScale = scale
        }
    }

    func apply(
        fraction: Double,
        secondsToFull: Double?,
        minutes: Int,
        accent: NSColor,
        isAlerting: Bool,
        isPaused: Bool,
        key: String
    ) {
        if minutes != self.minutes {
            self.minutes = minutes
            layoutTicks()
        }
        if accent != self.accent || isAlerting != self.isAlerting || isPaused != self.isPaused {
            self.accent = accent
            self.isAlerting = isAlerting
            self.isPaused = isPaused
            applyColors()
        }
        if key != self.key {
            self.key = key
            restart(from: fraction, secondsToFull: secondsToFull)
        } else if let presented = presentedFraction, abs(presented - currentFraction) > 0.004 {
            // Core Animation's clock stops while the Mac sleeps; catch the tape up.
            restart(from: fraction, secondsToFull: secondsToFull)
        }
    }

    override func layout() {
        super.layout()
        layoutTicks()
        restart(from: currentFraction, secondsToFull: remainingSecondsNow)
    }

    // MARK: Motion

    private var currentFraction: Double {
        guard let secondsToFull, secondsToFull > 0 else { return anchorFraction }
        let progressed = Date().timeIntervalSince(anchorDate) / secondsToFull
        return min(1, anchorFraction + (1 - anchorFraction) * progressed)
    }

    private var remainingSecondsNow: Double? {
        guard let secondsToFull else { return nil }
        return max(0, secondsToFull - Date().timeIntervalSince(anchorDate))
    }

    private var presentedFraction: Double? {
        guard bounds.width > 0, let presented = fill.presentation() else { return nil }
        return Double(presented.bounds.width / bounds.width)
    }

    private func restart(from fraction: Double, secondsToFull: Double?) {
        anchorFraction = min(1, max(0, fraction))
        anchorDate = Date()
        self.secondsToFull = secondsToFull

        let width = bounds.width
        let midY = bounds.midY
        guard width > 0 else { return }
        let startWidth = width * anchorFraction

        fill.removeAnimation(forKey: "progress")
        marker.removeAnimation(forKey: "progress")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.position = CGPoint(x: 0, y: midY)
        let moving = (secondsToFull ?? 0) > 0 && anchorFraction < 1
        let endWidth = moving ? width : startWidth
        fill.bounds = CGRect(x: 0, y: 0, width: endWidth, height: fillHeight)
        marker.position = CGPoint(x: endWidth, y: midY)
        CATransaction.commit()

        guard moving, let secondsToFull else { return }
        let grow = CABasicAnimation(keyPath: "bounds.size.width")
        grow.fromValue = startWidth
        grow.toValue = width
        grow.duration = secondsToFull
        grow.timingFunction = CAMediaTimingFunction(name: .linear)
        fill.add(grow, forKey: "progress")

        let travel = CABasicAnimation(keyPath: "position.x")
        travel.fromValue = startWidth
        travel.toValue = width
        travel.duration = secondsToFull
        travel.timingFunction = CAMediaTimingFunction(name: .linear)
        marker.add(travel, forKey: "progress")
    }

    // MARK: Drawing

    private func applyColors() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.9)
        fill.colors = [accent.withAlphaComponent(0.12).cgColor, accent.withAlphaComponent(0.55).cgColor, accent.cgColor]
        fill.locations = [0, 0.7, 1]
        marker.backgroundColor = accent.cgColor
        marker.shadowColor = accent.cgColor
        CATransaction.commit()

        marker.removeAnimation(forKey: "flash")
        marker.opacity = isPaused ? 0.55 : 1
        if isAlerting {
            // The same slow caution pulse as the rest of the app's overtime alert.
            let flash = CABasicAnimation(keyPath: "opacity")
            flash.fromValue = 1
            flash.toValue = 0.4
            flash.duration = 1.35
            flash.autoreverses = true
            flash.repeatCount = .infinity
            flash.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            marker.add(flash, forKey: "flash")
        }
    }

    private func layoutTicks() {
        let width = bounds.width
        let midY = bounds.midY
        guard width > 0 else { return }

        // Short blocks get a mark every 30 seconds so the tape never looks empty.
        let marksPerMinute = minutes < 12 ? 2 : 1
        let count = max(1, minutes * marksPerMinute)
        let majorEvery = minutes < 12 ? 2 : 5
        let minor = CGMutablePath()
        let major = CGMutablePath()
        for index in 0...count {
            let x = width * CGFloat(index) / CGFloat(count)
            let isMajor = index % majorEvery == 0
            let height: CGFloat = isMajor ? 13 : 6
            let lineWidth: CGFloat = isMajor ? 1.2 : 0.8
            let mark = CGRect(x: x - lineWidth / 2, y: midY - height / 2, width: lineWidth, height: height)
            (isMajor ? major : minor).addRoundedRect(in: mark, cornerWidth: lineWidth / 2, cornerHeight: lineWidth / 2)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.frame = CGRect(x: 0, y: midY - 0.5, width: width, height: 1)
        minorTicks.frame = bounds
        majorTicks.frame = bounds
        minorTicks.path = minor
        majorTicks.path = major
        CATransaction.commit()
    }
}
