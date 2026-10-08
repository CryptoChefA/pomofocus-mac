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
                .preferredColorScheme(.dark)
                .frame(minWidth: 1180, minHeight: 720)
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
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                Button("Skip Break and Start Focus") { model.skipBreakAndStartFocus() }
                    .disabled(model.phase == .focus && !model.isOvertime)
                Divider()
                Button("Cinema Mode") { CinematicController.shared.toggle(model: model) }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
            }
            CommandMenu("Canvas") {
                Button("Paste Image") { model.pasteImageFromClipboard() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                Button("Add Images from Mac…") { model.chooseImages() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            MenuBarTimerView()
                .environment(model)
                .preferredColorScheme(.dark)
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
        return (model.isOvertime ? "+" : "") + model.displaySeconds.clockString
    }

    var body: some View {
        _ = pulse.tick   // redraws on the pulse, not in a loop
        return Image(nsImage: glyph(at: Date()))
            .accessibilityLabel(menuBarText.map { "Pomofocus, \($0)" } ?? "Pomofocus")
    }

    private func glyph(at now: Date) -> NSImage {
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
