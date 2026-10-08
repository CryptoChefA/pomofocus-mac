import AppKit
import SwiftUI

/// The panel that drops from the menu-bar item: a miniature of the main dial.
struct MenuBarTimerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isAlerting: Bool { model.isOvertime && model.settings.overtimeAlert }
    private var isFlashing: Bool { isAlerting && model.status == .overtime }

    private var accent: Color {
        if isAlerting { return NonnaTheme.alert }
        if let next = model.awaitingNextPhase { return NonnaTheme.accent(for: next) }
        return NonnaTheme.accent(for: model.phase)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.bottom, 20)
            dial
                .padding(.bottom, showsFocusContext ? 16 : 20)
            if showsFocusContext {
                context
                    .padding(.bottom, 18)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            controls
            Rectangle()
                .fill(NonnaTheme.line)
                .frame(height: 0.8)
                .padding(.top, 20)
                .padding(.bottom, 14)
            footer
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 17)
        .frame(width: 326)
        .background { panelBackground }
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.13), NonnaTheme.line.opacity(0.72), .black.opacity(0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
                .padding(1)
        }
        .foregroundStyle(NonnaTheme.ink)
        .animation(reduceMotion ? nil : NonnaMotion.page, value: showsFocusContext)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 7) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                    .shadow(color: accent.opacity(0.62), radius: 5)
                Text(eyebrow)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(2.2)
                    .foregroundStyle(accent)
            }
            .alertFlash(isFlashing)
            Spacer()
            cycleDots
        }
    }

    private var eyebrow: String {
        if model.awaitingNextPhase != nil { return "BREAK COMPLETE" }
        if model.isBreathing { return "BREATH \(model.breathingCycle) OF \(AppModel.breathingCycleCount)" }
        if model.status == .paused { return "PAUSED" }
        if model.status == .overtime { return model.phase == .focus ? "FOCUS OVERTIME" : "BREAK OVERTIME" }
        return model.phase.compactTitle
    }

    /// One dot per focus block in the current run toward a long break.
    private var cycleDots: some View {
        let every = max(1, model.settings.longBreakEvery)
        let completed = model.completedFocusCycleCount
        let remainder = completed % every
        let filled = completed > 0 && remainder == 0 ? every : remainder
        return HStack(spacing: 4) {
            ForEach(0..<every, id: \.self) { index in
                Capsule()
                    .fill(index < filled ? NonnaTheme.terracotta : NonnaTheme.strongLine)
                    .frame(width: index < filled ? 11 : 6, height: 3)
            }
        }
        .help("\(filled) of \(every) focus blocks before a long break")
        .animation(reduceMotion ? nil : NonnaMotion.selection, value: filled)
    }

    // MARK: - Dial

    private var dial: some View {
        ZStack {
            // Static face and bezel: views with no inputs, so they are never rebuilt.
            MiniDialFace()

            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(
                    AngularGradient(
                        colors: [accent.opacity(0.35), accent],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * max(0.001, ringProgress))
                    ),
                    style: StrokeStyle(lineWidth: 2.6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(2)
                .shadow(color: accent.opacity(0.38), radius: 7)
                // Transaction order matters: the inner modifier wins, so phase changes
                // always settle smoothly, while the per-second glide only runs when the
                // ring moves far enough each second for a step to be visible.
                .animation(reduceMotion ? nil : NonnaMotion.settle, value: ringStage)
                .animation(reduceMotion || !ringGlides ? nil : .linear(duration: 1), value: ringProgress)

            Circle()
                .trim(from: 0.08, to: 0.39)
                .stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                .rotationEffect(.degrees(-78))
                .padding(7)

            VStack(spacing: 5) {
                if model.isBreathing {
                    Text(timeText)
                        .font(.system(size: 17, weight: .medium))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(width: 122)
                } else {
                    RollingClockText(
                        text: timeText,
                        countsDown: !model.isOvertime,
                        travel: 16,
                        animation: reduceMotion ? nil : NonnaMotion.numeric
                    )
                        .font(.system(size: 40, weight: .medium))
                        .tracking(-1.5)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .allowsTightening(true)
                        .frame(width: 136)
                        .foregroundStyle(isAlerting ? NonnaTheme.alert : NonnaTheme.ink)
                        .shadow(color: isAlerting ? NonnaTheme.alert.opacity(0.38) : .clear, radius: isAlerting ? 10 : 0)
                        .alertFlash(isFlashing)
                }
                Text(caption)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            .padding(.horizontal, 22)
        }
        .frame(width: 180, height: 180)
        .drawingGroup(opaque: false, colorMode: .linear)
    }

    /// Coarse state of the ring, so a jump between phases animates even when the
    /// per-second glide is off.
    private var ringStage: String {
        "\(model.phase.rawValue)-\(model.status.rawValue)-\(model.isBreathing)-\(model.awaitingNextPhase != nil)-\(model.isOvertime)"
    }

    /// Whether the ring advances at least ~¾ pt per second (breathing, short breaks). A
    /// 25-minute ring moves about a third of a point a second, where a one-second glide
    /// would keep the panel redrawing continuously for no visible difference.
    private var ringGlides: Bool {
        let seconds = model.isBreathing ? AppModel.breathingTotalSeconds : max(1, model.plannedSeconds)
        return 2 * Double.pi * 88 / Double(seconds) >= 0.75
    }

    private var ringProgress: Double {
        if model.isBreathing {
            let total = Double(AppModel.breathingTotalSeconds)
            return min(1, max(0, (total - Double(model.breathingRemaining)) / total))
        }
        if model.isOvertime || model.awaitingNextPhase != nil { return 1 }
        if model.status == .idle { return 0 }
        return model.progress
    }

    private var timeText: String {
        if model.isBreathing { return model.breathingStage.prompt }
        if model.status == .idle { return model.remainingSeconds.clockString }
        return (model.isOvertime ? "+" : "") + model.displaySeconds.clockString
    }

    private var caption: String {
        if model.awaitingNextPhase != nil { return "NEXT PHASE" }
        if model.isBreathing { return "BREATHING" }
        switch model.status {
        case .idle:
            return "\(model.plannedSeconds / 60) MIN"
        case .paused:
            return "\(model.remainingSeconds.clockString) LEFT"
        case .overtime:
            return "OVERTIME"
        case .running:
            let end = Date().addingTimeInterval(TimeInterval(model.remainingSeconds))
            return "ENDS \(end.formatted(date: .omitted, time: .shortened))"
        }
    }

    // MARK: - Task and intention

    private var showsFocusContext: Bool {
        model.phase == .focus || model.awaitingNextPhase == .focus
    }

    private var context: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(NonnaTheme.taskColor(for: model.selectedTask?.colorHex ?? "BDA56F"))
                    .frame(width: 6, height: 6)
                Text(model.selectedTask?.name ?? "No task")
                    .font(.system(size: 11, weight: .medium))
            }
            if !model.intention.isEmpty {
                Text(model.intention)
                    .font(.system(size: 11))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 8) {
            if model.isBreathing {
                panelButton("Skip breaths", icon: "forward.fill", prominent: true) { model.skipBreathing() }
                panelButton("Cancel", icon: "xmark", prominent: false) { model.cancelBreathing() }
            } else if model.canAdvanceCycle {
                panelButton(
                    model.nextActionTitle,
                    icon: "arrow.right",
                    prominent: true,
                    color: model.cycleNextPhase.map { NonnaTheme.accent(for: $0) } ?? accent
                ) { model.advanceToNextPhase() }
                if model.phase == .focus, model.isOvertime {
                    panelButton("Skip break", icon: "forward.end.fill", prominent: false) { model.skipBreakAndStartFocus() }
                    compactEndButton
                } else {
                    panelButton("End session", icon: "stop.fill", prominent: false) { model.endSession() }
                }
            } else if model.status == .idle {
                panelButton(
                    model.phase == .focus ? "Begin focus" : "Begin rest",
                    icon: "play.fill",
                    prominent: true
                ) { model.start() }
                if model.hasOpenRun {
                    panelButton("End session", icon: "stop.fill", prominent: false) { model.endSession() }
                }
            } else {
                panelButton(
                    model.status == .paused ? "Resume" : "Pause",
                    icon: model.status == .paused ? "play.fill" : "pause.fill",
                    prominent: true
                ) { model.togglePause() }
                if model.phase == .focus {
                    panelButton("End session", icon: "stop.fill", prominent: false) { model.endSession() }
                } else {
                    panelButton("Skip break", icon: "forward.end.fill", prominent: false) { model.skipBreakAndStartFocus() }
                    compactEndButton
                }
            }
        }
    }

    /// End session as a square key, for rows that already hold two buttons.
    private var compactEndButton: some View {
        Button {
            model.endSession()
        } label: {
            Image(systemName: "stop.fill")
                .font(.system(size: 10, weight: .bold))
                .frame(width: 14, height: 44)
        }
        .buttonStyle(NonnaButtonStyle(prominent: false))
        .fixedSize()
        .help("End session: keep what's tracked and stop")
        .accessibilityLabel("End session")
    }

    private func panelButton(
        _ title: String,
        icon: String,
        prominent: Bool,
        color: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
        .buttonStyle(NonnaButtonStyle(color: color ?? accent, prominent: prominent))
    }

    // MARK: - Footer

    private var footer: some View {
        let goal = max(1, model.settings.dailyGoalMinutes * 60)
        let today = todayFocusSeconds
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text("TODAY")
                        .tracking(1.4)
                        .foregroundStyle(NonnaTheme.secondaryInk)
                    Text("\(today.focusDurationString) / \(goal.focusDurationString)")
                        .foregroundStyle(NonnaTheme.ink)
                }
                .font(.system(size: 8, weight: .semibold, design: .monospaced))

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(NonnaTheme.line)
                        Capsule()
                            .fill(NonnaTheme.terracotta)
                            .frame(width: proxy.size.width * min(1, Double(today) / Double(goal)))
                    }
                }
                .frame(height: 2.5)
            }

            Button {
                CinematicController.shared.enter(model: model)
            } label: {
                Image(systemName: "sparkles.tv")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .frame(width: 26, height: 26)
                    .background(NonnaTheme.raisedPaper)
                    .clipShape(Circle())
                    .overlay { Circle().stroke(NonnaTheme.line, lineWidth: 0.8) }
            }
            .buttonStyle(.plain)
            .help("Cinema mode")

            Button {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
            } label: {
                HStack(spacing: 4) {
                    Text("Open")
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NonnaTheme.secondaryInk)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(NonnaTheme.raisedPaper)
                .clipShape(Capsule())
                .overlay { Capsule().stroke(NonnaTheme.line, lineWidth: 0.8) }
            }
            .buttonStyle(.plain)
            .help("Open Pomofocus")
        }
    }

    /// Finished focus today plus the block that is running right now.
    private var todayFocusSeconds: Int {
        let finished = model.todayRecordedFocusSeconds
        let live = model.phase == .focus && model.status != .idle ? model.elapsedSeconds : 0
        return finished + live
    }

    // MARK: - Surface

    private var panelBackground: some View {
        ZStack {
            NonnaTheme.cream
            RadialGradient(
                colors: [accent.opacity(0.13), accent.opacity(0.035), .clear],
                center: .topLeading,
                startRadius: 4,
                endRadius: 270
            )
            RadialGradient(
                colors: [.white.opacity(0.025), .clear],
                center: .bottomTrailing,
                startRadius: 4,
                endRadius: 220
            )
            LinearGradient(
                colors: [.white.opacity(0.025), .clear, .black.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct MiniDialFace: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            NonnaTheme.line,
                            .white.opacity(0.17),
                            NonnaTheme.strongLine,
                            .black.opacity(0.72),
                            NonnaTheme.line
                        ],
                        center: .center
                    )
                )
                .shadow(color: .black.opacity(0.7), radius: 18, y: 10)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            NonnaTheme.raisedPaper.opacity(0.98),
                            NonnaTheme.paper,
                            NonnaTheme.sunken
                        ],
                        center: .topLeading,
                        startRadius: 4,
                        endRadius: 108
                    )
                )
                .padding(4)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.12), NonnaTheme.line, .black.opacity(0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
                .padding(5)

            DialTicks(radius: 83, major: false, majorSize: CGSize(width: 1, height: 5), minorSize: CGSize(width: 0.6, height: 2.5))
                .fill(NonnaTheme.line)
            DialTicks(radius: 83, major: true, majorSize: CGSize(width: 1, height: 5), minorSize: CGSize(width: 0.6, height: 2.5))
                .fill(NonnaTheme.secondaryInk.opacity(0.55))
        }
    }
}
