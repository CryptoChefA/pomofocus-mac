import AppIntents
import PomofocusShared
import SwiftUI
import WidgetKit

// Buttons for Control Center and the menu bar (macOS 26 and later). They run the same
// intents as the widget's buttons, so they need nothing new from the app.

/// What the timer button shows: the action a press will take.
struct TimerControlState: Sendable {
    let title: String
    let icon: String
}

@available(macOS 26.0, *)
struct TimerControlProvider: ControlValueProvider {
    var previewValue: TimerControlState { TimerControlState(title: "Start focus", icon: "play.fill") }

    func currentValue() async throws -> TimerControlState {
        let snapshot = (try? PomofocusWidgetSnapshotStore.load()) ?? .idle
        guard let action = WidgetAction.actions(for: snapshot).first(where: \.prominent) else {
            return previewValue
        }
        // "Next: 25 min focus" reads well on the widget; a control's label is short.
        let title = snapshot.nextTitle == action.title ? "Start next" : action.title
        return TimerControlState(title: title, icon: action.icon)
    }
}

/// Start, pause, resume or move on, whichever fits right now.
@available(macOS 26.0, *)
struct TimerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: PomofocusControl.controlCenterKinds[0], provider: TimerControlProvider()) { state in
            ControlWidgetButton(action: ToggleTimerIntent()) {
                Label(state.title, systemImage: state.icon)
            }
        }
        .displayName("Pomofocus Timer")
        .description("Start, pause or resume your focus block, or start the next one.")
    }
}

@available(macOS 26.0, *)
struct EndSessionControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: PomofocusControl.controlCenterKinds[1]) {
            ControlWidgetButton(action: EndSessionIntent()) {
                Label("End Session", systemImage: "stop.fill")
            }
        }
        .displayName("End Pomofocus Session")
        .description("Saves what you've tracked and stops the timer.")
    }
}
