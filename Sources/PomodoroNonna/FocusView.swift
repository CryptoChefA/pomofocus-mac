import SwiftUI

struct FocusView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingNewTask = false
    @State private var showsInspector = false
    @State private var confirmsAbandon = false
    @Namespace private var phaseSelection

    private var accent: Color { isAlerting ? NonnaTheme.alert : NonnaTheme.accent(for: model.phase) }

    /// Past the planned time, with the alert switched on.
    private var isAlerting: Bool { model.isOvertime && model.settings.overtimeAlert }
    /// Only flash while the clock is actually running over. Paused overtime holds steady red.
    private var isFlashing: Bool { isAlerting && model.status == .overtime }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    HStack {
                        Text("POMOFOCUS")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(1.8)
                            .foregroundStyle(NonnaTheme.terracotta)
                        Spacer()
                        Button {
                            CinematicController.shared.enter(model: model)
                        } label: {
                            Label("Cinema", systemImage: "sparkles.tv")
                        }
                        .buttonStyle(NonnaButtonStyle(prominent: false))
                        .help("Show the timer full screen (⇧⌘F)")
                        Button {
                            showsInspector = true
                        } label: {
                            Label("Session", systemImage: "doc.text.image")
                        }
                        .buttonStyle(NonnaButtonStyle(prominent: false))
                        .keyboardShortcut("i", modifiers: [.command])
                    }

                    VStack(spacing: 13) {
                        Text("What's your focus?")
                            .font(.system(size: 28, weight: .semibold))
                        focusSetup
                    }

                    timerCard
                        .frame(minWidth: 500, maxWidth: 690)
                }
                .frame(maxWidth: .infinity)
                .padding(28)
            }

            Divider().overlay(NonnaTheme.line)

            DayTimelineView()
                .frame(minWidth: 470, idealWidth: 540, maxWidth: 620)
        }
        .sheet(isPresented: $showingNewTask) {
            NewTaskView()
                .environment(model)
        }
        .sheet(isPresented: $showsInspector) {
            sessionInspector
        }
        .onChange(of: model.intention) { _, _ in model.persistDraft() }
        .onChange(of: model.note) { _, _ in model.persistDraft() }
    }

    private var focusSetup: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(model.tasks) { task in
                        Button {
                            model.selectedTaskID = task.id
                            model.persistDraft()
                        } label: {
                            Label(task.name, systemImage: model.selectedTaskID == task.id ? "checkmark.circle.fill" : "circle.fill")
                        }
                    }
                    Divider()
                    Button("New task…") { showingNewTask = true }
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(NonnaTheme.taskColor(for: model.selectedTask?.colorHex ?? "BDA56F"))
                            .frame(width: 7, height: 7)
                        Text(model.selectedTask?.name ?? "Choose a task")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(NonnaTheme.raisedPaper)
                    .clipShape(Capsule())
                    .overlay { Capsule().stroke(NonnaTheme.line, lineWidth: 0.8) }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button { showingNewTask = true } label: {
                    Image(systemName: "plus")
                        .frame(width: 32, height: 32)
                        .background(NonnaTheme.raisedPaper)
                        .clipShape(Circle())
                        .overlay { Circle().stroke(NonnaTheme.line, lineWidth: 0.8) }
                }
                .buttonStyle(.plain)
            }

            ZStack(alignment: .leading) {
                if model.intention.isEmpty {
                    Text("Intention")
                        .foregroundStyle(NonnaTheme.secondaryInk.opacity(0.62))
                        .padding(.horizontal, 14)
                }
                TextField("", text: Bindable(model).intention)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(.horizontal, 14)
                    .disabled(model.phase != .focus)
            }
            .frame(maxWidth: 440)
            .frame(height: 42)
            .background(NonnaTheme.raisedPaper.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 9).stroke(NonnaTheme.line, lineWidth: 0.8) }
        }
    }

    private var sessionInspector: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                SectionHeading(eyebrow: "Local workspace", title: "Session")
                Spacer()
                Button("Done") { showsInspector = false }
                    .buttonStyle(NonnaButtonStyle(prominent: false))
            }
            FocusCanvasView()
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(width: 560)
        .frame(minHeight: 540)
        .background(NonnaTheme.cream)
        .environment(model)
    }

    private var todayProgress: some View {
        let todaySeconds = model.todayRecordedFocusSeconds
        let goal = max(1, model.settings.dailyGoalMinutes * 60)
        return VStack(alignment: .trailing, spacing: 5) {
            Text("TODAY")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(NonnaTheme.secondaryInk)
            Text("\(todaySeconds.focusDurationString) / \((goal).focusDurationString)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
            ProgressView(value: min(1, Double(todaySeconds) / Double(goal)))
                .tint(NonnaTheme.terracotta)
                .frame(width: 130)
        }
        .padding(.trailing, 4)
    }

    private var timerCard: some View {
        NonnaCard(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(TimerPhase.allCases, id: \.self) { phase in
                        Button {
                            withAnimation(reduceMotion ? nil : NonnaMotion.selection) {
                                model.selectPhase(phase)
                            }
                        } label: {
                            ZStack {
                                if model.phase == phase {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(NonnaTheme.raisedPaper)
                                        .matchedGeometryEffect(id: "phase-surface", in: phaseSelection)
                                        .padding(4)
                                }
                                Text(phase == .focus ? "Focus" : phase == .shortBreak ? "Short rest" : "Long rest")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .tracking(0.5)
                                    .foregroundStyle(model.phase == phase ? NonnaTheme.ink : NonnaTheme.secondaryInk)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .overlay(alignment: .bottom) {
                                if model.phase == phase {
                                    Capsule()
                                        .fill(NonnaTheme.accent(for: phase))
                                        .frame(width: 28, height: 1.5)
                                        .matchedGeometryEffect(id: "phase-indicator", in: phaseSelection)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(NonnaTheme.sunken.opacity(0.72))
                .overlay(alignment: .bottom) { Rectangle().fill(NonnaTheme.line).frame(height: 0.8) }

                VStack(spacing: 22) {
                    ZStack {
                        if model.isBreathing {
                            BreathingRitualView(
                                stage: model.breathingStage,
                                cycle: model.breathingCycle,
                                accent: accent
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                        } else {
                            TimelineView(.animation(minimumInterval: dialFrameInterval, paused: !shouldAnimateDial)) { context in
                                PremiumTimerDial(
                                    progress: smoothDialFraction(at: context.date),
                                    accent: accent,
                                    isActive: model.status != .idle,
                                    isPaused: model.status == .paused,
                                    reduceMotion: reduceMotion
                                )
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        }
                    }
                    .frame(width: 300, height: 300)
                    .animation(reduceMotion ? nil : NonnaMotion.settle, value: model.isBreathing)

                    if !model.isBreathing {
                        VStack(spacing: 7) {
                            Text(timerStateLabel)
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .tracking(2)
                                .foregroundStyle(accent)
                                .padding(.horizontal, isAlerting ? 9 : 0)
                                .frame(height: isAlerting ? 20 : nil)
                                .background {
                                    if isAlerting {
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .fill(NonnaTheme.alert.opacity(0.13))
                                    }
                                }
                                .overlay {
                                    if isAlerting {
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .stroke(NonnaTheme.alert.opacity(0.75), lineWidth: 0.8)
                                    }
                                }
                                .alertFlash(isFlashing)
                            RollingClockText(
                                text: (model.isOvertime ? "+" : "") + model.displaySeconds.clockString,
                                countsDown: !model.isOvertime,
                                travel: 22,
                                animation: reduceMotion ? nil : NonnaMotion.numeric
                            )
                                .font(.system(size: 56, weight: .medium))
                                .tracking(-2)
                                .monospacedDigit()
                                .foregroundStyle(isAlerting ? NonnaTheme.alert : NonnaTheme.ink)
                                // The glow only exists in overtime; a clear shadow still costs a blur pass.
                                .shadow(color: isAlerting ? NonnaTheme.alert.opacity(0.45) : .clear, radius: isAlerting ? 14 : 0)
                                .alertFlash(isFlashing)
                            Text(timerRangeText)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(NonnaTheme.secondaryInk)
                                .padding(.horizontal, 10)
                                .frame(height: 24)
                                .background(NonnaTheme.raisedPaper)
                                .clipShape(Capsule())
                                .overlay { Capsule().stroke(NonnaTheme.line, lineWidth: 0.8) }
                        }
                    }

                    timerControls
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 24)
            }
            .frame(maxWidth: .infinity, minHeight: 600)
        }
    }

    private var timerStateLabel: String {
        if model.awaitingNextPhase != nil { return "BREAK COMPLETE" }
        if model.status == .overtime { return model.phase == .focus ? "FOCUS OVERTIME" : "BREAK OVERTIME" }
        return model.phase.compactTitle
    }

    private var timerRangeText: String {
        let now = Date()
        let interval = model.activityIntervals.last
        let start = interval?.startedAt ?? model.activeTimerStartedAt ?? now
        let end: Date
        if model.status == .idle {
            end = now.addingTimeInterval(TimeInterval(model.plannedSeconds))
        } else if model.status == .paused {
            end = interval?.endedAt ?? now
        } else if model.isOvertime {
            end = now
        } else {
            end = now.addingTimeInterval(TimeInterval(model.remainingSeconds))
        }
        return "\(start.formatted(date: .omitted, time: .shortened)) → \(end.formatted(date: .omitted, time: .shortened))"
    }

    /// How often the dial redraws while it runs. The progress ring (r ≈ 123 pt) is the
    /// fastest-moving edge; redrawing each time it travels a quarter point keeps the sweep
    /// visually continuous. A 25-minute block needs about 2 frames a second, a 5-minute
    /// break about 10, and very short blocks are capped at 30.
    private var dialFrameInterval: Double {
        let pointsPerSecond = 2 * Double.pi * 123 / Double(max(1, model.plannedSeconds))
        return min(1, max(1.0 / 30.0, 0.25 / pointsPerSecond))
    }

    private var shouldAnimateDial: Bool {
        !reduceMotion && !model.isBreathing && (model.status == .running || model.status == .overtime)
    }

    /// Exact progress at the frame's date, read from the session's active intervals, so
    /// the hand sweeps continuously without a per-second state anchor (which cost a second
    /// full redraw of this view every tick).
    private func smoothDialFraction(at date: Date) -> Double {
        if model.status == .idle {
            return min(1, Double(model.plannedSeconds) / 3_600)
        }
        if model.isOvertime { return 1 }
        guard model.plannedSeconds > 0 else { return 0 }

        let elapsed = model.activityIntervals.reduce(0.0) { $0 + $1.duration(through: date) }
        return min(1, max(0, elapsed / Double(model.plannedSeconds)))
    }

    private var timerControlState: String {
        if model.isBreathing { return "breathing" }
        if model.canAdvanceCycle { return "advance-\(model.phase.rawValue)" }
        if model.status == .idle { return "idle-\(model.phase.rawValue)-\(model.hasOpenRun)" }
        return "\(model.status.rawValue)-\(model.phase.rawValue)"
    }

    /// Stops for now and keeps everything tracked. Shown in every active state.
    private var endSessionButton: some View {
        Button {
            model.endSession()
        } label: {
            Label("End session", systemImage: "stop.fill")
        }
        .buttonStyle(NonnaButtonStyle(prominent: false))
        .help("Save what you've tracked and stop, without starting anything new (⌘.)")
    }

    @ViewBuilder
    private var timerControls: some View {
        HStack(spacing: 10) {
            if model.breathingRemaining > 0 {
                Button("Skip breaths") { model.skipBreathing() }
                    .buttonStyle(NonnaButtonStyle(color: accent))
                Button("Cancel") { model.cancelBreathing() }
                    .buttonStyle(NonnaButtonStyle(prominent: false))
            } else if model.canAdvanceCycle {
                Button {
                    model.advanceToNextPhase()
                } label: {
                    Label(model.nextActionTitle, systemImage: "arrow.right")
                }
                .buttonStyle(NonnaButtonStyle(color: model.cycleNextPhase.map { NonnaTheme.accent(for: $0) } ?? accent))

                if model.phase == .focus, model.isOvertime {
                    Button {
                        model.skipBreakAndStartFocus()
                    } label: {
                        Label("Skip break", systemImage: "forward.end.fill")
                    }
                    .buttonStyle(NonnaButtonStyle(prominent: false))
                }

                endSessionButton

                if model.status != .idle {
                    Menu {
                        Button(model.status == .paused ? "Resume" : "Pause") { model.togglePause() }
                        Divider()
                        Button("Abandon timer…", role: .destructive) { confirmsAbandon = true }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 30, height: 42)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            } else if model.status == .idle {
                Button {
                    model.start()
                } label: {
                    Label(model.phase == .focus ? "Begin focus" : "Begin rest", systemImage: "play.fill")
                }
                .buttonStyle(NonnaButtonStyle(color: accent))

                if model.hasOpenRun { endSessionButton }
            } else {
                Button {
                    model.togglePause()
                } label: {
                    Label(model.status == .paused ? "Resume" : "Pause", systemImage: model.status == .paused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(NonnaButtonStyle(color: accent))

                if model.phase != .focus {
                    Button {
                        model.skipBreakAndStartFocus()
                    } label: {
                        Label("Skip break", systemImage: "forward.end.fill")
                    }
                    .buttonStyle(NonnaButtonStyle(prominent: false))
                }

                endSessionButton

                Menu {
                    if model.phase == .focus {
                        Button("Finish and take a break") {
                            model.skipToNextPhase()
                        }
                        Divider()
                    }
                    Button("Abandon timer…", role: .destructive) { confirmsAbandon = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 38, height: 42)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .confirmationDialog("Abandon this timer?", isPresented: $confirmsAbandon) {
            Button("Abandon and discard", role: .destructive) { model.abandon() }
            Button("End session and keep it") { model.endSession() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Abandoning throws away the time tracked in this block. End session keeps it.")
        }
        .id(timerControlState)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
        .animation(reduceMotion ? nil : NonnaMotion.selection, value: timerControlState)
    }

    private var intentionCard: some View {
        NonnaCard(padding: 18) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("SESSION")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.8)
                        .foregroundStyle(NonnaTheme.terracotta)
                    Spacer()
                    Label("LOCAL", systemImage: "lock.fill")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(NonnaTheme.sage)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("TASK")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(NonnaTheme.secondaryInk)

                    HStack(spacing: 9) {
                        Menu {
                            ForEach(model.tasks) { task in
                                Button {
                                    model.selectedTaskID = task.id
                                    model.persistDraft()
                                } label: {
                                    Label(task.name, systemImage: model.selectedTaskID == task.id ? "checkmark.circle.fill" : "circle.fill")
                                }
                            }
                            Divider()
                            Button("New task…") { showingNewTask = true }
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(NonnaTheme.taskColor(for: model.selectedTask?.colorHex ?? "8D8379"))
                                    .frame(width: 9, height: 9)
                                Text(model.selectedTask?.name ?? "Choose a task")
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(NonnaTheme.ink)
                            .padding(.horizontal, 11)
                            .frame(height: 34)
                            .background(NonnaTheme.raisedPaper)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: 8).stroke(NonnaTheme.line, lineWidth: 0.8) }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()

                        Button {
                            showingNewTask = true
                        } label: {
                            Image(systemName: "plus")
                                .frame(width: 34, height: 34)
                                .background(NonnaTheme.raisedPaper)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay { RoundedRectangle(cornerRadius: 8).stroke(NonnaTheme.line, lineWidth: 0.8) }
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("INTENTION")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(NonnaTheme.secondaryInk)
                    ZStack(alignment: .leading) {
                        if model.intention.isEmpty {
                            Text("e.g. Draft the opening section")
                                .foregroundStyle(NonnaTheme.secondaryInk.opacity(0.58))
                                .allowsHitTesting(false)
                        }
                        TextField("", text: Bindable(model).intention, axis: .vertical)
                            .foregroundStyle(NonnaTheme.ink)
                            .textFieldStyle(.plain)
                            .lineLimit(1...3)
                            .disabled(model.phase != .focus)
                    }
                    .font(.system(size: 18, weight: .medium))
                    Rectangle()
                        .fill(NonnaTheme.line)
                        .frame(height: 1)
                }

                FocusCanvasView()

                Spacer(minLength: 0)

                HStack(spacing: 9) {
                    Image(systemName: "wind")
                        .foregroundStyle(accent)
                    Text(model.settings.breathingEnabled ? "Begin with three slow, guided breaths." : "Opening breath ritual is disabled.")
                        .font(.system(size: 10))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
            }
            .frame(minHeight: 529, alignment: .top)
        }
    }
}

private struct PremiumTimerDial: View {
    let progress: Double
    let accent: Color
    let isActive: Bool
    let isPaused: Bool
    let reduceMotion: Bool

    private var clampedProgress: Double { min(1, max(0, progress)) }

    var body: some View {
        ZStack {
            // The face and bezel never change, so they are separate views with no inputs:
            // SwiftUI reuses them as-is and only the moving layers are rebuilt each frame.
            PremiumDialFace()

            PieSlice(progress: clampedProgress)
                .fill(
                    AngularGradient(
                        colors: [accent.opacity(0.18), accent.opacity(0.5), accent.opacity(0.28)],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    )
                )
                .padding(28)
                .opacity(isActive ? 1 : 0.72)

            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(
                    LinearGradient(
                        colors: [accent.opacity(0.36), accent.opacity(0.92)],
                        startPoint: .top,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(27)
                .shadow(color: accent.opacity(isActive ? 0.28 : 0.08), radius: 7)

            PremiumDialBezel()

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.42), accent, NonnaTheme.ink.opacity(0.92)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: 3, height: 101)
                .offset(y: -50.5)
                .rotationEffect(.degrees(clampedProgress * 360))
                .shadow(color: accent.opacity(isActive && !isPaused ? 0.42 : 0.18), radius: 5)

            Capsule()
                .fill(accent.opacity(0.38))
                .frame(width: 2, height: 20)
                .offset(y: 10)
                .rotationEffect(.degrees(clampedProgress * 360))

            Circle()
                .fill(NonnaTheme.sunken)
                .frame(width: 25, height: 25)
                .overlay {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [NonnaTheme.ink, accent.opacity(0.82)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3.5
                        )
                }
                .overlay {
                    Circle()
                        .fill(NonnaTheme.ink)
                        .frame(width: 5, height: 5)
                }
                .shadow(color: accent.opacity(0.28), radius: reduceMotion ? 3 : 7)
        }
        .drawingGroup(opaque: false, colorMode: .linear)
    }
}

private struct PremiumDialFace: View {
    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        NonnaTheme.raisedPaper.opacity(0.98),
                        NonnaTheme.raisedPaper.opacity(0.9),
                        NonnaTheme.sunken.opacity(0.96)
                    ],
                    center: .center,
                    startRadius: 18,
                    endRadius: 142
                )
            )
            .padding(27)
            .shadow(color: .black.opacity(0.42), radius: 20, y: 10)
    }
}

private struct PremiumDialBezel: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.12), NonnaTheme.strongLine.opacity(0.9), .black.opacity(0.22)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .padding(27)

            DialTicks(radius: 143, major: false, majorSize: CGSize(width: 1.25, height: 9), minorSize: CGSize(width: 0.7, height: 4))
                .fill(NonnaTheme.line.opacity(0.9))
            DialTicks(radius: 143, major: true, majorSize: CGSize(width: 1.25, height: 9), minorSize: CGSize(width: 0.7, height: 4))
                .fill(NonnaTheme.secondaryInk.opacity(0.62))
        }
    }
}

private struct PieSlice: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + min(1, max(0, progress)) * 360),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

private struct BreathingRitualView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let stage: BreathingStage
    let cycle: Int
    let accent: Color
    @State private var expanded = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(NonnaTheme.line, lineWidth: 1)
            Circle()
                .fill(accent.opacity(expanded ? 0.1 : 0.035))
                .blur(radius: 18)
                .scaleEffect(expanded ? 0.98 : 0.58)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accent.opacity(0.2), accent.opacity(0.055), accent.opacity(0.01)],
                        center: .center,
                        startRadius: 12,
                        endRadius: 120
                    )
                )
                .scaleEffect(expanded ? 0.86 : 0.56)
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [accent.opacity(0.64), accent.opacity(0.13)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
                .scaleEffect(expanded ? 0.92 : 0.62)
                .shadow(color: accent.opacity(expanded ? 0.28 : 0.1), radius: 12)

            Circle()
                .stroke(accent.opacity(0.18), lineWidth: 0.8)
                .scaleEffect(expanded ? 0.76 : 0.5)

            VStack(spacing: 10) {
                Text("BREATH \(cycle) OF 3")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(accent)
                Text(stage.prompt)
                    .font(.system(size: 25, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(NonnaTheme.ink)
                    .contentTransition(.interpolate)
                    .animation(reduceMotion ? nil : NonnaMotion.quick, value: stage)
            }
            .padding(.horizontal, 44)
        }
        .onAppear {
            expanded = stage == .exhale
            DispatchQueue.main.async { animate(to: stage) }
        }
        .onChange(of: stage) { _, nextStage in
            animate(to: nextStage)
        }
    }

    private func animate(to nextStage: BreathingStage) {
        let duration = nextStage == .inhale
            ? Double(AppModel.breathingInhaleSeconds)
            : Double(AppModel.breathingExhaleSeconds)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: duration)) {
            expanded = nextStage == .inhale
        }
    }
}

