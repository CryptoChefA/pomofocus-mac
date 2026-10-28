import SwiftUI

/// "What's your focus?" as one control: type what you're doing (matching tasks appear as
/// you type), and underneath, the list it counts toward plus a couple of likely tasks to
/// link in one click.
struct FocusPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var showingNewList: Bool

    private var openTodos: [TodoItem] { model.todos.filter { !$0.isDone } }

    /// Tasks whose name matches what's typed, once there's enough to go on.
    private var matches: [TodoItem] {
        let text = model.intention.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { return [] }
        return openTodos
            .filter { $0.title.localizedCaseInsensitiveContains(text) && $0.title.caseInsensitiveCompare(text) != .orderedSame }
            .sorted(by: TodoItem.dueOrder)
            .prefix(4)
            .map { $0 }
    }

    /// The likeliest next tasks: planned around now, then due today, then this list's.
    private var suggestions: [TodoItem] {
        let calendar = Calendar.current
        let now = Date()
        func score(_ todo: TodoItem) -> Int {
            if let planned = todo.scheduledAt, calendar.isDateInToday(planned) {
                let minutes = Int(planned.timeIntervalSince(now) / 60)
                if minutes > -todo.plannedMinutes && minutes < 60 { return 0 }
                return minutes >= 60 ? 2 : 1
            }
            if DueBucket.of(todo.due).rawValue <= DueBucket.today.rawValue { return 1 }
            if todo.listID != nil, todo.listID == model.selectedTaskID { return 3 }
            return 9
        }
        return openTodos
            .map { ($0, score($0)) }
            .filter { $0.1 < 9 }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : TodoItem.dueOrder($0.0, $1.0) }
            .prefix(2)
            .map(\.0)
    }

    var body: some View {
        VStack(spacing: 10) {
            if model.selectedTodo != nil {
                // A linked task already says what this block is for.
                LinkedTodoControl(compact: true)
            } else {
                IntentionField(style: .pill)
                let matches = self.matches
                if !matches.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(matches) { todo in
                            matchRow(todo)
                            if todo.id != matches.last?.id {
                                Rectangle().fill(NonnaTheme.line.opacity(0.6)).frame(height: 0.8)
                            }
                        }
                    }
                    .background(NonnaTheme.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }
                    .frame(maxWidth: 460)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            HStack(spacing: 8) {
                listMenu
                if model.selectedTodo == nil, matches.isEmpty {
                    ForEach(suggestions) { todo in
                        suggestionChip(todo)
                    }
                    allTasksMenu
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: matches.map(\.id))
        .animation(reduceMotion ? nil : NonnaMotion.selection, value: model.selectedTodoID)
    }

    // MARK: Pieces

    private func tint(for todo: TodoItem) -> Color {
        model.data.tasks.first { $0.id == todo.listID }.map { NonnaTheme.taskColor(for: $0.colorHex) } ?? NonnaTheme.secondaryInk
    }

    private func matchRow(_ todo: TodoItem) -> some View {
        Button { model.linkTodo(todo.id) } label: {
            HStack(spacing: 10) {
                Circle().fill(tint(for: todo)).frame(width: 7, height: 7)
                Text(todo.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let minutes = todo.minutes {
                    Text("\(model.minutesLeft(on: todo).minutesString) of \(minutes.minutesString) left")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
                Image(systemName: "link")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Work on this task: its time counts toward it")
    }

    private func suggestionChip(_ todo: TodoItem) -> some View {
        Button { model.linkTodo(todo.id) } label: {
            HStack(spacing: 6) {
                Circle().fill(tint(for: todo)).frame(width: 6, height: 6)
                Text(todo.title)
                    .lineLimit(1)
                    .frame(maxWidth: 150, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                if todo.minutes != nil {
                    Text(model.minutesLeft(on: todo).minutesString)
                        .monospacedDigit()
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(NonnaTheme.paper, in: Capsule())
            .overlay { Capsule().stroke(NonnaTheme.line, lineWidth: 0.8) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(todo.scheduledAt.map { "Planned for \($0.formatted(date: .omitted, time: .shortened)). Click to work on it." } ?? "Click to work on this task")
    }

    private var listMenu: some View {
        Menu {
            ForEach(model.tasks) { task in
                Button {
                    model.selectList(task.id)
                } label: {
                    Label(task.name, systemImage: model.selectedTaskID == task.id ? "checkmark.circle.fill" : "circle.fill")
                }
            }
            Divider()
            Button("New list…") { showingNewList = true }
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(model.selectedTask.map { NonnaTheme.taskColor(for: $0.colorHex) } ?? NonnaTheme.secondaryInk)
                    .frame(width: 7, height: 7)
                Text(model.selectedTask?.name ?? "Choose a list")
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(NonnaTheme.raisedPaper, in: Capsule())
            .overlay { Capsule().stroke(NonnaTheme.strongLine, lineWidth: 0.8) }
            .contentShape(Capsule())
        }
        // The button style keeps the custom pill and colour dot; a borderless menu draws text only.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("The list this focus time counts toward")
    }

    private var allTasksMenu: some View {
        let open = openTodos.sorted(by: TodoItem.dueOrder)
        let soon = open.filter { DueBucket.of($0.due).rawValue <= DueBucket.today.rawValue }
        let rest = open.filter { DueBucket.of($0.due).rawValue > DueBucket.today.rawValue }
        return Menu {
            if open.isEmpty {
                Text("No open tasks yet. Add some in Tasks.")
            }
            if !soon.isEmpty {
                Section("Today") { ForEach(soon.prefix(12)) { item($0) } }
            }
            if !rest.isEmpty {
                Section("Later") { ForEach(rest.prefix(12)) { item($0) } }
            }
        } label: {
            HStack(spacing: 5) {
                Text(suggestions.isEmpty ? "Pick a task" : "More")
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(NonnaTheme.secondaryInk)
            .padding(.horizontal, 8)
            .frame(height: 32)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Link this focus block to any open task")
    }

    private func item(_ todo: TodoItem) -> some View {
        let left = todo.minutes.map { _ in ", \(model.minutesLeft(on: todo).minutesString) left" } ?? ""
        return Button("\(todo.title)\(left)") { model.linkTodo(todo.id) }
    }
}
