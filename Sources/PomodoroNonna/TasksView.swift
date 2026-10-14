import SwiftUI

// MARK: - Scope

/// What the Tasks screen is showing: a smart view across lists, or one list.
enum TaskScope: Hashable {
    case today, upcoming, all, completed
    case list(UUID)

    var defaultDue: Date? {
        switch self {
        case .today, .upcoming: Calendar.current.startOfDay(for: Date())
        default: nil
        }
    }
}

// MARK: - Tasks

struct TasksView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.compactLayout) private var compact
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scope: TaskScope = .today
    @AppStorage("pomofocus.tasksPageView") private var pageView = false
    @State private var showingNewList = false
    @State private var showsWriteItOut = false
    @State private var showsCompleted = false
    @State private var expandedID: UUID?
    /// The task just added without an estimate: the app asks how long it will take.
    @State private var estimatePromptID: UUID?

    var body: some View {
        HStack(spacing: 0) {
            if !compact {
                TaskSidebar(scope: $scope, onNewList: { showingNewList = true })
                    .frame(width: 236)
                Divider().overlay(NonnaTheme.line)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    statsStrip
                    QuickAddBar(scope: scope) { id, hasEstimate in
                        if !hasEstimate {
                            withAnimation(reduceMotion ? nil : NonnaMotion.selection) { estimatePromptID = id }
                        }
                    }
                    if let id = estimatePromptID, let todo = model.todos.first(where: { $0.id == id }) {
                        EstimatePrompt(todo: todo) {
                            withAnimation(reduceMotion ? nil : NonnaMotion.quick) { estimatePromptID = nil }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if pageView {
                        TaskPage(scope: scope, groups: groups)
                    } else {
                        listBody
                    }
                }
                .padding(30)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showingNewList) {
            NewTaskView().environment(model)
        }
        .sheet(isPresented: $showsWriteItOut) {
            WriteItOutSheet(scope: scope) { showsWriteItOut = false }
                .environment(model)
        }
        .onChange(of: scope) { _, _ in expandedID = nil }
    }

    // MARK: Header

    private var title: String {
        switch scope {
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .all: "All tasks"
        case .completed: "Completed"
        case .list(let id): model.tasks.first { $0.id == id }?.name ?? "List"
        }
    }

    private var subtitle: String {
        switch scope {
        case .today: Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
        case .upcoming: "Everything due this week"
        case .all: "Every open task, soonest first"
        case .completed: "Done and dusted"
        case .list(let id):
            if let total = model.analytics.taskTotals.first(where: { $0.taskID == id }), total.seconds > 0 {
                "\((total.seconds / 60).minutesString) focused across \(total.sessionCount) \(total.sessionCount == 1 ? "session" : "sessions"), all time"
            } else {
                "Nothing focused on this list yet"
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                if compact {
                    scopeMenu
                } else {
                    Text("TASKS")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.8)
                        .foregroundStyle(NonnaTheme.terracotta)
                }
                Text(title)
                    .font(.system(size: 29, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            Spacer()
            Picker("View", selection: $pageView) {
                Image(systemName: "list.bullet").tag(false).help("List")
                Image(systemName: "doc.plaintext").tag(true).help("Page: your tasks as a clean, notes-style page")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 92)
            Button {
                showsWriteItOut = true
            } label: {
                Label("Write it out", systemImage: "square.and.pencil")
            }
            .buttonStyle(NonnaButtonStyle(prominent: false))
            .help("Type or paste a whole list in plain text")
        }
    }

    private var scopeMenu: some View {
        Menu {
            Button("Today") { scope = .today }
            Button("Upcoming") { scope = .upcoming }
            Button("All tasks") { scope = .all }
            Button("Completed") { scope = .completed }
            Divider()
            ForEach(model.tasks) { list in
                Button(list.name) { scope = .list(list.id) }
            }
            Divider()
            Button("New list…") { showingNewList = true }
        } label: {
            Label("Lists", systemImage: "sidebar.left")
                .font(.system(size: 11, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: Stats

    private var openInScope: [TodoItem] { model.todos.filter { !$0.isDone && includes($0) } }

    private var statsStrip: some View {
        let open = scope == .completed ? [] : openInScope
        let estimated = open.reduce(0) { $0 + model.minutes(forPomodoros: $1.estimate ?? 0) }
        let unestimated = open.filter { $0.estimate == nil }.count
        let completedToday = model.todos.filter { $0.isDone && ($0.completedAt.map { Calendar.current.isDateInToday($0) } ?? false) && includes($0, ignoringDone: true) }.count
        let focused: Int = scope == .today
            ? model.todayRecordedFocusSeconds
            : model.todos.filter { includes($0, ignoringDone: true) }.reduce(0) { $0 + model.stats(for: $1.id).seconds }
        let goal = model.settings.dailyGoalMinutes

        return VStack(alignment: .leading, spacing: 10) {
            NonnaCard(padding: 0) {
                HStack(spacing: 0) {
                    stat(estimated.minutesString, "Estimated", detail: unestimated > 0 ? "\(unestimated) without an estimate" : nil)
                    divider
                    stat("\(open.count)", "To do")
                    divider
                    stat((focused / 60).minutesString, scope == .today ? "Focused today" : "Focused on these")
                    divider
                    stat("\(completedToday)", "Done today")
                }
                .padding(.vertical, 18)
            }
            if scope == .today, goal > 0, estimated > goal {
                Label("That's \(estimated.minutesString) planned against your \(goal.minutesString) daily goal. Consider moving something to tomorrow.", systemImage: "exclamationmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(NonnaTheme.gold)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(NonnaTheme.line).frame(width: 1, height: 44)
    }

    private func stat(_ value: String, _ label: String, detail: String? = nil) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 26, weight: .light))
                .monospacedDigit()
                .foregroundStyle(NonnaTheme.terracotta)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(NonnaTheme.secondaryInk)
            if let detail {
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(NonnaTheme.secondaryInk.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Filtering and grouping

    private func includes(_ todo: TodoItem, ignoringDone: Bool = false) -> Bool {
        let calendar = Calendar.current
        switch scope {
        case .today:
            guard let due = todo.due else { return false }
            return calendar.startOfDay(for: due) <= calendar.startOfDay(for: Date())
        case .upcoming:
            guard let due = todo.due else { return false }
            let limit = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: Date())) ?? Date()
            return due < limit
        case .all:
            return true
        case .completed:
            return todo.isDone
        case .list(let id):
            return todo.listID == id
        }
    }

    struct Group: Identifiable {
        let id: String
        let title: String
        let color: Color?
        let todos: [TodoItem]
        let defaultList: UUID?
        let defaultDue: Date?
    }

    private var groups: [Group] {
        let calendar = Calendar.current
        if scope == .completed {
            let done = model.todos.filter(\.isDone).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            return done.isEmpty ? [] : [Group(id: "done", title: "Completed", color: nil, todos: done, defaultList: nil, defaultDue: nil)]
        }
        let open = openInScope.sorted(by: TodoItem.dueOrder)
        switch scope {
        case .today:
            // Today reads best by subject, the way you'd write it out by hand.
            var result: [Group] = []
            for list in model.tasks {
                let items = open.filter { $0.listID == list.id }
                if !items.isEmpty {
                    result.append(Group(id: list.id.uuidString, title: list.name, color: NonnaTheme.taskColor(for: list.colorHex),
                                        todos: items, defaultList: list.id, defaultDue: scope.defaultDue))
                }
            }
            let loose = open.filter { todo in todo.listID == nil || !model.tasks.contains { $0.id == todo.listID } }
            if !loose.isEmpty {
                result.append(Group(id: "none", title: "No list", color: nil, todos: loose, defaultList: nil, defaultDue: scope.defaultDue))
            }
            return result
        case .upcoming:
            let byDay = Dictionary(grouping: open) { calendar.startOfDay(for: $0.due ?? Date()) }
            return byDay.keys.sorted().map { day in
                let label = TodoItem(title: "", due: day).dueLabel() ?? ""
                let title = DueBucket.of(day) == .overdue ? "Overdue · \(day.formatted(.dateTime.month(.abbreviated).day()))"
                    : "\(label) · \(day.formatted(.dateTime.weekday(.wide)))"
                return Group(id: "day-\(day.timeIntervalSince1970)", title: title, color: nil, todos: byDay[day] ?? [],
                             defaultList: nil, defaultDue: max(day, calendar.startOfDay(for: Date())))
            }
        default:
            let listID: UUID? = if case .list(let id) = scope { id } else { nil }
            let byBucket = Dictionary(grouping: open) { DueBucket.of($0.due) }
            return DueBucket.allCases.compactMap { bucket in
                guard let items = byBucket[bucket], !items.isEmpty else { return nil }
                let due: Date? = switch bucket {
                case .today, .overdue: calendar.startOfDay(for: Date())
                case .tomorrow: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))
                default: nil
                }
                return Group(id: "bucket-\(bucket.rawValue)", title: bucket.title, color: bucket == .overdue ? NonnaTheme.alert : nil,
                             todos: items, defaultList: listID, defaultDue: due)
            }
        }
    }

    // MARK: List view

    @ViewBuilder
    private var listBody: some View {
        let groups = groups
        if groups.isEmpty {
            NonnaCard {
                EmptyState(
                    icon: scope == .completed ? "checkmark.circle" : "checklist",
                    title: scope == .completed ? "Nothing finished yet" : "A clear slate",
                    message: scope == .completed
                        ? "Tasks you check off land here."
                        : "Add a task above. Try “Problem set 5 3p tomorrow”, or write out a whole list."
                )
            }
        } else {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 9) {
                        GroupHeader(group: group, showsCount: true)
                        ForEach(group.todos) { todo in
                            TodoRow(todo: todo, showsList: !isListScope && scope != .today, showsTodayLabel: scope != .today, isExpanded: expandedID == todo.id) {
                                withAnimation(reduceMotion ? nil : NonnaMotion.selection) {
                                    expandedID = expandedID == todo.id ? nil : todo.id
                                }
                            }
                        }
                    }
                }
            }
            .animation(reduceMotion ? nil : NonnaMotion.selection, value: model.todos)
        }

        if scope != .completed {
            let done = model.todos.filter { $0.isDone && includes($0, ignoringDone: true) && ($0.completedAt.map { Calendar.current.isDateInToday($0) } ?? false) }
            if !done.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Button {
                        withAnimation(reduceMotion ? nil : NonnaMotion.selection) { showsCompleted.toggle() }
                    } label: {
                        Label("\(showsCompleted ? "Hide" : "Show") \(done.count) done today", systemImage: showsCompleted ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                    }
                    .buttonStyle(.plain)
                    if showsCompleted {
                        ForEach(done) { todo in
                            TodoRow(todo: todo, showsList: !isListScope, isExpanded: false) {}
                        }
                    }
                }
            }
        }
    }

    private var isListScope: Bool { if case .list = scope { true } else { false } }
}

// MARK: - Sidebar

private struct TaskSidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var scope: TaskScope
    let onNewList: () -> Void
    @State private var renaming: UUID?
    @State private var renameText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                smart(.today, "Today", "sun.max")
                smart(.upcoming, "Upcoming", "calendar")
                smart(.all, "All tasks", "tray")
                smart(.completed, "Completed", "checkmark.circle")

                HStack {
                    Text("LISTS")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.6)
                        .foregroundStyle(NonnaTheme.secondaryInk)
                    Spacer()
                    Button(action: onNewList) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .help("New list")
                }
                .padding(.horizontal, 12)
                .padding(.top, 18)
                .padding(.bottom, 4)

                ForEach(model.tasks) { list in
                    if renaming == list.id {
                        TextField("List name", text: $renameText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(NonnaTheme.raisedPaper, in: RoundedRectangle(cornerRadius: 9))
                            .onSubmit {
                                model.renameList(list.id, to: renameText)
                                renaming = nil
                            }
                            .onExitCommand { renaming = nil }
                    } else {
                        row(scope: .list(list.id), title: list.name, color: NonnaTheme.taskColor(for: list.colorHex), icon: nil)
                            .contextMenu {
                                Button("Rename…") {
                                    renameText = list.name
                                    renaming = list.id
                                }
                                Button("Archive list", role: .destructive) {
                                    if scope == .list(list.id) { scope = .today }
                                    model.archiveTask(list.id)
                                }
                            }
                    }
                }
            }
            .padding(14)
        }
        .background(NonnaTheme.sunken.opacity(0.5))
    }

    private func smart(_ target: TaskScope, _ title: String, _ icon: String) -> some View {
        row(scope: target, title: title, color: nil, icon: icon)
    }

    private func row(scope target: TaskScope, title: String, color: Color?, icon: String?) -> some View {
        let open = model.todos.filter { todo in
            switch target {
            case .today: return !todo.isDone && (todo.due.map { Calendar.current.startOfDay(for: $0) <= Calendar.current.startOfDay(for: Date()) } ?? false)
            case .upcoming: return !todo.isDone && (todo.due.map { $0 < Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: Date()))! } ?? false)
            case .all: return !todo.isDone
            case .completed: return todo.isDone && (todo.completedAt.map { Calendar.current.isDateInToday($0) } ?? false)
            case .list(let id): return !todo.isDone && todo.listID == id
            }
        }
        let minutes = open.reduce(0) { $0 + model.minutes(forPomodoros: $1.estimate ?? 0) }
        let selected = scope == target
        return Button {
            withAnimation(NonnaMotion.quick) { scope = target }
        } label: {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .frame(width: 18)
                        .foregroundStyle(selected ? NonnaTheme.terracotta : NonnaTheme.secondaryInk)
                } else {
                    Circle().fill(color ?? NonnaTheme.secondaryInk).frame(width: 8, height: 8).frame(width: 18)
                }
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if target != .completed, minutes > 0 {
                    Text(minutes.minutesString)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
                if !open.isEmpty {
                    Text("\(open.count)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                        .frame(minWidth: 14, alignment: .trailing)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(selected ? NonnaTheme.raisedPaper : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                if selected { RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quick add

private struct QuickAddBar: View {
    @Environment(AppModel.self) private var model
    let scope: TaskScope
    /// The new task's id, and whether it already had an estimate.
    let onAdd: (UUID, Bool) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    private var target: String {
        switch scope {
        case .list(let id): "to \(model.tasks.first { $0.id == id }?.name ?? "this list")"
        case .today, .upcoming: "for today"
        default: ""
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NonnaTheme.terracotta)
            TextField("Add a task \(target)  ·  try “Problem set 5 3p tomorrow #Math”", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($focused)
                .onSubmit(add)
            if !text.isEmpty {
                Text("↩ to add")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .background(NonnaTheme.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(focused ? NonnaTheme.terracotta.opacity(0.6) : NonnaTheme.line, lineWidth: focused ? 1.2 : 0.8)
        }
    }

    private func add() {
        guard let parsed = TodoParser.parseLine(text, focusMinutes: model.settings.focusMinutes) else { return }
        let list: UUID? = if case .list(let id) = scope { id } else { nil }
        let id = model.addTodo(parsed, defaultList: list, defaultDue: scope.defaultDue)
        text = ""
        focused = true
        onAdd(id, parsed.estimate != nil)
    }
}

/// "How long will this take?" — shown right after adding a task without an estimate.
private struct EstimatePrompt: View {
    @Environment(AppModel.self) private var model
    let todo: TodoItem
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("How long will “\(todo.title)” take?")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Button("Skip", action: onDone)
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            EstimatePicker(estimate: todo.estimate) { value in
                model.updateTodo(todo.id) { $0.estimate = value }
                onDone()
            }
        }
        .padding(16)
        .background(NonnaTheme.terracotta.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NonnaTheme.terracotta.opacity(0.4), lineWidth: 0.8) }
    }
}

/// Pomodoro chips (1–8) and time chips (30m–3h), shown with what they add up to.
struct EstimatePicker: View {
    @Environment(AppModel.self) private var model
    let estimate: Int?
    let onPick: (Int?) -> Void
    @State private var hovered: Int?

    var body: some View {
        let focus = model.settings.focusMinutes
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                ForEach(1...8, id: \.self) { count in
                    chip(selected: estimate == count) {
                        HStack(spacing: 3) {
                            Text("🍅").font(.system(size: 10))
                            Text("\(count)").font(.system(size: 12, weight: .semibold, design: .monospaced))
                        }
                    } action: { onPick(count) }
                    .onHover { hovered = $0 ? count : (hovered == count ? nil : hovered) }
                }
            }
            HStack(spacing: 6) {
                ForEach([30, 60, 90, 120, 180], id: \.self) { minutes in
                    let count = max(1, Int((Double(minutes) / Double(max(1, focus))).rounded(.up)))
                    chip(selected: false) {
                        Text(minutes.minutesString).font(.system(size: 12, weight: .medium))
                    } action: { onPick(count) }
                    .onHover { hovered = $0 ? count : (hovered == count ? nil : hovered) }
                }
                if estimate != nil {
                    chip(selected: false) {
                        Text("Clear").font(.system(size: 12)).foregroundStyle(NonnaTheme.secondaryInk)
                    } action: { onPick(nil) }
                }
                Spacer(minLength: 8)
                Group {
                    if let shown = hovered ?? estimate {
                        Text("\(shown) × \(focus) min = \((shown * focus).minutesString)")
                    } else {
                        Text("1 🍅 = \(focus) min")
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(NonnaTheme.secondaryInk)
            }
        }
    }

    private func chip<Label: View>(selected: Bool, @ViewBuilder label: () -> Label, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label()
                .padding(.horizontal, 10)
                .frame(height: 28)
                .foregroundStyle(selected ? NonnaTheme.onAccent : NonnaTheme.ink)
                .background(selected ? NonnaTheme.terracotta : NonnaTheme.raisedPaper, in: Capsule())
                .overlay { Capsule().stroke(selected ? .clear : NonnaTheme.line, lineWidth: 0.8) }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Rows

private struct GroupHeader: View {
    let group: TasksView.Group
    var showsCount = false
    @Environment(AppModel.self) private var model

    var body: some View {
        let minutes = group.todos.reduce(0) { $0 + model.minutes(forPomodoros: $1.estimate ?? 0) }
        HStack(spacing: 8) {
            if let color = group.color {
                Circle().fill(color).frame(width: 7, height: 7)
            }
            Text(group.title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(group.color == NonnaTheme.alert ? NonnaTheme.alert : NonnaTheme.secondaryInk)
            if minutes > 0 {
                Text("· \(minutes.minutesString)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(NonnaTheme.secondaryInk.opacity(0.8))
            }
            Spacer()
        }
        .padding(.leading, 4)
    }
}

/// Small tomato meter: filled for blocks done, hollow for what's left of the estimate.
struct PomodoroMeter: View {
    let done: Int
    let estimate: Int?
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            if let estimate {
                HStack(spacing: 3) {
                    ForEach(0..<min(max(estimate, done), 10), id: \.self) { index in
                        Circle()
                            .fill(index < done ? tint : .clear)
                            .overlay { Circle().stroke(index < estimate ? tint.opacity(0.75) : NonnaTheme.alert.opacity(0.7), lineWidth: 1) }
                            .frame(width: 7, height: 7)
                    }
                }
                Text("\(done)/\(estimate)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            } else if done > 0 {
                Text("🍅 \(done)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
        }
    }
}

private struct TodoRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let todo: TodoItem
    let showsList: Bool
    var showsTodayLabel = true
    let isExpanded: Bool
    let onTap: () -> Void
    @State private var hovering = false

    private var list: FocusTask? { model.data.tasks.first { $0.id == todo.listID } }
    private var tint: Color { list.map { NonnaTheme.taskColor(for: $0.colorHex) } ?? NonnaTheme.terracotta }
    private var isCurrent: Bool { model.selectedTodoID == todo.id && model.status != .idle }

    var body: some View {
        let stats = model.stats(for: todo.id)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                CheckCircle(isDone: todo.isDone, tint: tint) {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.3)) { model.toggleDone(todo.id) }
                }
                if !todo.isDone {
                    Button {
                        if model.status == .idle { model.startFocus(on: todo.id) } else { model.linkTodo(todo.id) }
                    } label: {
                        Image(systemName: isCurrent ? "waveform" : "play.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(isCurrent ? NonnaTheme.onAccent : tint)
                            .frame(width: 24, height: 24)
                            .background(isCurrent ? tint : tint.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(model.status == .idle ? "Start a focus block on this task" : "Work on this task next")
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(todo.title)
                        .font(.system(size: 14, weight: .medium))
                        .strikethrough(todo.isDone, color: NonnaTheme.secondaryInk)
                        .foregroundStyle(todo.isDone ? NonnaTheme.secondaryInk : NonnaTheme.ink)
                        .lineLimit(2)
                    HStack(spacing: 10) {
                        if todo.estimate != nil || stats.blocks > 0 {
                            PomodoroMeter(done: stats.blocks, estimate: todo.estimate, tint: tint)
                        }
                        if todo.estimate == nil, stats.blocks == 0, !todo.isDone {
                            Text("No estimate")
                                .font(.system(size: 10))
                                .foregroundStyle(NonnaTheme.secondaryInk.opacity(0.7))
                        }
                        if showsList, let list {
                            HStack(spacing: 4) {
                                Circle().fill(tint).frame(width: 5, height: 5)
                                Text(list.name).font(.system(size: 10)).foregroundStyle(NonnaTheme.secondaryInk)
                            }
                        }
                        if !todo.notes.isEmpty {
                            Image(systemName: "note.text").font(.system(size: 9)).foregroundStyle(NonnaTheme.secondaryInk)
                        }
                    }
                }
                Spacer(minLength: 8)
                if let label = todo.dueLabel(), showsTodayLabel || DueBucket.of(todo.due) != .today {
                    let bucket = DueBucket.of(todo.due)
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(todo.isDone ? NonnaTheme.secondaryInk : bucket == .overdue ? NonnaTheme.alert : bucket == .today ? NonnaTheme.terracotta : NonnaTheme.secondaryInk)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)

            if isExpanded {
                TodoEditor(todo: todo)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(hovering || isExpanded ? NonnaTheme.raisedPaper : NonnaTheme.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isCurrent ? tint.opacity(0.7) : NonnaTheme.line, lineWidth: isCurrent ? 1.2 : 0.8)
        }
        .onHover { hovering = $0 }
        .animation(NonnaMotion.quick, value: hovering)
        .contextMenu { TodoMenu(todo: todo) }
    }
}

private struct CheckCircle: View {
    let isDone: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(isDone ? tint : NonnaTheme.strongLine, lineWidth: 1.5)
                if isDone {
                    Circle().fill(tint)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(NonnaTheme.onAccent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 20, height: 20)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isDone ? "Mark as not done" : "Mark as done")
    }
}

private struct TodoMenu: View {
    @Environment(AppModel.self) private var model
    let todo: TodoItem

    var body: some View {
        if !todo.isDone {
            Button("Start focus on this") { model.startFocus(on: todo.id) }
                .disabled(model.status != .idle)
        }
        Button(todo.isDone ? "Mark as not done" : "Mark as done") { model.toggleDone(todo.id) }
        Divider()
        Menu("Due") {
            let today = Calendar.current.startOfDay(for: Date())
            Button("Today") { model.updateTodo(todo.id) { $0.due = today } }
            Button("Tomorrow") { model.updateTodo(todo.id) { $0.due = Calendar.current.date(byAdding: .day, value: 1, to: today) } }
            Button("Next week") { model.updateTodo(todo.id) { $0.due = Calendar.current.date(byAdding: .day, value: 7, to: today) } }
            Button("No date") { model.updateTodo(todo.id) { $0.due = nil } }
        }
        Menu("Estimate") {
            ForEach(1...8, id: \.self) { count in
                Button("\(count) 🍅 · \(model.minutes(forPomodoros: count).minutesString)") { model.updateTodo(todo.id) { $0.estimate = count } }
            }
            Button("No estimate") { model.updateTodo(todo.id) { $0.estimate = nil } }
        }
        Menu("Move to list") {
            ForEach(model.tasks) { list in
                Button(list.name) { model.updateTodo(todo.id) { $0.listID = list.id } }
            }
        }
        Divider()
        Button("Delete", role: .destructive) { model.deleteTodo(todo.id) }
    }
}

/// Inline editor shown when a task is expanded.
private struct TodoEditor: View {
    @Environment(AppModel.self) private var model
    let todo: TodoItem
    @State private var title = ""
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider().overlay(NonnaTheme.line)
            VStack(alignment: .leading, spacing: 7) {
                label("Rename")
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(NonnaTheme.sunken, in: RoundedRectangle(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(NonnaTheme.line, lineWidth: 0.8) }
                        .onSubmit { model.updateTodo(todo.id) { $0.title = title.trimmingCharacters(in: .whitespaces).isEmpty ? $0.title : title } }
            }

            VStack(alignment: .leading, spacing: 7) {
                label("How long")
                EstimatePicker(estimate: todo.estimate) { value in model.updateTodo(todo.id) { $0.estimate = value } }
            }

            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    label("Due")
                    HStack(spacing: 6) {
                        let today = Calendar.current.startOfDay(for: Date())
                        dueChip("Today", today)
                        dueChip("Tomorrow", Calendar.current.date(byAdding: .day, value: 1, to: today))
                        dueChip("Next week", Calendar.current.date(byAdding: .day, value: 7, to: today))
                        dueChip("None", nil)
                        DatePicker("", selection: Binding(
                            get: { todo.due ?? today },
                            set: { date in model.updateTodo(todo.id) { $0.due = Calendar.current.startOfDay(for: date) } }
                        ), displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .fixedSize()
                        .help("Pick a date")
                    }
                }
                VStack(alignment: .leading, spacing: 7) {
                    label("List")
                    Menu {
                        ForEach(model.tasks) { list in
                            Button(list.name) { model.updateTodo(todo.id) { $0.listID = list.id } }
                        }
                        Button("No list") { model.updateTodo(todo.id) { $0.listID = nil } }
                    } label: {
                        Text(model.tasks.first { $0.id == todo.listID }?.name ?? "No list")
                            .font(.system(size: 12))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                label("Notes")
                TextEditor(text: $notes)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 70)
                    .background(NonnaTheme.sunken, in: RoundedRectangle(cornerRadius: 9))
                    .overlay { RoundedRectangle(cornerRadius: 9).stroke(NonnaTheme.line, lineWidth: 0.8) }
                    .onChange(of: notes) { _, value in model.updateTodo(todo.id) { $0.notes = value } }
            }

            HStack {
                let stats = model.stats(for: todo.id)
                if stats.seconds > 0 {
                    Text("\(stats.blocks) \(stats.blocks == 1 ? "block" : "blocks") · \((stats.seconds / 60).minutesString) focused so far")
                        .font(.system(size: 11))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
                Spacer()
                Button(role: .destructive) {
                    model.deleteTodo(todo.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(NonnaTheme.alert.opacity(0.85))
            }
        }
        .onAppear {
            title = todo.title
            notes = todo.notes
        }
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(NonnaTheme.secondaryInk)
    }

    private func dueChip(_ title: String, _ date: Date?) -> some View {
        let selected = todo.due.map { d in date.map { Calendar.current.isDate(d, inSameDayAs: $0) } ?? false } ?? (date == nil)
        return Button(title) { model.updateTodo(todo.id) { $0.due = date } }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: selected ? .semibold : .regular))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .foregroundStyle(selected ? NonnaTheme.onAccent : NonnaTheme.ink)
            .background(selected ? NonnaTheme.terracotta : NonnaTheme.raisedPaper, in: Capsule())
            .overlay { Capsule().stroke(selected ? .clear : NonnaTheme.line, lineWidth: 0.8) }
    }
}

// MARK: - Page view

/// Tasks as one clean page, the way you'd write them in your notes: headings, lines you
/// can tick, and a line at the end of each section to keep writing.
private struct TaskPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let scope: TaskScope
    let groups: [TasksView.Group]

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 4) {
                Text(pageTitle)
                    .font(.system(size: 30, weight: .regular, design: .serif))
                let total = groups.flatMap(\.todos).reduce(0) { $0 + model.minutes(forPomodoros: $1.estimate ?? 0) }
                Text("\(groups.flatMap(\.todos).count) tasks\(total > 0 ? " · about \(total.minutesString)" : "")")
                    .font(.system(size: 12))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            if groups.isEmpty {
                Text("Nothing here yet. Start writing below, or use Write it out to paste a whole list.")
                    .font(.system(size: 14, design: .serif))
                    .italic()
                    .foregroundStyle(NonnaTheme.secondaryInk)
                PageAddLine(defaultList: listID, defaultDue: scope.defaultDue)
            }
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if let color = group.color { Circle().fill(color).frame(width: 8, height: 8) }
                        Text(group.title)
                            .font(.system(size: 17, weight: .semibold, design: .serif))
                            .foregroundStyle(group.color == NonnaTheme.alert ? NonnaTheme.alert : NonnaTheme.ink)
                        let minutes = group.todos.reduce(0) { $0 + model.minutes(forPomodoros: $1.estimate ?? 0) }
                        if minutes > 0 {
                            Text(minutes.minutesString)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(NonnaTheme.secondaryInk)
                        }
                    }
                    .padding(.bottom, 6)
                    ForEach(group.todos) { todo in
                        PageLine(todo: todo)
                    }
                    PageAddLine(defaultList: group.defaultList ?? listID, defaultDue: group.defaultDue)
                }
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 36)
        .frame(maxWidth: 760, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(NonnaTheme.paper)
                .shadow(color: NonnaTheme.shadow, radius: 24, y: 12)
        }
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : NonnaMotion.selection, value: model.todos)
    }

    private var listID: UUID? { if case .list(let id) = scope { id } else { nil } }

    private var pageTitle: String {
        switch scope {
        case .today: Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
        case .upcoming: "This week"
        case .all: "Everything"
        case .completed: "Done"
        case .list(let id): model.tasks.first { $0.id == id }?.name ?? "List"
        }
    }
}

