import SwiftUI

// What Pomofocus offers when focus slips: one clear next step, matched to how the last block
// went, rather than a menu to think about. Restless is the body asking to move; Scattered is
// a full head that needs emptying; two rough blocks in a row mean rest beats pushing.

/// On the break after a rough block: one suggestion, and the button to act on it.
struct CoachCard: View {
    @Environment(AppModel.self) private var model
    let kind: AppModel.CoachSuggestion
    let onBrainDump: () -> Void
    let onDismiss: () -> Void

    private var icon: String {
        switch kind {
        case .move: "figure.walk"
        case .unload: "square.and.pencil"
        case .callIt: "moon.zzz"
        }
    }

    private var title: String {
        switch kind {
        case .move: "Get up and move"
        case .unload: "Empty your head"
        case .callIt: "Two tough blocks in a row"
        }
    }

    private var detail: String {
        switch kind {
        case .move:
            "That block felt restless. Walk for five minutes, phone in your pocket, and come back when the break ends. Moving clears restlessness faster than sitting through it."
        case .unload:
            "That block felt scattered. Two minutes writing down everything on your mind gets it out of the way, or try the guided reset for a busy mind."
        case .callIt:
            "Your plan has stepped down a level. A proper 20-minute rest, away from the screen, will help more than a third push right now."
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 19))
                .foregroundStyle(NonnaTheme.sage)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    switch kind {
                    case .move:
                        Button("I'll go now") { onDismiss() }
                            .buttonStyle(NonnaButtonStyle(color: NonnaTheme.sage))
                        Button("One-minute reset instead") {
                            model.startQuickReset(.oneMinute)
                            onDismiss()
                        }
                        .buttonStyle(NonnaButtonStyle(prominent: false))
                    case .unload:
                        Button("Brain dump") { onBrainDump() }
                            .buttonStyle(NonnaButtonStyle(color: NonnaTheme.sage))
                        Button("Settle a busy mind") {
                            model.startQuickReset(.settle)
                            onDismiss()
                        }
                        .buttonStyle(NonnaButtonStyle(prominent: false))
                    case .callIt:
                        Button("End the session") {
                            model.endSession()
                            onDismiss()
                        }
                        .buttonStyle(NonnaButtonStyle(color: NonnaTheme.sage))
                        Button("Keep going") { onDismiss() }
                            .buttonStyle(NonnaButtonStyle(prominent: false))
                    }
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(NonnaTheme.sage.opacity(0.1))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(NonnaTheme.sage.opacity(0.45), lineWidth: 0.8)
                }
        }
    }
}

/// Two minutes to get everything out of your head. Each line becomes a to-do, so it can
/// wait until later instead of circling while you work.
struct BrainDumpSheet: View {
    @Environment(AppModel.self) private var model
    let onClose: () -> Void
    @State private var text = ""
    @State private var parked: Int?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("What's on your mind?")
                    .font(.system(size: 22, weight: .semibold))
                Text("Write it all down, one thought per line: things to do, worries, ideas. Each one waits in Tasks, so you don't have to hold it.")
                    .font(.system(size: 12))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextEditor(text: $text)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 200)
                .background(NonnaTheme.raisedPaper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }
                .focused($focused)
            HStack {
                if let parked {
                    Label(parked == 0 ? "Nothing to park" : "\(parked) parked in Tasks", systemImage: "checkmark.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(NonnaTheme.sage)
                }
                Spacer()
                Button("Close") { onClose() }
                    .buttonStyle(NonnaButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
                Button("Park Them") {
                    parked = model.parkThoughts(text)
                    text = ""
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        onClose()
                    }
                }
                .buttonStyle(NonnaButtonStyle())
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(26)
        .frame(width: 480)
        .background(NonnaTheme.cream)
        .onAppear { focused = true }
    }
}

/// The "Drifting?" menu on a running focus block: ways to rescue it instead of quitting.
struct DriftingMenu: View {
    @Environment(AppModel.self) private var model
    let onBrainDump: () -> Void

    var body: some View {
        Menu {
            Button {
                model.startQuickReset(.oneMinute)
            } label: {
                Label("One-minute reset", systemImage: "wind")
            }
            Button {
                onBrainDump()
            } label: {
                Label("Park what's on your mind…", systemImage: "square.and.pencil")
            }
            if model.remainingSeconds > 11 * 60 {
                Button {
                    model.finishSmall(minutes: 10)
                } label: {
                    Label("Finish small: 10 more minutes", systemImage: "scope")
                }
            }
            Divider()
            Button {
                model.startBreak()
            } label: {
                Label("Take a break now", systemImage: "cup.and.saucer")
            }
        } label: {
            Label("Drifting?", systemImage: "wind")
                .font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(NonnaTheme.secondaryInk)
        .help("Losing focus? Rescue this block instead of quitting it")
    }
}
