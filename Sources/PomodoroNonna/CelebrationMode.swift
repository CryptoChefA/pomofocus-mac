import AppKit
import SwiftUI

// MARK: - Summary

/// Everything the celebration shows about a sitting, captured when End session is pressed.
struct CelebrationSummary: Sendable {
    struct Block: Sendable, Identifiable {
        let id: UUID
        let focusedSeconds: Int
        let plannedSeconds: Int
        let completed: Bool
        let colorHex: String
    }

    let blocks: [Block]
    let intentions: [String]
    let startedAt: Date
    let endedAt: Date
    let breakCount: Int
    let breakSeconds: Int
    let pausedSeconds: Int
    let overtimeSeconds: Int
    let todaySeconds: Int
    /// "TODAY", or "SINCE YESTERDAY" when the sitting crossed midnight.
    let todayLabel: String
    let goalSeconds: Int
    let streakDays: Int

    var focusedSeconds: Int { blocks.reduce(0) { $0 + $1.focusedSeconds } }
    var completedCount: Int { blocks.filter(\.completed).count }
    var reachedGoalNow: Bool { todaySeconds >= goalSeconds && todaySeconds - focusedSeconds < goalSeconds }
}

extension AppModel {
    /// Gathers every block and break since the sitting began and puts on the show.
    func celebrateRun(since start: Date) {
        guard settings.celebrateSessions else { return }
        let focus = data.sessions
            .filter { $0.startedAt >= start && $0.outcome != .abandoned && $0.focusedSeconds > 0 }
            .sorted { $0.startedAt < $1.startedAt }
        guard focus.reduce(0, { $0 + $1.focusedSeconds }) >= 60 else { return }
        let rests = (data.breaks ?? []).filter { $0.startedAt >= start }
        let colors = Dictionary(uniqueKeysWithValues: data.tasks.map { ($0.id, $0.colorHex) })

        var intentions: [String] = []
        for session in focus {
            let text = session.intention.isEmpty ? session.taskName : session.intention
            if !text.isEmpty, !intentions.contains(text) { intentions.append(text) }
        }

        let summary = CelebrationSummary(
            blocks: focus.map { session in
                CelebrationSummary.Block(
                    id: session.id,
                    focusedSeconds: session.focusedSeconds,
                    plannedSeconds: session.plannedSeconds,
                    completed: session.outcome == .completed,
                    colorHex: session.taskID.flatMap { colors[$0] } ?? "BDA56F"
                )
            },
            intentions: intentions,
            startedAt: focus.first?.startedAt ?? start,
            // The last moment something was actually timing, so a break left paused
            // for hours (say, while you're out) doesn't stretch the sitting.
            endedAt: (focus.map { $0.activeIntervals?.last?.endedAt ?? $0.endedAt }
                      + rests.map { $0.activeIntervals?.last?.endedAt ?? $0.endedAt }).max() ?? Date(),
            breakCount: rests.count,
            breakSeconds: rests.reduce(0) { $0 + $1.restedSeconds },
            pausedSeconds: focus.reduce(0) { $0 + $1.pausedSeconds },
            overtimeSeconds: focus.reduce(0) { $0 + max(0, $1.focusedSeconds - $1.plannedSeconds) },
            todaySeconds: dayFocus(from: start),
            todayLabel: Calendar.current.isDateInToday(start) ? "TODAY"
                : Calendar.current.isDateInYesterday(start) ? "SINCE YESTERDAY"
                : "SINCE \(start.formatted(.dateTime.weekday(.wide)).uppercased())",
            goalSeconds: max(60, settings.dailyGoalMinutes * 60),
            streakDays: analytics.currentStreak
        )
        CelebrationController.shared.show(summary)
    }

    /// Focus since the start of the day the sitting began, so a sitting that runs to
    /// 3 AM is measured against the evening it started in, not the hours after midnight.
    private func dayFocus(from sittingStart: Date) -> Int {
        let dayStart = Calendar.current.startOfDay(for: min(sittingStart, Date()))
        return data.sessions
            .filter { $0.startedAt >= dayStart && $0.outcome != .abandoned }
            .reduce(0) { $0 + $1.focusedSeconds }
    }
}

