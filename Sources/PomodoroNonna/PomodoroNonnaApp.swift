import SwiftUI

@main
struct PomodoroNonnaApp: App {
    @State private var model = AppModel()
    @StateObject private var calendarStore = CalendarStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup("Pomofocus") {
            RootView()
                .environment(model)
                .environmentObject(calendarStore)
                .preferredColorScheme(NonnaTheme.colorScheme)
                .frame(minWidth: 720, minHeight: 560)
                .onChange(of: model.settings.showCalendarEvents) { _, enabled in
                    guard enabled, calendarStore.access == .notDetermined else { return }
                    calendarStore.requestAccess()
                }
                .onChange(of: scenePhase) { _, newValue in
                    if newValue != .active { model.persistActiveTimer() }
                    if newValue == .active {
                        calendarStore.refreshAccess()
                        if model.settings.showCalendarEvents, calendarStore.access == .notDetermined {
                            calendarStore.requestAccess()
                        }
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1440, height: 860)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Task { await Updater.shared.check(userInitiated: true) } }
            }
            CommandMenu("Timer") {
                Button(model.canAdvanceCycle ? model.nextActionTitle : model.status == .idle ? "Start Focus" : "Pause or Resume") {
                    if model.canAdvanceCycle {
                        model.advanceToNextPhase()
                    } else if model.status == .idle {
                        model.startFocus()
                    } else {
                        model.togglePause()
                    }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                Button("End Session") { model.endSession() }
                    .disabled(!model.canEndSession)
                    .keyboardShortcut(".", modifiers: [.command])
                Button("Start Break") { model.startBreak() }
                    .disabled(model.phase != .focus && model.status != .idle)
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                Button("Skip Break and Start Focus") { model.skipBreakAndStartFocus() }
                    .disabled(model.phase == .focus && !model.isOvertime)
                Divider()
                Button("How Are You Feeling…") { model.showsMoodCheckIn = true }
                Button("Your Week…") { model.weekSheetStart = model.lastWeekStart }
                Button("Your Year in Focus…") { model.yearSheet = model.replayYearNow }
                Button("Wrap Up Today…") { model.showsWrapUp = true }
                Divider()
                Button("Cinema Mode") { CinematicController.shared.toggle(model: model) }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }

        // "Show in the menu bar" in setup and Settings; taking the item out with ⌘-drag turns it off too.
        MenuBarExtra(isInserted: Binding(
            get: { model.settings.showInMenuBar },
            // SwiftUI writes this back while it updates the scene; saving an unchanged
            // value would update the scene again, round and round.
            set: { shown in
                guard shown != model.settings.showInMenuBar else { return }
                model.updateSettings { $0.showInMenuBar = shown }
            }
        )) {
            MenuBarTimerView()
                .tracksWindowVisibility()
                .environment(model)
                .preferredColorScheme(NonnaTheme.colorScheme)
        } label: {
            MenuBarLabel(model: model, pulse: model.menuPulse)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu-bar chip: a tank that drains as the session runs, breathes during the
/// opening ritual, turns green on a break and blinks red in overtime. It is its own view
/// so the clock and the pulse redraw this label alone, never the app's scenes.
private struct MenuBarLabel: View {
    let model: AppModel
    let pulse: MenuPulse

    /// What the menu bar shows. Nothing while idle, so the item stays small.
    private var menuBarText: String? {
        if model.awaitingNextPhase != nil { return "done" }
        if model.isBreathing { return "breathe" }
        if model.status == .idle { return nil }
        // Written the way the widget's live countdown writes it ("1:19", not "01:19"),
        // so the two read the same side by side.
        let seconds = max(0, model.displaySeconds)
        let clock = seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
        return (model.isOvertime ? "+" : "") + clock
    }

    var body: some View {
        _ = pulse.tick   // redraws on the pulse, not in a loop
        return Image(nsImage: glyph(at: Date()))
            .accessibilityLabel(menuBarText.map { "Pomofocus, \($0)" } ?? "Pomofocus")
    }

    private func glyph(at now: Date) -> NSImage {
        let settings = model.settings
        let style = MenuBarStyle(rawValue: settings.menuBarStyle) ?? .chip
        guard style != .chip else { return chip(at: now) }
        let color: NSColor? = settings.menuBarColor == "auto" ? nil : {
            let rgb = RGB(hex: settings.menuBarColor)
            return NSColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
        }()
        // Without a saved icon, "Your icon" shows the bars until one is chosen.
        let icon = style == .icon ? MenuBarIconStore.image : nil
        let minimal = style == .minimal
        // Minimal always shows something: the time left unless percent is chosen.
        let mode = minimal && settings.menuBarText == "none" ? "time" : settings.menuBarText
        let marks = bars(at: now)
        return MenuBarMark.image(
            bars: minimal ? MenuBarMark.Bars(levels: [], alpha: marks.alpha) : marks,
            color: color,
            icon: icon,
            iconFollowsMenuBar: settings.menuBarIconTemplate,
            text: label(mode: mode, minimal: minimal),
            showsMark: !minimal
        )
    }

    /// The words beside the mark: the time left, or how far through the block as a
    /// percentage. Idle, the minimal style shows the next block's length, dimmed by `bars`.
    private func label(mode: String, minimal: Bool) -> String? {
        switch mode {
        case "time":
            if let text = menuBarText { return text }
            return minimal ? (model.plannedSeconds / 60).description + ":00" : nil
        case "percent":
            if model.awaitingNextPhase != nil { return "done" }
            if model.isBreathing { return "breathe" }
            if model.status == .idle { return minimal ? "0%" : nil }
            if model.isOvertime { return "100%" }
            return "\(Int((model.progress * 100).rounded(.down)))%"
        default:
            return nil
        }
    }

    /// The three bars: each is a third of the block, and they empty from the right as the
    /// time runs down. Full when idle or done, breathing with you in the opening ritual,
    /// dim while paused, and blinking in overtime.
    private func bars(at now: Date) -> MenuBarMark.Bars {
        if model.isBreathing {
            let breath = model.breathFill ?? 0
            return MenuBarMark.Bars(levels: [breath, breath, breath], alpha: 1)
        }
        if model.status == .idle || model.awaitingNextPhase != nil {
            // Minimal shows the waiting time dimmed, so idle looks different from running.
            let idleAlpha = model.settings.menuBarStyle == MenuBarStyle.minimal.rawValue && model.status == .idle ? 0.55 : 1
            return MenuBarMark.Bars(levels: [1, 1, 1], alpha: idleAlpha)
        }
        let left = model.isOvertime ? 1 : max(0, min(1, 1 - model.progress))
        let levels = (0..<3).map { max(0, min(1, left * 3 - Double($0))) }
        let blinking = model.isOvertime && model.settings.overtimeAlert && model.status == .overtime
        let lit = !blinking || Int(now.timeIntervalSinceReferenceDate * 2) % 2 == 0
        let alpha = model.status == .paused ? 0.45 : (lit ? 1 : 0.3)
        return MenuBarMark.Bars(levels: levels, alpha: alpha)
    }

    private func chip(at now: Date) -> NSImage {
        if model.isBreathing {
            return MenuBarGlyph.image(text: "breathe", fill: model.breathFill ?? 0, tone: .focus)
        }
        if model.awaitingNextPhase != nil {
            return MenuBarGlyph.image(text: "done", fill: 1, tone: .rest)
        }
        if model.status == .idle {
            return MenuBarGlyph.image(text: nil, fill: 0, tone: .idle)
        }
        let paused = model.status == .paused
        let tone: MenuBarGlyph.Tone = model.isOvertime ? .alert
            : paused ? .paused
            : (model.phase == .focus ? .focus : .rest)
        // Running overtime blinks; everything else, paused overtime included, holds still.
        let blinking = model.isOvertime && model.settings.overtimeAlert && model.status == .overtime
        let lit = !blinking || Int(now.timeIntervalSinceReferenceDate * 2) % 2 == 0
        let fill = model.isOvertime ? 1 : max(0, min(1, 1 - model.progress))
        return MenuBarGlyph.image(text: menuBarText, fill: fill, tone: tone, isPaused: paused, lit: lit)
    }
}