private struct PageLine: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let todo: TodoItem
    @State private var hovering = false

    var body: some View {
        let list = model.data.tasks.first { $0.id == todo.listID }
        let tint = list.map { NonnaTheme.taskColor(for: $0.colorHex) } ?? NonnaTheme.terracotta
        let stats = model.stats(for: todo.id)
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button {
                withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.3)) { model.toggleDone(todo.id) }
            } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(todo.isDone ? tint : NonnaTheme.strongLine)
            }
            .buttonStyle(.plain)
            Text(todo.title)
                .font(.system(size: 15))
                .strikethrough(todo.isDone, color: NonnaTheme.secondaryInk)
                .foregroundStyle(todo.isDone ? NonnaTheme.secondaryInk : NonnaTheme.ink)
            Spacer(minLength: 12)
            if hovering, !todo.isDone, model.status == .idle {
                Button {
                    model.startFocus(on: todo.id)
                } label: {
                    Image(systemName: "play.fill").font(.system(size: 9)).foregroundStyle(tint)
                }
                .buttonStyle(.plain)
                .help("Start a focus block on this task")
            }
            HStack(spacing: 6) {
                if let estimate = todo.estimate {
                    Text("🍅 \(stats.blocks)/\(estimate)")
                } else if stats.blocks > 0 {
                    Text("🍅 \(stats.blocks)")
                }
                if let due = todo.dueLabel(), DueBucket.of(todo.due) != .today {
                    Text(due).foregroundStyle(DueBucket.of(todo.due) == .overdue ? NonnaTheme.alert : NonnaTheme.secondaryInk)
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(NonnaTheme.secondaryInk)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(hovering ? NonnaTheme.raisedPaper.opacity(0.7) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .onHover { hovering = $0 }
        .contextMenu { TodoMenu(todo: todo) }
    }
}

private struct PageAddLine: View {
    @Environment(AppModel.self) private var model
    let defaultList: UUID?
    let defaultDue: Date?
    @State private var text = ""

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.system(size: 11))
                .foregroundStyle(NonnaTheme.secondaryInk.opacity(0.6))
            TextField("Add a line…", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .onSubmit {
                    guard let parsed = TodoParser.parseLine(text, focusMinutes: model.settings.focusMinutes) else { return }
                    model.addTodo(parsed, defaultList: defaultList, defaultDue: defaultDue)
                    text = ""
                }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }
}