// MARK: - Controller

/// Puts the celebration over every window on the screen you're looking at, for about
/// ten seconds. It never takes keyboard focus from another app; a click anywhere, Esc
/// (while Pomofocus is frontmost), or the timer sends it away.
@MainActor
final class CelebrationController {
    static let shared = CelebrationController()

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private var keyMonitor: Any?

    static let displaySeconds: Double = 10

    func show(_ summary: CelebrationSummary) {
        dismiss(animated: false)

        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) })
            ?? NSScreen.main ?? NSScreen.screens.first else { return }

        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.setFrame(screen.frame, display: false)
        panel.contentView = NSHostingView(
            rootView: CelebrationView(summary: summary) { [weak self] in self?.dismiss(animated: true) }
        )
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.45
            panel.animator().alphaValue = 1
        }
        self.panel = panel

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 || event.keyCode == 36 || event.keyCode == 49 else { return event }
            MainActor.assumeIsolated { self?.dismiss(animated: true) }
            return nil
        }

        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.displaySeconds))
            guard !Task.isCancelled else { return }
            self?.dismiss(animated: true)
        }
    }

    func dismiss(animated: Bool) {
        dismissTask?.cancel()
        dismissTask = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        guard let panel else { return }
        self.panel = nil
        guard animated else {
            panel.orderOut(nil)
            panel.contentView = nil
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.6
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            panel.orderOut(nil)
            panel.contentView = nil
        }
    }
}

// MARK: - Scene

private struct CelebrationView: View {
    let summary: CelebrationSummary
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var countStart = Date.distantFuture
    @State private var countdown = false

    private var accent: Color { NonnaTheme.terracotta }

    private var pomodoroWord: String { summary.blocks.count == 1 ? "POMODORO" : "POMODOROS" }

    private var eyebrow: String {
        if summary.reachedGoalNow { return "SESSION COMPLETE · DAILY GOAL REACHED" }
        return "SESSION COMPLETE · \(summary.blocks.count) \(pomodoroWord)"
    }

    private var title: String {
        if summary.reachedGoalNow { return "Goal reached." }
        switch summary.blocks.count {
        case 4...: return "Brava."
        case 2...3: return "Beautifully done."
        default: return "Well done."
        }
    }

    /// "7:40 PM – 9:05 PM", or with weekdays when the sitting crossed midnight.
    private var spanText: String {
        let sameDay = Calendar.current.isDate(summary.startedAt, inSameDayAs: summary.endedAt)
        let style: Date.FormatStyle = sameDay
            ? .dateTime.hour().minute()
            : .dateTime.weekday(.abbreviated).hour().minute()
        return "\(summary.startedAt.formatted(style).uppercased()) – \(summary.endedAt.formatted(style).uppercased())"
    }

    private var intentionLine: String {
        let shown = summary.intentions.prefix(3).joined(separator: "  ·  ")
        let more = summary.intentions.count - 3
        return more > 0 ? "\(shown)  ·  +\(more) more" : shown
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(shown ? 0.58 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
                .animation(.easeOut(duration: 0.6), value: shown)

            if !reduceMotion {
                ConfettiBurst(colors: [
                    NonnaTheme.terracotta, NonnaTheme.darkTerracotta, NonnaTheme.sage,
                    NonnaTheme.gold, NonnaTheme.ink, Color(hex: "788897")
                ].map { NSColor($0) })
                .allowsHitTesting(false)
            }

            card
                .opacity(shown ? 1 : 0)
                .scaleEffect(shown || reduceMotion ? 1 : 0.94)
                .offset(y: shown || reduceMotion ? 0 : 18)
                .animation(reduceMotion ? nil : .spring(duration: 0.85, bounce: 0.18).delay(0.12), value: shown)
                .onTapGesture(perform: onDismiss)
        }
        .preferredColorScheme(.dark)
        .foregroundStyle(NonnaTheme.ink)
        .onAppear {
            shown = true
            countStart = Date().addingTimeInterval(reduceMotion ? -10 : 0.45)
            countdown = true
        }
    }

