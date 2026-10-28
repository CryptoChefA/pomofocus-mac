import SwiftUI

/// Rename a finished block or move it to another list.
struct EditSessionSheet: View {
    @Environment(AppModel.self) private var model
    let session: FocusSession
    let onDone: () -> Void
    @State private var intention: String
    @State private var taskID: UUID?
    @FocusState private var focused: Bool

    init(session: FocusSession, onDone: @escaping () -> Void) {
        self.session = session
        self.onDone = onDone
        _intention = State(initialValue: session.intention)
        _taskID = State(initialValue: session.taskID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit session")
                    .font(.system(size: 24, weight: .regular, design: .serif))
                Text("\(session.startedAt.formatted(date: .abbreviated, time: .shortened)), \(session.focusedSeconds.focusDurationString)")
                    .font(.system(size: 12))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }

            field("What were you working on?") {
                TextField("Name this session", text: $intention)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(NonnaTheme.paper, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(NonnaTheme.terracotta.opacity(0.5), lineWidth: 1) }
                    .focused($focused)
                    .onSubmit(save)
            }

            if !model.tasks.isEmpty {
                field("List") {
                    FlowChips {
                        ForEach(model.tasks) { list in
                            PillButton(title: list.name, dot: NonnaTheme.taskColor(for: list.colorHex), selected: taskID == list.id) {
                                taskID = taskID == list.id ? nil : list.id
                            }
                        }
                    }
                }
            }

            HStack {
                Button("Cancel", action: onDone)
                    .buttonStyle(NonnaButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save", action: save)
                    .buttonStyle(NonnaButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 520)
        .background(NonnaTheme.cream)
        .foregroundStyle(NonnaTheme.ink)
        .preferredColorScheme(NonnaTheme.colorScheme)
        .onAppear { focused = true }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NonnaTheme.secondaryInk)
            content()
        }
    }

    private func save() {
        model.updateSession(id: session.id, intention: intention, taskID: taskID)
        onDone()
    }
}