// MARK: - Write it out

/// A plain-text pad: write or paste a whole list the way you'd do it in Notes, see it
/// parsed live, and add everything in one go.
private struct WriteItOutSheet: View {
    @Environment(AppModel.self) private var model
    let scope: TaskScope
    let onDone: () -> Void
    @State private var text = ""

    private var parsed: [ParsedTodo] {
        TodoParser.parseDocument(text, focusMinutes: model.settings.focusMinutes)
    }

    private var defaultList: UUID? { if case .list(let id) = scope { id } else { nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("WRITE IT OUT")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(NonnaTheme.terracotta)
                    Text("Get it all out of your head.")
                        .font(.system(size: 26, weight: .regular, design: .serif))
                    Text("One task per line. Headings like “Math:” become lists. Add “3p” or “1h” for an estimate, and “today”, “tomorrow” or a weekday for a due date.")
                        .font(.system(size: 12))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(28)

            HStack(alignment: .top, spacing: 18) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Math:\n- Make formula sheet 2p today\n- Problem set 5 3p tomorrow\n\nBio:\n- Read chapter 4 1h fri\n- Practice midterm 4p")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(NonnaTheme.secondaryInk.opacity(0.5))
                            .padding(.horizontal, 15)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(.system(size: 14, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NonnaTheme.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PREVIEW · \(parsed.count) \(parsed.count == 1 ? "TASK" : "TASKS")")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(1.6)
                            .foregroundStyle(NonnaTheme.secondaryInk)
                        ForEach(Array(parsed.enumerated()), id: \.offset) { _, item in
                            preview(item)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 290)
            }
            .padding(.horizontal, 28)
            .frame(maxHeight: .infinity)

            HStack {
                Button("Cancel", action: onDone)
                    .buttonStyle(NonnaButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    model.addTodos(parsed, defaultList: defaultList, defaultDue: scope.defaultDue)
                    onDone()
                } label: {
                    Label(parsed.isEmpty ? "Add tasks" : "Add \(parsed.count) \(parsed.count == 1 ? "task" : "tasks")", systemImage: "checklist")
                }
                .buttonStyle(NonnaButtonStyle())
                .disabled(parsed.isEmpty)
                .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding(28)
        }
        .frame(width: 820, height: 620)
        .background(NonnaTheme.cream)
        .foregroundStyle(NonnaTheme.ink)
        .preferredColorScheme(NonnaTheme.colorScheme)
    }

    private func preview(_ item: ParsedTodo) -> some View {
        let existing = item.listName.flatMap { name in model.tasks.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } }
        return VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.system(size: 13, weight: .medium))
                .strikethrough(item.isDone)
            HStack(spacing: 8) {
                if let name = item.listName {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(existing.map { NonnaTheme.taskColor(for: $0.colorHex) } ?? NonnaTheme.secondaryInk)
                            .frame(width: 5, height: 5)
                        Text(existing == nil ? "\(name) (new list)" : name)
                    }
                }
                if let estimate = item.estimate {
                    Text("🍅 \(estimate) · \(model.minutes(forPomodoros: estimate).minutesString)")
                }
                if let due = item.due {
                    Text(TodoItem(title: "", due: due).dueLabel() ?? "")
                }
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(NonnaTheme.secondaryInk)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NonnaTheme.paper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }
    }
}

