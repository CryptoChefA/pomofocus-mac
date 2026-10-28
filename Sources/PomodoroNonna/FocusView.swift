import SwiftUI

struct FocusView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingNewTask = false
    @AppStorage("pomofocus.timelineCollapsed") private var timelineCollapsed = false
    /// Simple tasks folds the planner away while a focus block runs; this remembers that it
    /// was the app, not you, so it comes back when the block ends.
    @AppStorage("pomofocus.timelineAutoCollapsed") private var timelineAutoCollapsed = false
    @Environment(\.compactLayout) private var compact
    /// On a narrow window the timeline slides out over the timer instead of beside it.
    @State private var timelineDrawerOpen = false
    @State private var confirmsAbandon = false
    @Namespace private var phaseSelection
    /// Height of the timer column, so the dial can shrink and keep the controls in view.
    @State private var columnHeight: CGFloat = 860

    /// Up to 300pt on tall windows, down to 140pt on short ones, so the controls stay in view.
    private var dialSize: CGFloat { min(300, max(140, columnHeight - 600)) }

    private var accent: Color { isAlerting ? NonnaTheme.alert : NonnaTheme.accent(for: model.phase) }

    /// Past the planned time, with the alert switched on.
    private var isAlerting: Bool { model.isOvertime && model.settings.overtimeAlert }
    /// Only flash while the clock is actually running over. Paused overtime holds steady red.
    private var isFlashing: Bool { isAlerting && model.status == .overtime }

    @AppStorage("displayName") private var displayName = ""
    private var isBlackIce: Bool { ThemeManager.shared.themeID == ThemeChoice.blackIce.rawValue }
    private var isBespoke: Bool { ThemeManager.shared.themeID == ThemeChoice.bespoke.rawValue }

    /// "Good morning, Layla" once a name is set in Settings.
    private var greeting: String {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Pomofocus" }
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        return "\(part), \(name)"
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    HStack {
                        if isBespoke, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            // Bespoke greets you in a quick handwritten note.
                            Text(greeting)
                                .font(.custom("Bradley Hand", size: 18).weight(.bold))
                                .foregroundStyle(NonnaTheme.ink.opacity(0.88))
                        } else if isBlackIce {
                            // Black Ice signs its name in an icy script, glowing like frost.
                            IcyGreeting(text: greeting)
                        } else {
                            Text(greeting)
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundStyle(NonnaTheme.terracotta)
                        }
                        Spacer()
                        Button {
                            CinematicController.shared.enter(model: model)
                        } label: {
                            Label("Cinema", systemImage: "tv")
                        }
                        .buttonStyle(NonnaButtonStyle(prominent: false))
                        .help("Show the timer full screen (⇧⌘F)")
                    }

                    if let change = model.planChange {
                        PlanChangeBanner(change: change) {
                            withAnimation(reduceMotion ? nil : NonnaMotion.quick) { model.planChange = nil }
                        }
                        .frame(maxWidth: 690)
                    }

                    if let pausedAt = model.awayPausedAt {
                        AwayBanner(pausedAt: pausedAt)
                            .frame(maxWidth: 690)
                    }

                    if model.status == .idle {
                        WrapUpBanner()
                            .frame(maxWidth: 690)
                    }

                    VStack(spacing: 13) {
                        Text(isFocusing && model.settings.simpleTasks ? "Just this, for now" : "What's your focus?")
                            .font(.system(size: 28, weight: .semibold))
                        focusSetup
                    }

                    timerCard
                        .frame(minWidth: 380, maxWidth: 690)
                }
                .frame(maxWidth: .infinity)
                .padding(28)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { columnHeight = $0 }

            Divider().overlay(NonnaTheme.line)

            if compact {
                TimelineRail(onExpand: toggleDrawer)
            } else {
                // The timeline stays built and slides by width, so opening it is one smooth
                // motion instead of building the whole day mid-animation.
                HStack(spacing: 0) {
                    if timelineCollapsed {
                        TimelineRail(onExpand: toggleTimeline)
                            .transition(.opacity)
                    }
                    DayTimelineView(onCollapse: toggleTimeline)
                        .frame(width: 540)
                        .frame(width: timelineCollapsed ? 0 : 540, alignment: .leading)
                        .clipped()
                        .allowsHitTesting(!timelineCollapsed)
                        .accessibilityHidden(timelineCollapsed)
                }
            }
        }
        .clipped()
        .overlay(alignment: .trailing) {
            if compact && timelineDrawerOpen {
                ZStack(alignment: .trailing) {
                    // The shade and the drawer run up under the title bar too, so no light
                    // band is left across the top.
                    Color.black.opacity(NonnaTheme.isDark ? 0.4 : 0.15)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture(perform: toggleDrawer)
                        .transition(.opacity)
                    DayTimelineView(onCollapse: toggleDrawer)
                        .frame(width: 460)
                        .background(NonnaTheme.cream.ignoresSafeArea())
                        .overlay(alignment: .leading) { Rectangle().fill(NonnaTheme.line).frame(width: 1) }
                        .shadow(color: .black.opacity(0.35), radius: 30, x: -8)
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .onAppear(perform: foldPlannerWhileFocusing)
        .onChange(of: model.status) { _, _ in foldPlannerWhileFocusing() }
        .onChange(of: compact) { _, isCompact in
            if !isCompact { timelineDrawerOpen = false }
        }
        .sheet(isPresented: $showingNewTask) {
            NewTaskView()
                .environment(model)
        }
        .onChange(of: model.intention) { _, _ in model.persistDraft() }
        .onChange(of: model.note) { _, _ in model.persistDraft() }
    }

    private var isFocusing: Bool { model.status != .idle && model.phase == .focus }

    /// With simple tasks, the day planner steps aside during a focus block so starting
    /// doesn't open another thing to arrange. Opening it by hand mid-block is left alone.
    private func foldPlannerWhileFocusing() {
        guard !compact else { return }
        if isFocusing, model.settings.simpleTasks {
            if !timelineCollapsed, !timelineAutoCollapsed {
                timelineAutoCollapsed = true
                toggleTimeline()
            }
        } else if model.status == .idle, timelineAutoCollapsed {
            timelineAutoCollapsed = false
            if timelineCollapsed { toggleTimeline() }
        }
    }

    private func toggleDrawer() {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.06)) {
            timelineDrawerOpen.toggle()
        }
    }

    private func toggleTimeline() {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.08)) {
            timelineCollapsed.toggle()
        }
    }

    private var focusSetup: some View {
        FocusPicker(showingNewList: $showingNewTask)
    }

    private var todayProgress: some View {
        let todaySeconds = model.todayRecordedFocusSeconds
        let goal = max(1, model.settings.dailyGoalMinutes * 60)
        return VStack(alignment: .trailing, spacing: 5) {
            Text("Today")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(NonnaTheme.secondaryInk)
            Text("\(todaySeconds.focusDurationString) / \((goal).focusDurationString)")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
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
                                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                                    .foregroundStyle(model.phase == phase ? NonnaTheme.ink : NonnaTheme.secondaryInk)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .contentShape(Rectangle())
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
                            .overlay {
                                // In Black Ice a paused block frosts over.
                                if isBlackIce, model.status == .paused {
                                    FrostOverlay()
                                        .padding(40)
                                        .transition(.opacity)
                                }
                            }
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: model.status == .paused)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        }
                    }
                    .frame(width: 300, height: 300)
                    .scaleEffect(dialSize / 300)
                    .frame(width: dialSize, height: dialSize)
                    .animation(reduceMotion ? nil : NonnaMotion.settle, value: model.isBreathing)

                    if !model.isBreathing {
                        VStack(spacing: 7) {
                            Text(timerStateLabel)
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
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
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
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
            .frame(maxWidth: .infinity, minHeight: dialSize + 300)
        }
    }

    private var timerStateLabel: String {
        if model.awaitingNextPhase != nil { return "Break complete" }
        if model.status == .overtime { return model.phase == .focus ? "Focus overtime" : "Break overtime" }
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
        return (start..<max(end, start)).formatted(date: .omitted, time: .shortened)
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

    /// Stops for now and keeps everything tracked. Shown only while something is running or paused.
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
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
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
                .menuIndicator(.hidden)
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

            if ThemeManager.shared.themeID == ThemeChoice.piano.rawValue {
                RomanDialMarkings()
            }

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
        // Shadow outside the flattened layer, so it isn't clipped into a square.
        .background {
            Circle()
                .fill(NonnaTheme.cream)
                .padding(27)
                .shadow(color: .black.opacity(NonnaTheme.colorScheme == .dark ? 0.42 : 0.14), radius: 20, y: 10)
        }
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

/// The breathing ritual: six petals that bloom outward and turn as you breathe in, then
/// fold back as you breathe out, in the theme's colours. Six shapes and two animated
/// values, so it costs next to nothing to draw.
private struct BreathingRitualView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    let stage: BreathingStage
    let cycle: Int
    let accent: Color
    @State private var expanded = false

    private static let petals = 6

    private var colors: [Color] {
        // Only the theme's accent and its lighter shade, so the flower always matches the look.
        let palette = [accent, NonnaTheme.darkTerracotta]
        return (0..<Self.petals).map { palette[$0 % palette.count] }
    }

    var body: some View {
        VStack(spacing: 22) {
            GeometryReader { proxy in
                let size = min(proxy.size.width, proxy.size.height)
                let petal = size * 0.5
                ZStack {
                    ForEach(0..<Self.petals, id: \.self) { index in
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [colors[index].opacity(0.95), colors[index].opacity(0.55)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: petal, height: petal)
                            .offset(y: expanded ? -petal * 0.5 : 0)
                            .rotationEffect(.degrees(Double(index) / Double(Self.petals) * 360))
                            .opacity(colorScheme == .dark ? 0.6 : 0.5)
                            .blendMode(colorScheme == .dark ? .screen : .multiply)
                    }
                }
                .compositingGroup()
                .scaleEffect(expanded ? 1 : 0.38)
                .rotationEffect(.degrees(expanded ? 0 : -90))
                .shadow(color: accent.opacity(expanded ? 0.3 : 0.12), radius: expanded ? 24 : 10)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(height: 230)

            VStack(spacing: 8) {
                Text(stage.prompt)
                    .font(.system(size: 22, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(NonnaTheme.ink)
                    .contentTransition(.interpolate)
                    .animation(reduceMotion ? nil : NonnaMotion.quick, value: stage)
                Text("Breath \(cycle) of 3")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
        }
        .onAppear {
            expanded = stage == .exhale
            DispatchQueue.main.async { animate(to: stage) }
        }
        .onChange(of: stage) { _, nextStage in
            animate(to: nextStage)
        }
        .accessibilityElement(children: .combine)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionHeading(title: "New list")
            TextField("List name, like a course or project", text: $name)
                .font(.system(size: 18, weight: .semibold, design: .default))
                .textFieldStyle(.roundedBorder)
            ListColorPicker(hex: $color, size: 28)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(NonnaButtonStyle(prominent: false))
                Button("Create list") {
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var picked: Int?
    let session: FocusSession

    private static let feelings = ["Scattered", "Restless", "Steady", "Focused", "Flow"]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeading(title: model.settings.rateFocus == .everyBlock ? "How did that block feel?" : "How did this session feel?")
                Label(summary, systemImage: "timer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }

            // One click rates it and closes; no writing at the end of a sitting.
            HStack(spacing: 10) {
                ForEach(Self.feelings.indices, id: \.self) { index in
                    let value = index + 1
                    let isPicked = picked == value
                    Button { choose(value) } label: {
                        VStack(spacing: 8) {
                            Image(systemName: isPicked ? "circle.inset.filled" : "circle")
                                .font(.system(size: 22))
                            Text(Self.feelings[index])
                                .font(.system(size: 12, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(isPicked ? NonnaTheme.terracotta : NonnaTheme.secondaryInk)
                        .background(isPicked ? NonnaTheme.terracotta.opacity(0.12) : NonnaTheme.paper,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(isPicked ? NonnaTheme.terracotta.opacity(0.5) : NonnaTheme.line, lineWidth: 1)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(KeyEquivalent(Character(String(value))), modifiers: [])
                    .help("\(Self.feelings[index]) (\(value))")
                }
            }

            HStack {
                Spacer()
                Button("Skip") { model.skipReflection() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(30)
        .frame(width: 560)
        .background(NonnaTheme.cream)
    }

    private func choose(_ value: Int) {
        guard picked == nil else { return }
        withAnimation(reduceMotion ? nil : NonnaMotion.selection) { picked = value }
        // A moment to see the choice land before the sheet goes.
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 350))
            model.saveReflection(rating: value)
        }
    }

    /// One block's time, or the whole sitting's when rating a session.
    private var summary: String {
        let ids = model.reflectionRunIDs
        guard ids.count > 1 else { return session.focusedSeconds.focusDurationString }
        let rated = model.sessions.filter { ids.contains($0.id) }
        let total = rated.reduce(0) { $0 + $1.focusedSeconds }
        let blocks = FocusSession.mergedBlocks(rated).count
        guard blocks > 1 else { return total.focusDurationString }
        return "\(blocks) blocks, \(total.focusDurationString)"
    }
}

/// The day timeline, tucked away: a slim strip on the right edge with today's total and
/// a live dot while a timer runs. Click anywhere on it to pull the timeline back out.
private struct TimelineRail: View {
    @Environment(AppModel.self) private var model
    let onExpand: () -> Void
    @State private var hovering = false

    private var todayText: String {
        let live = model.phase == .focus && model.status != .idle ? model.elapsedSeconds : 0
        return (model.todayRecordedFocusSeconds + live).focusDurationString
    }

    var body: some View {
        Button(action: onExpand) {
            VStack(spacing: 22) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(hovering ? NonnaTheme.strongLine : NonnaTheme.raisedPaper)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }

                if model.status != .idle {
                    Circle()
                        .fill(NonnaTheme.accent(for: model.phase))
                        .frame(width: 7, height: 7)
                        .shadow(color: NonnaTheme.accent(for: model.phase).opacity(0.7), radius: 5)
                        .help("A timer is running")
                }

                Text("Timeline")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .fixedSize()
                    .rotationEffect(.degrees(90))
                    .frame(width: 14, height: 80)

                Text(todayText)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(NonnaTheme.terracotta)
                    .fixedSize()
                    .rotationEffect(.degrees(90))
                    .frame(width: 14, height: 70)

                Spacer(minLength: 0)
            }
            .padding(.top, 18)
            .frame(width: 52)
            .frame(maxHeight: .infinity)
            .background(NonnaTheme.sunken.opacity(hovering ? 0.95 : 0.72).ignoresSafeArea())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(NonnaMotion.quick, value: hovering)
        .keyboardShortcut("t", modifiers: [.command, .option])
        .help("Show the timeline (⌥⌘T)")
        .accessibilityLabel("Show the timeline")
    }
}

/// Shown after the away guard paused a timer that was running over.
private struct AwayBanner: View {
    @Environment(AppModel.self) private var model
    let pausedAt: Date

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 20))
                .foregroundStyle(NonnaTheme.sage)
            VStack(alignment: .leading, spacing: 2) {
                Text("Paused at \(pausedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 14, weight: .semibold))
                Text("Looks like you stepped away, so the time after that wasn’t counted.")
                    .font(.system(size: 12))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            Spacer()
            Button("I was here") { model.countAwayTime() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(NonnaTheme.secondaryInk)
                .help("Count the time since then after all")
            Button("End session") { model.endSession() }
                .buttonStyle(NonnaButtonStyle(prominent: false))
            Button("Resume") { model.togglePause() }
                .buttonStyle(NonnaButtonStyle())
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(NonnaTheme.sage.opacity(0.1))
                .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NonnaTheme.sage.opacity(0.45), lineWidth: 0.8) }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Piano's dial furniture: a railway minute track and twelve black Roman numerals set
/// radially, the way a classic dress watch does it. Drawn once; it never moves.
private struct RomanDialMarkings: View {
    private static let numerals = ["XII", "I", "II", "III", "IIII", "V", "VI", "VII", "VIII", "IX", "X", "XI"]

    var body: some View {
        ZStack {
            // Railway track: two fine rings with a short bar for every minute.
            Circle().stroke(NonnaTheme.ink.opacity(0.85), lineWidth: 0.7).frame(width: 236, height: 236)
            Circle().stroke(NonnaTheme.ink.opacity(0.85), lineWidth: 0.7).frame(width: 226, height: 226)
            ForEach(0..<60, id: \.self) { minute in
                Rectangle()
                    .fill(NonnaTheme.ink.opacity(0.8))
                    .frame(width: minute % 5 == 0 ? 1.2 : 0.6, height: 5)
                    .offset(y: -115.5)
                    .rotationEffect(.degrees(Double(minute) * 6))
            }
            // The name, engraved under the twelve.
            Text("POMOFOCUS")
                .font(.system(size: 10, weight: .semibold, design: .serif))
                .tracking(1.8)
                .foregroundStyle(NonnaTheme.ink)
                .offset(y: -52)
            ForEach(0..<12, id: \.self) { hour in
                Text(Self.numerals[hour])
                    .font(.system(size: 19, weight: .semibold, design: .serif))
                    .tracking(-0.5)
                    .foregroundStyle(NonnaTheme.ink)
                    .scaleEffect(x: 0.82, y: 1.25)
                    .offset(y: -94)
                    .rotationEffect(.degrees(Double(hour) * 30))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
