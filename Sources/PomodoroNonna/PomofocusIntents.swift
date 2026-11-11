import AppIntents
import PomofocusShared

// Pomofocus's actions for Spotlight, Shortcuts and Siri. They run inside the app and use
// the same checks as the widget's buttons, so an action that doesn't fit what the timer is
// doing does nothing.
//
// Xcode normally writes these intents' metadata at build time. This project builds without
// Xcode, so Scripts/appintents-metadata.py writes it, reading the titles, descriptions and
// App Shortcuts from this file. Keep the intents simple (no parameters) and the shortcuts
// in the one-line-per-field form below so the script can read them.

@MainActor
enum IntentRouter {
    static func run(_ control: PomofocusControl) async {
        // When an action launches Pomofocus, the model may be a moment away.
        for _ in 0..<40 {
            if let model = AppModel.current {
                model.perform(control)
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}

struct StartFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Focus"
    static let description = IntentDescription("Starts the Pomofocus timer.")
    func perform() async throws -> some IntentResult {
        await IntentRouter.run(.start)
        return .result()
    }
}

struct PauseFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause Timer"
    static let description = IntentDescription("Pauses the running Pomofocus timer.")
    func perform() async throws -> some IntentResult {
        await IntentRouter.run(.pause)
        return .result()
    }
}

struct ResumeFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume Timer"
    static let description = IntentDescription("Resumes a paused Pomofocus timer.")
    func perform() async throws -> some IntentResult {
        await IntentRouter.run(.resume)
        return .result()
    }
}

struct ToggleFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Start or Pause Timer"
    static let description = IntentDescription("Starts, pauses or resumes the Pomofocus timer, or moves on to the next block when one is waiting.")
    func perform() async throws -> some IntentResult {
        await IntentRouter.run(.toggle)
        return .result()
    }
}

struct NextFocusBlockIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Next Block"
    static let description = IntentDescription("Moves on to the next focus block or break, or skips the breathing ritual.")
    func perform() async throws -> some IntentResult {
        await IntentRouter.run(.next)
        return .result()
    }
}

struct SkipFocusBreakIntent: AppIntent {
    static let title: LocalizedStringResource = "Skip Break"
    static let description = IntentDescription("Skips the break and starts the next focus block.")
    func perform() async throws -> some IntentResult {
        await IntentRouter.run(.skipBreak)
        return .result()
    }
}

struct EndFocusSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "End Session"
    static let description = IntentDescription("Ends the current Pomofocus session and saves it.")
    func perform() async throws -> some IntentResult {
        await IntentRouter.run(.end)
        return .result()
    }
}

/// What Spotlight offers when you search for Pomofocus, and what Siri answers to.
struct PomofocusShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartFocusIntent(),
            phrases: ["Start focus in \(.applicationName)", "Start a \(.applicationName) block"],
            shortTitle: "Start Focus",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: PauseFocusIntent(),
            phrases: ["Pause \(.applicationName)", "Pause my \(.applicationName) timer"],
            shortTitle: "Pause Timer",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: ResumeFocusIntent(),
            phrases: ["Resume \(.applicationName)", "Resume my \(.applicationName) timer"],
            shortTitle: "Resume Timer",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: NextFocusBlockIntent(),
            phrases: ["Start the next \(.applicationName) block"],
            shortTitle: "Start Next Block",
            systemImageName: "arrow.right"
        )
        AppShortcut(
            intent: SkipFocusBreakIntent(),
            phrases: ["Skip the break in \(.applicationName)"],
            shortTitle: "Skip Break",
            systemImageName: "forward.end.fill"
        )
        AppShortcut(
            intent: EndFocusSessionIntent(),
            phrases: ["End my \(.applicationName) session"],
            shortTitle: "End Session",
            systemImageName: "stop.fill"
        )
    }
}