// MARK: - Timer link

/// On the timer: the task this block is for, with its progress, or a menu to pick one.
struct LinkedTodoControl: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var compact = false

    var body: some View {
        Group {
            if let todo = model.selectedTodo {
                linked(todo)
            } else {
                picker
            }
        }
        .animation(reduceMotion ? nil : NonnaMotion.selection, value: model.selectedTodoID)
    }

    private func linked(_ todo: TodoItem) -> some View {
        let list = model.data.tasks.first { $0.id == todo.listID }
        let tint = list.map { NonnaTheme.taskColor(for: $0.colorHex) } ?? NonnaTheme.terracotta
        let stats = model.stats(for: todo.id)
        return HStack(spacing: 10) {
            Button {
                withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.3)) { model.toggleDone(todo.id) }
            } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(todo.isDone ? tint : NonnaTheme.strongLine)
            }
            .buttonStyle(.plain)
            .help(todo.isDone ? "Mark as not done" : "Mark this task as done")
            VStack(alignment: .leading, spacing: 3) {
                Text("WORKING ON")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(tint)
                Text(todo.title)
                    .font(.system(size: 12, weight: .medium))
                    .strikethrough(todo.isDone, color: NonnaTheme.secondaryInk)
                    .lineLimit(1)
            }
            if !compact || todo.estimate != nil {
                PomodoroMeter(done: stats.blocks, estimate: todo.estimate, tint: tint)
            }
            Button {
                model.unlinkTodo()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .frame(width: 20, height: 20)
                    .background(NonnaTheme.sunken, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Stop working on this task")
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: 44)
        .background(NonnaTheme.raisedPaper, in: Capsule())
        .overlay { Capsule().stroke(tint.opacity(0.45), lineWidth: 0.9) }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private var picker: some View {
        let open = model.todos.filter { !$0.isDone }.sorted(by: TodoItem.dueOrder)
        let soon = open.filter { DueBucket.of($0.due).rawValue <= DueBucket.today.rawValue }
        let rest = open.filter { DueBucket.of($0.due).rawValue > DueBucket.today.rawValue }
        return Menu {
            if open.isEmpty {
                Text("No open tasks. Add some in Tasks.")
            }
            if !soon.isEmpty {
                Section("Today") { ForEach(soon.prefix(12)) { item($0) } }
            }
            if !rest.isEmpty {
                Section("Later") { ForEach(rest.prefix(12)) { item($0) } }
            }
        } label: {
            Label("Pick a task", systemImage: "checklist")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NonnaTheme.secondaryInk)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Link this focus block to a task so it counts toward its estimate")
    }

    private func item(_ todo: TodoItem) -> some View {
        let stats = model.stats(for: todo.id)
        let progress = todo.estimate.map { " · \(stats.blocks)/\($0) 🍅" } ?? ""
        return Button("\(todo.title)\(progress)") { model.linkTodo(todo.id) }
    }
}
