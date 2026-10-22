import SwiftUI

// MARK: - Scope

/// What the Tasks screen is showing: every list as a board, a smart view, or one list.
enum TaskScope: Hashable {
    case board, today, upcoming, completed
    case list(UUID)

    var defaultDue: Date? {
        switch self {
        case .today: Calendar.current.startOfDay(for: Date())
        default: nil
        }
    }

    var listID: UUID? { if case .list(let id) = self { id } else { nil } }
}

/// The lengths offered wherever the app asks how long something will take.
enum TaskLength {
    static let choices = [15, 30, 45, 60, 90, 120, 180]
}

// MARK: - Tasks

struct TasksView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.compactLayout) private var compact
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scope: TaskScope = .board
    @State private var showingNewList = false
    @State private var showsWriteItOut = false
    @State private var showsNewTask = false
    @State private var showsCompleted = false
    @State private var expandedID: UUID?
    /// The task just added without a length: the app asks how long it will take.
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
                    if scope == .board {
                        BoardView(onNewList: { showingNewList = true })
                    } else {
                        if scope != .completed {
                            QuickAddBar(scope: scope) { id, hasLength in
                                if !hasLength {
                                    withAnimation(reduceMotion ? nil : NonnaMotion.selection) { estimatePromptID = id }
                                }
                            }
                        }
                        if let id = estimatePromptID, let todo = model.todos.first(where: { $0.id == id }) {
                            EstimatePrompt(todo: todo) {
                                withAnimation(reduceMotion ? nil : NonnaMotion.quick) { estimatePromptID = nil }
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        listBody
                    }
                }
                .padding(30)
                .frame(maxWidth: scope == .board ? 1240 : 980, alignment: .leading)
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
        .sheet(isPresented: $showsNewTask) {
            NewTodoSheet(listID: scope.listID ?? model.tasks.first?.id, due: scope.defaultDue) { showsNewTask = false }
                .environment(model)
        }
        .onChange(of: scope) { _, _ in
            expandedID = nil
            estimatePromptID = nil
        }
    }

    // MARK: Header

    private var title: String {
        switch scope {
        case .board: "All lists"
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .completed: "Completed"
        case .list(let id): model.tasks.first { $0.id == id }?.name ?? "List"
        }
    }

    private var subtitle: String {
        switch scope {
        case .board: "Every list and what’s left in it"
        case .today: Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
        case .upcoming: "Everything due in the next week"
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
        HStack(alignment: .bottom, spacing: 10) {
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
            Button {
                showsWriteItOut = true
            } label: {
                Label("Paste a list", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(NonnaButtonStyle(prominent: false))
            .help("Paste or type a whole list from your notes and add it all at once")
            Button {
                showsNewTask = true
            } label: {
                Label("New task", systemImage: "plus")
            }
            .buttonStyle(NonnaButtonStyle())
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .help("Add a task (⇧⌘N)")
        }
    }

    private var scopeMenu: some View {
        Menu {
            Button("All lists") { scope = .board }
            Button("Today") { scope = .today }
            Button("Upcoming") { scope = .upcoming }
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
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: Stats

    private var openInScope: [TodoItem] { model.todos.filter { !$0.isDone && includes($0) } }

    private var statsStrip: some View {
        let open = scope == .completed ? [] : openInScope
        let left = open.reduce(0) { $0 + model.minutesLeft(on: $1) }
        let unestimated = open.filter { $0.minutes == nil }.count
        let completedToday = model.todos.filter { $0.isDone && ($0.completedAt.map { Calendar.current.isDateInToday($0) } ?? false) && includes($0, ignoringDone: true) }.count
        let showsToday = scope == .today || scope == .board
        let focused: Int = showsToday
            ? model.todayRecordedFocusSeconds
            : model.todos.filter { includes($0, ignoringDone: true) }.reduce(0) { $0 + model.stats(for: $1.id).seconds }
        let goal = model.settings.dailyGoalMinutes

        return VStack(alignment: .leading, spacing: 10) {
            NonnaCard(padding: 0) {
                HStack(spacing: 0) {
                    stat("\(open.count)", "To do")
                    divider
                    stat(left.minutesString, "Time needed", detail: unestimated > 0 ? "\(unestimated) not timed yet" : nil)
                    divider
                    stat((focused / 60).minutesString, showsToday ? "Focused today" : "Focused on these")
                    divider
                    stat("\(completedToday)", "Done today")
                }
                .padding(.vertical, 18)
            }
            if scope == .today, goal > 0, left > goal {
                Label("That’s \(left.minutesString) of work against your \(goal.minutesString) daily goal. Maybe move something to tomorrow.", systemImage: "exclamationmark.circle")
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
        case .board:
            return true
        case .today:
            guard let due = todo.due else { return false }
            return calendar.startOfDay(for: due) <= calendar.startOfDay(for: Date())
        case .upcoming:
            guard let due = todo.due else { return false }
            let limit = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: Date())) ?? Date()
            return due < limit
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
    }

    private var groups: [Group] {
        let calendar = Calendar.current
        if scope == .completed {
            let done = model.todos.filter(\.isDone).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            return done.isEmpty ? [] : [Group(id: "done", title: "Completed", color: nil, todos: done)]
        }
        let open = openInScope.sorted(by: TodoItem.dueOrder)
        switch scope {
        case .today:
            // Today reads best by subject, the way you'd write it out by hand.
            var result: [Group] = []
            for list in model.tasks {
                let items = open.filter { $0.listID == list.id }
                if !items.isEmpty {
                    result.append(Group(id: list.id.uuidString, title: list.name, color: NonnaTheme.taskColor(for: list.colorHex), todos: items))
                }
            }
            let loose = open.filter { todo in todo.listID == nil || !model.tasks.contains { $0.id == todo.listID } }
            if !loose.isEmpty {
                result.append(Group(id: "none", title: "No list", color: nil, todos: loose))
            }
            return result
        case .upcoming:
            let byDay = Dictionary(grouping: open) { calendar.startOfDay(for: $0.due ?? Date()) }
            return byDay.keys.sorted().map { day in
                let label = TodoItem(title: "", due: day).dueLabel() ?? ""
                let title = DueBucket.of(day) == .overdue ? "Overdue · \(day.formatted(.dateTime.month(.abbreviated).day()))"
                    : "\(label) · \(day.formatted(.dateTime.weekday(.wide)))"
                return Group(id: "day-\(day.timeIntervalSince1970)", title: title, color: nil, todos: byDay[day] ?? [])
            }
        default:
            let byBucket = Dictionary(grouping: open) { DueBucket.of($0.due) }
            return DueBucket.allCases.compactMap { bucket in
                guard let items = byBucket[bucket], !items.isEmpty else { return nil }
                return Group(id: "bucket-\(bucket.rawValue)", title: bucket.title, color: bucket == .overdue ? NonnaTheme.alert : nil, todos: items)
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
                    message: scope == .completed ? "Tasks you check off land here." : "Type a task above and press Return."
                )
            }
        } else {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 9) {
                        GroupHeader(group: group)
                        ForEach(group.todos) { todo in
                            TodoRow(todo: todo, showsList: scope.listID == nil && scope != .today,
                                    showsTodayLabel: scope != .today, isExpanded: expandedID == todo.id) {
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
                            TodoRow(todo: todo, showsList: scope.listID == nil, isExpanded: false) {}
                        }
                    }
                }
            }
        }
    }
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
                row(scope: .board, title: "All lists", color: nil, icon: "square.grid.2x2")
                row(scope: .today, title: "Today", color: nil, icon: "sun.max")
                row(scope: .upcoming, title: "Upcoming", color: nil, icon: "calendar")
                row(scope: .completed, title: "Completed", color: nil, icon: "checkmark.circle")

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
                                    if scope == .list(list.id) { scope = .board }
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

    private func row(scope target: TaskScope, title: String, color: Color?, icon: String?) -> some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekOut = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        let open = model.todos.filter { todo in
            switch target {
            case .board: return !todo.isDone
            case .today: return !todo.isDone && (todo.due.map { calendar.startOfDay(for: $0) <= today } ?? false)
            case .upcoming: return !todo.isDone && (todo.due.map { $0 < weekOut } ?? false)
            case .completed: return todo.isDone && (todo.completedAt.map { calendar.isDateInToday($0) } ?? false)
            case .list(let id): return !todo.isDone && todo.listID == id
            }
        }
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
                if !open.isEmpty {
                    Text("\(open.count)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(NonnaTheme.secondaryInk)
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

// MARK: - Adding

/// The short form behind "New task": what, which list, how long, and when.
private struct NewTodoSheet: View {
    @Environment(AppModel.self) private var model
    @State private var title = ""
    @State private var listID: UUID?
    @State private var minutes: Int?
    @State private var due: Date?
    @FocusState private var focused: Bool
    let onDone: () -> Void

    init(listID: UUID?, due: Date?, onDone: @escaping () -> Void) {
        _listID = State(initialValue: listID)
        _due = State(initialValue: due)
        self.onDone = onDone
    }

    private var trimmed: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("New task")
                .font(.system(size: 24, weight: .regular, design: .serif))

            TextField("What do you need to do?", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(NonnaTheme.paper, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(NonnaTheme.terracotta.opacity(0.5), lineWidth: 1) }
                .focused($focused)
                .onSubmit(add)

            field("List") {
                FlowChips {
                    ForEach(model.tasks) { list in
                        PillButton(title: list.name, dot: NonnaTheme.taskColor(for: list.colorHex), selected: listID == list.id) {
                            listID = listID == list.id ? nil : list.id
                        }
                    }
                }
            }

            field("How long will it take?") {
                LengthChips(selected: minutes) { minutes = $0 }
            }

            field("When is it due?") {
                DueChips(selected: due) { due = $0 }
            }

            HStack {
                Button("Cancel", action: onDone)
                    .buttonStyle(NonnaButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add task", action: add)
                    .buttonStyle(NonnaButtonStyle())
                    .disabled(trimmed.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 540)
        .background(NonnaTheme.cream)
        .foregroundStyle(NonnaTheme.ink)
        .preferredColorScheme(NonnaTheme.colorScheme)
        .onAppear {
            focused = true
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NonnaTheme.secondaryInk)
            content()
        }
    }

    private func add() {
        guard !trimmed.isEmpty else { return }
        // Typed shortcuts like "1h" or "tomorrow" still work; the picks win when made.
        let parsed = TodoParser.parseLine(trimmed, focusMinutes: model.settings.focusMinutes)
        model.addTodo(title: parsed?.title ?? trimmed, listID: listID, minutes: minutes ?? parsed?.minutes, due: due ?? parsed?.due)
        onDone()
    }
}

/// A plain "Add a task" line: type and press Return.
private struct QuickAddBar: View {
    @Environment(AppModel.self) private var model
    let scope: TaskScope
    /// The new task's id, and whether it already has a length.
    let onAdd: (UUID, Bool) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NonnaTheme.terracotta)
            TextField("Add a task", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($focused)
                .onSubmit(add)
            if !text.isEmpty {
                Text("Return to add")
                    .font(.system(size: 10))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 50)
        .background(NonnaTheme.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(focused ? NonnaTheme.terracotta.opacity(0.6) : NonnaTheme.line, lineWidth: focused ? 1.2 : 0.8)
        }
    }

    private func add() {
        guard let parsed = TodoParser.parseLine(text, focusMinutes: model.settings.focusMinutes) else { return }
        let id = model.addTodo(parsed, defaultList: scope.listID, defaultDue: scope.defaultDue)
        text = ""
        focused = true
        onAdd(id, parsed.minutes != nil)
    }
}

/// "How long will this take?" — asked right after adding a task without a length.
private struct EstimatePrompt: View {
    @Environment(AppModel.self) private var model
    let todo: TodoItem
    var compact = false
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(compact ? "How long will this take?" : "How long will “\(todo.title)” take?")
                    .font(.system(size: compact ? 11 : 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Button("Skip", action: onDone)
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            LengthChips(selected: nil, small: compact, showsNone: false) { value in
                model.updateTodo(todo.id) { $0.minutes = value }
                onDone()
            }
        }
        .padding(compact ? 10 : 14)
        .background(NonnaTheme.terracotta.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NonnaTheme.terracotta.opacity(0.3), lineWidth: 0.8) }
    }
}

// MARK: - Chips

/// A rounded choice button.
private struct PillButton: View {
    let title: String
    var dot: Color?
    let selected: Bool
    var small = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let dot { Circle().fill(selected ? NonnaTheme.onAccent : dot).frame(width: 7, height: 7) }
                Text(title)
                    .font(.system(size: small ? 11 : 12, weight: selected ? .semibold : .medium))
            }
            .padding(.horizontal, small ? 9 : 12)
            .frame(height: small ? 24 : 30)
            .foregroundStyle(selected ? NonnaTheme.onAccent : NonnaTheme.ink)
            .background(selected ? NonnaTheme.terracotta : NonnaTheme.raisedPaper, in: Capsule())
            .overlay { Capsule().stroke(selected ? .clear : NonnaTheme.line, lineWidth: 0.8) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Wraps chips onto as many lines as they need.
private struct FlowChips<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        FlowLayout(spacing: 6) { content }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// 15m … 3h, plus "Not sure".
private struct LengthChips: View {
    let selected: Int?
    var small = false
    var showsNone = true
    let onPick: (Int?) -> Void

    var body: some View {
        FlowChips {
            ForEach(TaskLength.choices, id: \.self) { minutes in
                PillButton(title: minutes.minutesString, selected: selected == minutes, small: small) {
                    onPick(selected == minutes ? nil : minutes)
                }
            }
            if showsNone {
                PillButton(title: "Not sure", selected: false, small: small) { onPick(nil) }
                    .opacity(selected == nil ? 0.5 : 1)
            }
            if let selected, !TaskLength.choices.contains(selected) {
                PillButton(title: selected.minutesString, selected: true, small: small) {}
            }
        }
    }
}

/// Today, Tomorrow, This weekend, Next week, No date.
private struct DueChips: View {
    let selected: Date?
    var small = false
    let onPick: (Date?) -> Void

    private var choices: [(String, Date?)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let day = { (n: Int) in calendar.date(byAdding: .day, value: n, to: today) }
        let toSaturday = (7 - calendar.component(.weekday, from: today)) % 7
        return [("Today", today), ("Tomorrow", day(1)), ("This weekend", day(toSaturday)),
                ("Next week", day(7)), ("No date", nil)]
    }

    var body: some View {
        FlowChips {
            ForEach(choices, id: \.0) { title, date in
                let isSelected = date.flatMap { d in selected.map { Calendar.current.isDate($0, inSameDayAs: d) } } ?? (selected == nil && date == nil)
                PillButton(title: title, selected: isSelected, small: small) { onPick(date) }
            }
        }
    }
}

// MARK: - Progress

/// "25m of 1h 40m" with a thin bar, or "25m focused" for an untimed task.
struct TaskProgress: View {
    @Environment(AppModel.self) private var model
    let todo: TodoItem
    let tint: Color

    var body: some View {
        let focused = model.stats(for: todo.id).seconds / 60
        if let minutes = todo.minutes {
            HStack(spacing: 7) {
                if focused > 0 {
                    Capsule()
                        .fill(tint.opacity(0.18))
                        .frame(width: 44, height: 4)
                        .overlay(alignment: .leading) {
                            Capsule().fill(tint).frame(width: 44 * min(1, Double(focused) / Double(max(1, minutes))), height: 4)
                        }
                    Text("\(focused.minutesString) of \(minutes.minutesString)")
                } else {
                    Image(systemName: "clock").font(.system(size: 9))
                    Text(minutes.minutesString)
                }
            }
        } else if focused > 0 {
            Text("\(focused.minutesString) focused")
        }
    }
}

// MARK: - Rows

private struct GroupHeader: View {
    let group: TasksView.Group
    @Environment(AppModel.self) private var model

    var body: some View {
        let left = group.todos.reduce(0) { $0 + model.minutesLeft(on: $1) }
        HStack(spacing: 8) {
            if let color = group.color {
                Circle().fill(color).frame(width: 7, height: 7)
            }
            Text(group.title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(group.color == NonnaTheme.alert ? NonnaTheme.alert : NonnaTheme.secondaryInk)
            if left > 0 {
                Text("· \(left.minutesString)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(NonnaTheme.secondaryInk.opacity(0.8))
            }
            Spacer()
        }
        .padding(.leading, 4)
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                CheckCircle(isDone: todo.isDone, tint: tint) {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.3)) { model.toggleDone(todo.id) }
                }
                VStack(alignment: .leading, spacing: 5) {
                    if todo.isDone {
                        Text(todo.title)
                            .font(.system(size: 14, weight: .medium))
                            .strikethrough(true, color: NonnaTheme.secondaryInk)
                            .foregroundStyle(NonnaTheme.secondaryInk)
                            .lineLimit(2)
                    } else {
                        InlineTitleField(todo: todo, size: 14, weight: .medium)
                    }
                    HStack(spacing: 10) {
                        TaskProgress(todo: todo, tint: tint)
                        if showsList, let list {
                            HStack(spacing: 4) {
                                Circle().fill(tint).frame(width: 5, height: 5)
                                Text(list.name)
                            }
                        }
                        if isCurrent {
                            Text("● now").foregroundStyle(tint)
                        }
                        if model.queuedTodoID == todo.id {
                            Text("up next").foregroundStyle(tint)
                        }
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                }
                Spacer(minLength: 8)
                if !todo.isDone, hovering || isCurrent {
                    StartButton(todo: todo, tint: tint)
                }
                if !todo.isDone, hovering || isExpanded {
                    EditButton(isOpen: isExpanded, action: onTap)
                }
                if let label = todo.dueLabel(), showsTodayLabel || DueBucket.of(todo.due) != .today {
                    DueText(todo: todo, label: label)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

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

private struct DueText: View {
    let todo: TodoItem
    let label: String

    var body: some View {
        let bucket = DueBucket.of(todo.due)
        Text(label)
            .font(.system(size: 11, weight: bucket.rawValue <= DueBucket.tomorrow.rawValue ? .semibold : .regular))
            .foregroundStyle(todo.isDone ? NonnaTheme.secondaryInk : bucket == .overdue ? NonnaTheme.alert : bucket == .today ? NonnaTheme.terracotta : NonnaTheme.secondaryInk)
    }
}

/// ▶ — start a focus block on this task (or pick it as the next one while timing).
private struct StartButton: View {
    @Environment(AppModel.self) private var model
    let todo: TodoItem
    let tint: Color

    var body: some View {
        let isCurrent = model.selectedTodoID == todo.id && model.status != .idle
        Button {
            if model.status == .idle { model.startFocus(on: todo.id) } else { model.linkTodo(todo.id) }
        } label: {
            Image(systemName: isCurrent ? "waveform" : "play.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(isCurrent ? NonnaTheme.onAccent : tint)
                .frame(width: 22, height: 22)
                .background(isCurrent ? tint : tint.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
        .help(model.status == .idle ? "Start focusing on this" : "Work on this next")
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
            Button("Start focusing on this") { model.startFocus(on: todo.id) }
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
        Menu("How long") {
            ForEach(TaskLength.choices, id: \.self) { minutes in
                Button(minutes.minutesString) { model.updateTodo(todo.id) { $0.minutes = minutes } }
            }
            Button("Not sure") { model.updateTodo(todo.id) { $0.minutes = nil } }
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

/// Editing a task: name, list, length, due date, notes.
private struct TodoEditor: View {
    @Environment(AppModel.self) private var model
    let todo: TodoItem
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider().overlay(NonnaTheme.line)
            field("Name") {
                InlineTitleField(todo: todo, size: 13)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(NonnaTheme.sunken, in: RoundedRectangle(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(NonnaTheme.line, lineWidth: 0.8) }
            }
            field("List") {
                FlowChips {
                    ForEach(model.tasks) { list in
                        PillButton(title: list.name, dot: NonnaTheme.taskColor(for: list.colorHex), selected: todo.listID == list.id, small: true) {
                            model.updateTodo(todo.id) { $0.listID = list.id }
                        }
                    }
                }
            }
            field("How long") {
                LengthChips(selected: todo.minutes, small: true) { value in model.updateTodo(todo.id) { $0.minutes = value } }
            }
            field("Due") {
                HStack(spacing: 8) {
                    DueChips(selected: todo.due, small: true) { date in model.updateTodo(todo.id) { $0.due = date } }
                    DatePicker("", selection: Binding(
                        get: { todo.due ?? Calendar.current.startOfDay(for: Date()) },
                        set: { date in model.updateTodo(todo.id) { $0.due = Calendar.current.startOfDay(for: date) } }
                    ), displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .fixedSize()
                    .help("Pick another date")
                }
            }
            field("Notes") {
                TextEditor(text: $notes)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 60)
                    .background(NonnaTheme.sunken, in: RoundedRectangle(cornerRadius: 9))
                    .overlay { RoundedRectangle(cornerRadius: 9).stroke(NonnaTheme.line, lineWidth: 0.8) }
                    .onChange(of: notes) { _, value in model.updateTodo(todo.id) { $0.notes = value } }
            }
            HStack {
                let focused = model.stats(for: todo.id).seconds
                if focused > 0 {
                    Text("\((focused / 60).minutesString) focused on this so far")
                        .font(.system(size: 11))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
                Spacer()
                Button(role: .destructive) {
                    model.deleteTodo(todo.id)
                } label: {
                    Label("Delete", systemImage: "trash").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(NonnaTheme.alert.opacity(0.85))
            }
        }
        .onAppear { notes = todo.notes }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(NonnaTheme.secondaryInk)
            content()
        }
    }
}

// MARK: - Board

/// Every list as a card with what's left to do underneath, the way you'd write out your
/// classes and their homework. Drag a task onto another card to move it.
private struct BoardView: View {
    @Environment(AppModel.self) private var model
    let onNewList: () -> Void

    var body: some View {
        let hasLoose = model.todos.contains { todo in
            !todo.isDone && (todo.listID == nil || !model.tasks.contains { $0.id == todo.listID })
        }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
            ForEach(model.tasks) { list in
                BoardCard(list: list)
            }
            if hasLoose {
                BoardCard(list: nil)
            }
            NewListCard(onMore: onNewList)
        }
    }
}

private struct BoardCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// nil for tasks that aren't in any list.
    let list: FocusTask?
    @State private var text = ""
    @State private var promptID: UUID?
    @State private var name = ""
    @State private var isTargeted = false
    @FocusState private var adding: Bool
    @FocusState private var naming: Bool

    private var tint: Color { list.map { NonnaTheme.taskColor(for: $0.colorHex) } ?? NonnaTheme.secondaryInk }

    private func belongs(_ todo: TodoItem) -> Bool {
        if let list { return todo.listID == list.id }
        return todo.listID == nil || !model.tasks.contains { $0.id == todo.listID }
    }

    var body: some View {
        let open = model.todos.filter { !$0.isDone && belongs($0) }.sorted(by: TodoItem.dueOrder)
        let doneToday = model.todos.filter { $0.isDone && belongs($0) && ($0.completedAt.map { Calendar.current.isDateInToday($0) } ?? false) }.count
        let left = open.reduce(0) { $0 + model.minutesLeft(on: $1) }

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle().fill(tint).frame(width: 10, height: 10)
                if let list {
                    TextField("List name", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18, weight: .semibold, design: .serif))
                        .focused($naming)
                        .onSubmit { model.renameList(list.id, to: name) }
                        .onChange(of: naming) { _, isEditing in
                            if !isEditing { model.renameList(list.id, to: name) }
                        }
                        .onAppear { name = list.name }
                        .onExitCommand {
                            name = list.name
                            naming = false
                        }
                        .onChange(of: list.name) { _, value in if !naming { name = value } }
                        .help("Click to rename")
                } else {
                    Text("No list")
                        .font(.system(size: 18, weight: .semibold, design: .serif))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(open.isEmpty ? "all done" : "\(open.count) to do\(left > 0 ? " · \(left.minutesString)" : "")")
                    .font(.system(size: 11))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                if let list {
                    Menu {
                        Button("Rename") { naming = true }
                        Button("Archive list", role: .destructive) { model.archiveTask(list.id) }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                            .frame(width: 22, height: 22)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(open) { todo in
                    BoardRow(todo: todo, tint: tint)
                    if promptID == todo.id {
                        EstimatePrompt(todo: todo, compact: true) {
                            withAnimation(reduceMotion ? nil : NonnaMotion.quick) { promptID = nil }
                        }
                        .padding(.leading, 46)
                        .padding(.trailing, 14)
                        .padding(.bottom, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                if open.isEmpty {
                    Text(doneToday > 0 ? "Nothing left. Nice work." : "Nothing here yet.")
                        .font(.system(size: 13, design: .serif))
                        .italic()
                        .foregroundStyle(NonnaTheme.secondaryInk)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                }

                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 20)
                    TextField("Add a task", text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($adding)
                        .onSubmit(add)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }

            if doneToday > 0, !open.isEmpty {
                Text("✓ \(doneToday) done today")
                    .font(.system(size: 10))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
            }
        }
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NonnaTheme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16, style: .continuous)
                .fill(tint)
                .frame(height: 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isTargeted ? tint : NonnaTheme.line, lineWidth: isTargeted ? 1.6 : 0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .dropDestination(for: String.self) { items, _ in
            guard let list else { return false }
            let ids = items.compactMap(UUID.init(uuidString:))
            for id in ids { model.updateTodo(id) { $0.listID = list.id } }
            return !ids.isEmpty
        } isTargeted: { isTargeted = $0 }
        .animation(reduceMotion ? nil : NonnaMotion.selection, value: open.map(\.id))
    }

    private func add() {
        guard let parsed = TodoParser.parseLine(text, focusMinutes: model.settings.focusMinutes) else { return }
        let id = model.addTodo(parsed, defaultList: list?.id, defaultDue: nil)
        text = ""
        adding = true
        if parsed.minutes == nil {
            withAnimation(reduceMotion ? nil : NonnaMotion.selection) { promptID = id }
        }
    }
}

/// One line on a card: tick it, see how long it takes and when it's due; click to edit.
private struct BoardRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let todo: TodoItem
    let tint: Color
    @State private var hovering = false
    @State private var editing = false

    var body: some View {
        let isCurrent = model.selectedTodoID == todo.id && model.status != .idle
        HStack(spacing: 10) {
            CheckCircle(isDone: todo.isDone, tint: tint) {
                withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.3)) { model.toggleDone(todo.id) }
            }
            VStack(alignment: .leading, spacing: 3) {
                InlineTitleField(todo: todo, size: 13.5)
                HStack(spacing: 8) {
                    TaskProgress(todo: todo, tint: tint)
                    if isCurrent { Text("● now").foregroundStyle(tint) }
                    if model.queuedTodoID == todo.id { Text("up next").foregroundStyle(tint) }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(NonnaTheme.secondaryInk)
                .contentShape(Rectangle())
                .onTapGesture { editing = true }
            }
            Spacer(minLength: 6)
            if hovering || isCurrent {
                StartButton(todo: todo, tint: tint)
            }
            if hovering || editing {
                EditButton { editing = true }
            }
            if let label = todo.dueLabel() {
                DueText(todo: todo, label: label)
                    .onTapGesture { editing = true }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(hovering ? NonnaTheme.raisedPaper : .clear)
        .onHover { hovering = $0 }
        .popover(isPresented: $editing, arrowEdge: .trailing) {
            TodoEditor(todo: todo)
                .padding(18)
                .frame(width: 480)
                .background(NonnaTheme.cream)
                .environment(model)
        }
        .contextMenu { TodoMenu(todo: todo) }
        .draggable(todo.id.uuidString) {
            Text(todo.title)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(NonnaTheme.raisedPaper, in: Capsule())
        }
    }
}

/// The last card: type a class or project name and press Return.
private struct NewListCard: View {
    @Environment(AppModel.self) private var model
    let onMore: () -> Void
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(NonnaTheme.terracotta)
                TextField("New list, like a class or project", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, design: .serif))
                    .onSubmit {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        let palette = ["BDA56F", "738B80", "A9A4B5", "788897", "8F7581", "6F858F", "837765"]
                        model.addTask(name: trimmed, colorHex: palette[model.data.tasks.count % palette.count])
                        name = ""
                    }
            }
            Button("Choose a colour…", action: onMore)
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(NonnaTheme.secondaryInk)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(NonnaTheme.strongLine, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
    }
}

// MARK: - Paste a list

/// A plain-text pad: paste a whole list the way you'd write it in Notes, see it read
/// live, and add everything in one go.
private struct WriteItOutSheet: View {
    @Environment(AppModel.self) private var model
    let scope: TaskScope
    let onDone: () -> Void
    @State private var text = ""

    private var parsed: [ParsedTodo] {
        TodoParser.parseDocument(text, focusMinutes: model.settings.focusMinutes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Paste a list")
                    .font(.system(size: 26, weight: .regular, design: .serif))
                Text("One task per line. A line ending in a colon, like “Chemistry:”, starts a list. Add “1h” or “30m” for how long, and “today”, “tomorrow” or a weekday for when it’s due.")
                    .font(.system(size: 12))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(28)

            HStack(alignment: .top, spacing: 18) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Math:\n- Formula sheet 1h today\n- Problem set 5 tomorrow\n\nBio:\n- Read chapter 4 45m fri\n- Practice midterm 2h")
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
                        Text(parsed.isEmpty ? "Your tasks will show up here" : "\(parsed.count) \(parsed.count == 1 ? "task" : "tasks") to add")
                            .font(.system(size: 11, weight: .medium))
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
                    model.addTodos(parsed, defaultList: scope.listID, defaultDue: scope.defaultDue)
                    onDone()
                } label: {
                    Text(parsed.isEmpty ? "Add tasks" : "Add \(parsed.count) \(parsed.count == 1 ? "task" : "tasks")")
                }
                .buttonStyle(NonnaButtonStyle())
                .disabled(parsed.isEmpty)
                .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding(28)
        }
        .frame(width: 820, height: 600)
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
                if let minutes = item.minutes {
                    Text(minutes.minutesString)
                }
                if let due = item.due {
                    Text(TodoItem(title: "", due: due).dueLabel() ?? "")
                }
            }
            .font(.system(size: 10.5))
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
        return HStack(spacing: 10) {
            CheckCircle(isDone: todo.isDone, tint: tint) {
                withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.3)) { model.toggleDone(todo.id) }
            }
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
            TaskProgress(todo: todo, tint: tint)
                .font(.system(size: 10.5))
                .foregroundStyle(NonnaTheme.secondaryInk)
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
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                Text("Pick a task")
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(NonnaTheme.secondaryInk)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Link this focus block to a task so its time counts toward it")
    }

    private func item(_ todo: TodoItem) -> some View {
        let left = todo.minutes.map { _ in " · \(model.minutesLeft(on: todo).minutesString) left" } ?? ""
        return Button("\(todo.title)\(left)") { model.linkTodo(todo.id) }
    }
}

// MARK: - Inline editing

/// A task's name you can click into and retype, like a line in Notes. Saves on Return or
/// when you click away; an emptied name goes back to what it was.
private struct InlineTitleField: View {
    @Environment(AppModel.self) private var model
    let todo: TodoItem
    var size: CGFloat = 14
    var weight: Font.Weight = .regular
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Task", text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(NonnaTheme.ink)
            .lineLimit(1...3)
            .focused($focused)
            .onAppear { text = todo.title }
            .onChange(of: todo.title) { _, value in if !focused { text = value } }
            .onSubmit(save)
            .onChange(of: focused) { _, isEditing in if !isEditing { save() } }
            .onExitCommand {
                text = todo.title
                focused = false
            }
            .help("Click to edit")
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            text = todo.title
            return
        }
        if trimmed != todo.title { model.updateTodo(todo.id) { $0.title = trimmed } }
    }
}

/// Opens a task's details: list, how long, due date, notes.
private struct EditButton: View {
    var isOpen = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOpen ? "chevron.up" : "slider.horizontal.3")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(NonnaTheme.secondaryInk)
                .frame(width: 22, height: 22)
                .background(NonnaTheme.sunken, in: Circle())
        }
        .buttonStyle(.plain)
        .help(isOpen ? "Close details" : "Edit time, due date, list and notes")
    }
}