    // MARK: Card

    private var card: some View {
        VStack(spacing: 26) {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(accent)
                        .frame(width: 6, height: 6)
                        .shadow(color: accent.opacity(0.8), radius: 5)
                    Text(eyebrow)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(3)
                        .foregroundStyle(accent)
                }
                Text(title)
                    .font(.system(size: 64, weight: .regular, design: .serif))
                    .tracking(-1)
                if !summary.intentions.isEmpty {
                    Text(intentionLine)
                        .font(.system(size: 20, design: .serif))
                        .italic()
                        .foregroundStyle(NonnaTheme.ink.opacity(0.72))
                        .lineLimit(1)
                        .frame(maxWidth: 760)
                }
                Text("\(spanText)  ·  \(max(0, Int(summary.endedAt.timeIntervalSince(summary.startedAt))).focusDurationString.uppercased()) AT THE DESK")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }

            VStack(spacing: 6) {
                TimelineView(.animation(minimumInterval: 1.0 / 40, paused: !countdown)) { context in
                    Text(Self.longClock(countedValue(at: context.date)))
                        .font(.system(size: 112, weight: .light))
                        .tracking(-4)
                        .monospacedDigit()
                        .onChange(of: context.date >= countStart.addingTimeInterval(Self.countDuration)) { _, done in
                            if done { countdown = false }
                        }
                }
                Text("FOCUSED IN TOTAL")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }

            pomodoroStrip

