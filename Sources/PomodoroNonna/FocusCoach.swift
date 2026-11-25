import SwiftUI

// What Pomofocus offers when focus slips: one clear next step, matched to how the last block
// went, rather than a menu to think about. Restless is the body asking to move; Scattered is
// a full head that needs emptying; two rough blocks in a row mean rest beats pushing.

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
                Text("One thought per line: things to do, worries, ideas. Each one goes to Tasks.")
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
