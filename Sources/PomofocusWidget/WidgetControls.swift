import AppIntents
import AppKit
import Foundation
import PomofocusShared

// The widget's buttons. Each is a tiny App Intent that runs in the widget's own process
// and passes the request to the app, which does the timing.
//
// Xcode normally writes these intents' metadata (Metadata.appintents) at build time. This
// project builds without Xcode, so Scripts/appintents-metadata.py writes it instead, reading
// each intent's title and description from here. Keep them simple (no parameters) and
// internal, not private, so the script can find their names in the binary.

enum ControlSender {
    static let appBundleID = "org.pomodorononna.app"

    static func send(_ control: PomofocusControl) async {
        let before = try? PomofocusWidgetSnapshotStore.load()
        if NSRunningApplication.runningApplications(withBundleIdentifier: appBundleID).isEmpty {
            // Not open: launch it in the background with the same request as a link.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            _ = try? await NSWorkspace.shared.open(control.url, configuration: configuration)
        } else {
            DistributedNotificationCenter.default().postNotificationName(
                control.notificationName, object: nil, userInfo: nil, deliverImmediately: true
            )
        }
        // The widget redraws as soon as this returns. Give the app a moment to save its new
        // state first, so the buttons don't flicker back to the old one.
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(50))
            if let now = try? PomofocusWidgetSnapshotStore.load(), now != before { return }
        }
    }
}

struct StartTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Focus"
    static let description = IntentDescription("Starts the Pomofocus timer.")
    func perform() async throws -> some IntentResult {
        await ControlSender.send(.start)
        return .result()
    }
}

struct PauseTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause Timer"
    static let description = IntentDescription("Pauses the running Pomofocus timer.")
    func perform() async throws -> some IntentResult {
        await ControlSender.send(.pause)
        return .result()
    }
}

struct ResumeTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume Timer"
    static let description = IntentDescription("Resumes a paused Pomofocus timer.")
    func perform() async throws -> some IntentResult {
        await ControlSender.send(.resume)
        return .result()
    }
}

struct NextBlockIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Next Block"
    static let description = IntentDescription("Moves on to the next focus block or break, or skips the breathing ritual.")
    func perform() async throws -> some IntentResult {
        await ControlSender.send(.next)
        return .result()
    }
}

struct EndSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "End Session"
    static let description = IntentDescription("Ends the current Pomofocus session and saves it.")
    func perform() async throws -> some IntentResult {
        await ControlSender.send(.end)
        return .result()
    }
}

struct SkipBreakIntent: AppIntent {
    static let title: LocalizedStringResource = "Skip Break"
    static let description = IntentDescription("Skips the break and starts the next focus block.")
    func perform() async throws -> some IntentResult {
        await ControlSender.send(.skipBreak)
        return .result()
    }
}

struct ToggleTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start or Pause Timer"
    static let description = IntentDescription("Starts, pauses or resumes the Pomofocus timer, or moves on to the next block when one is waiting.")
    func perform() async throws -> some IntentResult {
        await ControlSender.send(.toggle)
        return .result()
    }
}