            Rectangle()
                .fill(LinearGradient(colors: [.clear, NonnaTheme.strongLine, .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)

            HStack(alignment: .top, spacing: 0) {
                statTile("POMODOROS", "\(summary.blocks.count)",
                         detail: blockDetail, delay: 0.55)
                divider
                statTile("BREAKS", "\(summary.breakCount)",
                         detail: summary.breakSeconds >= 60 ? "\(summary.breakSeconds.focusDurationString) of rest" : "no rest taken", delay: 0.65)
                divider
                statTile("PAUSED", summary.pausedSeconds >= 60 ? summary.pausedSeconds.focusDurationString : "None",
                         detail: summary.pausedSeconds >= 60 ? "stepped away" : "unbroken", delay: 0.75)
                divider
                statTile("OVERTIME", summary.overtimeSeconds >= 60 ? "+" + summary.overtimeSeconds.focusDurationString : "—",
                         detail: summary.overtimeSeconds >= 60 ? "past the bell" : "on time", delay: 0.85)
                divider
                todayTile.reveal(shown, delay: 0.95, reduceMotion: reduceMotion)
                divider
                statTile("STREAK", "\(summary.streakDays) \(summary.streakDays == 1 ? "day" : "days")",
                         detail: "keep it going", delay: 1.05)
            }

            VStack(spacing: 10) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(NonnaTheme.line)
                        Capsule()
                            .fill(accent.opacity(0.7))
                            .frame(width: shown ? 0 : proxy.size.width)
                            .animation(reduceMotion ? nil : .linear(duration: CelebrationController.displaySeconds), value: shown)
                    }
                }
                .frame(width: 160, height: 2)
                Text("CLICK ANYWHERE TO CONTINUE")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(NonnaTheme.secondaryInk.opacity(0.75))
            }
        }
        .padding(.horizontal, 56)
        .padding(.vertical, 48)
        .frame(minWidth: 860)
        .fixedSize()
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(NonnaTheme.paper.opacity(0.94))
                RadialGradient(
                    colors: [accent.opacity(0.16), .clear],
                    center: .top,
                    startRadius: 10,
                    endRadius: 520
                )
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(colors: [.white.opacity(0.16), NonnaTheme.line, .black.opacity(0.3)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 0.8
                )
        }
        .shadow(color: .black.opacity(0.6), radius: 50, y: 24)
    }

    private var divider: some View {
        Rectangle()
            .fill(NonnaTheme.line)
            .frame(width: 1, height: 58)
    }

    private func statTile(_ label: String, _ value: String, detail: String, delay: Double) -> some View {
        VStack(spacing: 7) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(NonnaTheme.secondaryInk)
            Text(value)
                .font(.system(size: 24, weight: .medium))
                .monospacedDigit()
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(NonnaTheme.secondaryInk)
        }
        .frame(width: 124)
        .reveal(shown, delay: delay, reduceMotion: reduceMotion)
    }

    private var todayTile: some View {
        let fraction = min(1, Double(summary.todaySeconds) / Double(summary.goalSeconds))
        return VStack(spacing: 7) {
            Text(summary.todayLabel)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .tracking(2)
                .foregroundStyle(NonnaTheme.secondaryInk)
            Text(summary.todaySeconds.focusDurationString)
                .font(.system(size: 24, weight: .medium))
                .monospacedDigit()
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(NonnaTheme.line)
                    Capsule()
                        .fill(fraction >= 1 ? NonnaTheme.sage : accent)
                        .frame(width: proxy.size.width * (shown ? fraction : 0))
                        .animation(reduceMotion ? nil : .easeOut(duration: 1.2).delay(1.1), value: shown)
                }
            }
            .frame(width: 84, height: 3)
            .padding(.top, 4)
            Text("of \(summary.goalSeconds.focusDurationString) goal")
                .font(.system(size: 10))
                .foregroundStyle(NonnaTheme.secondaryInk)
        }
        .frame(width: 124)
    }

    private var blockDetail: String {
        let early = summary.blocks.count - summary.completedCount
        if early == 0 { return summary.completedCount == 1 ? "full block" : "all full blocks" }
        if summary.completedCount == 0 { return early == 1 ? "ended early" : "\(early) ended early" }
        return "\(summary.completedCount) full · \(early) early"
    }

    /// One bar per pomodoro, in order, sized by how much of its plan it filled.
    private var pomodoroStrip: some View {
        HStack(alignment: .bottom, spacing: summary.blocks.count > 8 ? 10 : 18) {
            ForEach(Array(summary.blocks.enumerated()), id: \.element.id) { index, block in
                let fill = min(1.2, Double(block.focusedSeconds) / Double(max(1, block.plannedSeconds)))
                let color = NonnaTheme.taskColor(for: block.colorHex)
                VStack(spacing: 7) {
                    ZStack(alignment: .bottom) {
                        Capsule()
                            .fill(NonnaTheme.line)
                            .frame(width: 8, height: 56)
                        Capsule()
                            .fill(LinearGradient(
                                colors: [color.opacity(block.completed ? 1 : 0.55), color.opacity(block.completed ? 0.55 : 0.25)],
                                startPoint: .top, endPoint: .bottom
                            ))
                            .frame(width: 8, height: shown ? max(6, 56 * min(1, fill)) : 0)
                            .shadow(color: block.completed ? color.opacity(0.55) : .clear, radius: 6)
                            .animation(reduceMotion ? nil : .spring(duration: 0.8, bounce: 0.2).delay(0.5 + Double(index) * 0.12), value: shown)
                    }
                    Text(block.focusedSeconds.focusDurationString)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(block.completed ? NonnaTheme.ink.opacity(0.8) : NonnaTheme.secondaryInk)
                }
                .help(block.completed ? "Full block" : "Ended early")
            }
        }
    }

    private static func longClock(_ seconds: Int) -> String {
        let value = max(0, seconds)
        guard value >= 3600 else { return value.clockString }
        return String(format: "%d:%02d:%02d", value / 3600, (value % 3600) / 60, value % 60)
    }

    // MARK: Count-up

    private static let countDuration: Double = 1.6

    private func countedValue(at date: Date) -> Int {
        let t = min(1, max(0, date.timeIntervalSince(countStart) / Self.countDuration))
        let eased = 1 - pow(1 - t, 3)   // ease-out cubic: fast, then settles on the number
        return Int((Double(summary.focusedSeconds) * eased).rounded())
    }
}

private extension View {
    func reveal(_ shown: Bool, delay: Double, reduceMotion: Bool) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.7).delay(delay), value: shown)
    }
}

// MARK: - Confetti

/// A screen-wide confetti fall plus two corner cannons, as Core Animation emitters. The
/// window server animates every piece; the app only sets it off and stops the flow.
private struct ConfettiBurst: NSViewRepresentable {
    let colors: [NSColor]

