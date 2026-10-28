import SwiftUI

// Simple tasks: for when the list itself has become the thing you're working on.
// Today shows one task to do now and a couple after it, and a few minutes of planning
// earns a gentle "start with this?" instead of another colour to pick.

/// The one task to do now, big, with a single obvious way to start.
struct UpNextCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let todo: TodoItem
    let heading: String
    let canSkip: Bool
    let onSkip: () -> Void

    private var list: FocusTask? { model.data.tasks.first { $0.id == todo.listID } }
    private var tint: Color { list.map { NonnaTheme.taskColor(for: $0.colorHex) } ?? NonnaTheme.terracotta }
    private var nextStep: Subtask? { todo.steps.first { !$0.isDone } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(heading)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NonnaTheme.secondaryInk)
            Text(todo.title)
                .font(.system(size: 26, weight: .semibold))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            details
            HStack(spacing: 10) {
                Button {
                    if model.status == .idle {
                        model.startFocus(on: todo.id)
                        model.focusScreenRequest += 1
                    } else {
                        model.linkTodo(todo.id)
                    }
                } label: {
                    Label(model.status == .idle ? "Start focusing" : "Work on this next", systemImage: "play.fill")
                }
                .buttonStyle(NonnaButtonStyle())
                .help("Start a focus block on this")

                Button("Done") {
                    withAnimation(reduceMotion ? nil : NonnaMotion.selection) { model.toggleDone(todo.id) }
                }
                .buttonStyle(NonnaButtonStyle(prominent: false))

                if canSkip {
                    Button("Something else", action: onSkip)
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                        .padding(.leading, 4)
                        .help("Show the next task instead")
                }
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NonnaTheme.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.45), lineWidth: 1)
        }
        .contextMenu {
            Button("Due tomorrow") {
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))
                model.updateTodo(todo.id) { $0.due = tomorrow }
            }
            Button("Delete…", role: .destructive) { model.confirmDeleteTodo(todo.id) }
        }
    }

    private var details: some View {
        HStack(spacing: 14) {
            if let list {
                HStack(spacing: 6) {
                    Circle().fill(tint).frame(width: 7, height: 7)
                    Text(list.name)
                }
            }
            if let label = todo.dueLabel(), DueBucket.of(todo.due) != .today {
                // Overdue work already comes first; it doesn't need to be red as well.
                Label(DueBucket.of(todo.due) == .overdue ? "Carried over" : label == "Tomorrow" ? "Due tomorrow" : "Due \(label)",
                      systemImage: "calendar")
            }
            if let minutes = todo.minutes {
                Label(minutes.minutesString, systemImage: "clock")
            }
            if let nextStep {
                Label("Next step: \(nextStep.title)", systemImage: "arrow.turn.down.right")
                    .lineLimit(1)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(NonnaTheme.secondaryInk)
    }
}

/// After a few minutes of arranging tasks with no timer running, suggests starting one.
struct PlanningNudge: View {
    /// How long planning goes on before the nudge appears. It never shows the time itself:
    /// a number that keeps climbing reads as being watched.
    static let after: TimeInterval = 5 * 60

    let since: Date
    let suggestion: TodoItem?
    let onStart: (UUID) -> Void
    let onLater: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let elapsed = context.date.timeIntervalSince(since)
            if elapsed >= Self.after {
                banner
            }
        }
    }

    private var banner: some View {
        HStack(spacing: 14) {
            Image(systemName: "leaf")
                .font(.system(size: 15))
                .foregroundStyle(NonnaTheme.terracotta)
            VStack(alignment: .leading, spacing: 3) {
                Text("Ready when you are")
                    .font(.system(size: 13, weight: .semibold))
                Text(suggestion.map { "Your list is good enough. Start with “\($0.title)”?" } ?? "Your list is good enough. Time to start one.")
                    .font(.system(size: 12))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button("Not yet", action: onLater)
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(NonnaTheme.secondaryInk)
            if let suggestion {
                Button("Start") { onStart(suggestion.id) }
                    .buttonStyle(NonnaButtonStyle())
            }
        }
        .padding(16)
        .background(NonnaTheme.terracotta.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NonnaTheme.terracotta.opacity(0.3), lineWidth: 0.8) }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