struct NewTaskView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color = "BDA56F"

    private let colors = ["BDA56F", "738B80", "A9A4B5", "788897", "8F7581", "6F858F", "837765"]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionHeading(eyebrow: "Tasks", title: "New task")
            TextField("Task name", text: $name)
                .font(.system(size: 18, weight: .semibold, design: .default))
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 12) {
                ForEach(colors, id: \.self) { hex in
                    Button {
                        color = hex
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 28, height: 28)
                            .overlay {
                                if color == hex {
                                    Circle().stroke(.white, lineWidth: 3).padding(3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(NonnaButtonStyle(prominent: false))
                Button("Create task") {
                    model.addTask(name: name, colorHex: color)
                    dismiss()
                }
                .buttonStyle(NonnaButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(28)
        .frame(width: 490)
        .background(NonnaTheme.cream)
    }
}

struct ReflectionView: View {
    @Environment(AppModel.self) private var model
    @State private var rating = 3
    @State private var note: String
    let session: FocusSession

    init(session: FocusSession) {
        self.session = session
        _note = State(initialValue: session.note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionHeading(
                eyebrow: "Session complete",
                title: "Reflection"
            )

            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        rating = value
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: rating >= value ? "circle.inset.filled" : "circle")
                                .font(.system(size: 23))
                            Text(["Scattered", "Restless", "Steady", "Focused", "Flow"][value - 1])
                                .font(.system(size: 9, design: .default))
                        }
                        .foregroundStyle(rating >= value ? NonnaTheme.terracotta : NonnaTheme.secondaryInk)
                    }
                    .buttonStyle(.plain)
                }
            }

            TextEditor(text: $note)
                .font(.system(size: 13, design: .default))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(NonnaTheme.paper)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).stroke(NonnaTheme.line) }
                .frame(height: 130)

            HStack {
                Label(session.focusedSeconds.focusDurationString, systemImage: "timer")
                    .font(.system(size: 12, weight: .semibold, design: .default))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                Spacer()
                Button("Save reflection") {
                    model.saveReflection(rating: rating, note: note)
                }
                .buttonStyle(NonnaButtonStyle())
            }
        }
        .padding(30)
        .frame(width: 560)
        .background(NonnaTheme.cream)
    }
}