    func makeNSView(context: Context) -> ConfettiView {
        let view = ConfettiView()
        view.colors = colors
        return view
    }

    func updateNSView(_ view: ConfettiView, context: Context) {}
}

final class ConfettiView: NSView {
    var colors: [NSColor] = []
    private var fired = false
    private let rain = CAEmitterLayer()
    private let leftCannon = CAEmitterLayer()
    private let rightCannon = CAEmitterLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        guard !fired, bounds.width > 0 else { return }
        fired = true
        fire()
    }

    private func fire() {
        let width = bounds.width
        let height = bounds.height
        let scale = window?.backingScaleFactor ?? 2
        let now = CACurrentMediaTime()

        rain.emitterShape = .line
        rain.emitterPosition = CGPoint(x: width / 2, y: height + 24)
        rain.emitterSize = CGSize(width: width * 1.1, height: 1)
        rain.beginTime = now
        rain.emitterCells = cells(
            ratePerCell: Float(width / 3440 * 22),
            velocity: 170, velocityRange: 110,
            longitude: -.pi / 2, range: .pi / 7,
            gravity: -150, lifetime: 9, scale: scale
        )

        for (cannon, x, longitude) in [(leftCannon, CGFloat(0), CGFloat.pi / 2.9), (rightCannon, width, CGFloat.pi - .pi / 2.9)] {
            cannon.emitterShape = .point
            cannon.emitterPosition = CGPoint(x: x, y: -10)
            cannon.beginTime = now + 0.15
            cannon.emitterCells = cells(
                ratePerCell: 26,
                velocity: height * 0.95, velocityRange: height * 0.25,
                longitude: longitude, range: .pi / 9,
                gravity: -height * 0.55, lifetime: 7, scale: scale
            )
        }

        for emitter in [rain, leftCannon, rightCannon] {
            emitter.renderMode = .unordered
            layer?.addSublayer(emitter)
        }

        // Bursts, not streams: open the taps briefly, then let everything fall out.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            self?.leftCannon.birthRate = 0
            self?.rightCannon.birthRate = 0
            try? await Task.sleep(for: .milliseconds(1400))
            self?.rain.birthRate = 0
        }
    }

    private func cells(
        ratePerCell: Float,
        velocity: CGFloat, velocityRange: CGFloat,
        longitude: CGFloat, range: CGFloat,
        gravity: CGFloat, lifetime: Float, scale: CGFloat
    ) -> [CAEmitterCell] {
        let shapes = Self.shapes(scale: scale)
        return colors.flatMap { color in
            shapes.map { image in
                let cell = CAEmitterCell()
                cell.contents = image
                cell.contentsScale = scale
                cell.color = color.cgColor
                cell.birthRate = ratePerCell
                cell.lifetime = lifetime
                cell.lifetimeRange = 1.5
                cell.velocity = velocity
                cell.velocityRange = velocityRange
                cell.emissionLongitude = longitude
                cell.emissionRange = range
                cell.yAcceleration = gravity
                cell.xAcceleration = CGFloat.random(in: -12...12)
                cell.spin = 3
                cell.spinRange = 7
                cell.scale = 1
                cell.scaleRange = 0.35
                cell.alphaRange = 0.15
                cell.alphaSpeed = -1 / lifetime * 0.6
                return cell
            }
        }
    }

    /// White pieces the cells tint: a ribbon, a square, and a dot.
    private static func shapes(scale: CGFloat) -> [CGImage] {
        let specs: [(CGSize, CGFloat)] = [(CGSize(width: 12, height: 5), 1.5), (CGSize(width: 8, height: 8), 1.5), (CGSize(width: 7, height: 7), 3.5)]
        return specs.compactMap { size, radius in
            let pixelWidth = Int(size.width * scale)
            let pixelHeight = Int(size.height * scale)
            guard let context = CGContext(
                data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            context.setFillColor(NSColor.white.cgColor)
            let rect = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius * scale, cornerHeight: radius * scale, transform: nil))
            context.fillPath()
            return context.makeImage()
        }
    }
}
