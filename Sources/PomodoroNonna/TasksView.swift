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
    @EnvironmentObject private var calendarStore: CalendarStore
    @State private var planMessage: String?
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
                    if let planMessage {
                        Label(planMessage, systemImage: "wand.and.stars")
                            .font(.system(size: 12))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                            .task(id: planMessage) {
                                try? await Task.sleep(for: .seconds(5))
                                self.planMessage = nil
                            }
                    }
                    statsStrip
                    if scope == .board {
                        BoardView(onNewList: { showingNewList = true }, onOpen: { scope = .list($0) })
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
                }
                Text(title)
                    .font(.system(size: 29, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            Spacer()
            Button {
                let today = Date()
                let busy = calendarStore.events(on: today, hiddenIDs: model.settings.hiddenCalendarIDs)
                    .filter { !$0.isAllDay }
                    .map { DayPlanner.Slot(start: $0.startedAt, end: $0.endedAt) }
                let placed = model.planDay(today, busy: busy)
                planMessage = placed == 0 ? "Nothing due today needs a time, or the day is full." : "Planned \(placed) \(placed == 1 ? "task" : "tasks") into today's free time. See the timeline."
            } label: {
                Label("Plan my day", systemImage: "wand.and.stars")
            }
            .buttonStyle(NonnaButtonStyle(prominent: false))
            .help("Fit what's due today into your free time on the timeline")
            Button {
                model.showsWrapUp = true
            } label: {
                Label("Wrap up day", systemImage: "moon.stars")
            }
            .buttonStyle(NonnaButtonStyle(prominent: false))
            .help("See what got done today and move the rest to tomorrow")
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
            // One quiet line of numbers instead of a strip of big ones.
            HStack(spacing: 22) {
                inlineStat("\(open.count)", "to do")
                inlineStat(left.minutesString, unestimated > 0 ? "needed, \(unestimated) not timed" : "needed")
                inlineStat((focused / 60).minutesString, showsToday ? "focused today" : "focused on these")
                inlineStat("\(completedToday)", "done today")
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

    private func inlineStat(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(NonnaTheme.ink)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(NonnaTheme.secondaryInk)
        }
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
                    .font(.system(size: 11))
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
                let title = DueBucket.of(day) == .overdue ? "Overdue, \(day.formatted(.dateTime.month(.abbreviated).day()))"
                    : "\(label), \(day.formatted(.dateTime.weekday(.wide)))"
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
    @State private var dropTarget: TaskScope?
    @State private var colouring: UUID?
    @State private var renameText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                row(scope: .board, title: "All lists", color: nil, icon: "square.grid.2x2")
                row(scope: .today, title: "Today", color: nil, icon: "sun.max")
                row(scope: .upcoming, title: "Upcoming", color: nil, icon: "calendar")
                row(scope: .completed, title: "Completed", color: nil, icon: "checkmark.circle")

                HStack {
                    Text("Lists")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
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
                            .popover(isPresented: Binding(get: { colouring == list.id }, set: { if !$0 { colouring = nil } }), arrowEdge: .trailing) {
                                ListColorPicker(hex: Binding(
                                    get: { list.colorHex },
                                    set: { model.setListColor(list.id, to: $0) }
                                ), size: 22)
                                .frame(width: 236)
                                .padding(14)
                            }
                            .contextMenu {
                                Button("Rename…") {
                                    renameText = list.name
                                    renaming = list.id
                                }
                                Button("Change colour…") { colouring = list.id }
                                Button("Archive list") {
                                    if scope == .list(list.id) { scope = .board }
                                    model.archiveTask(list.id)
                                }
                                Divider()
                                Button("Delete list…", role: .destructive) {
                                    let wasOpen = scope == .list(list.id)
                                    if model.confirmDeleteList(list.id), wasOpen { scope = .board }
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
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(selected ? NonnaTheme.raisedPaper : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                if selected { RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }
                if dropTarget == target {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(color ?? NonnaTheme.terracotta, lineWidth: 1.6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Drop a task here: onto a list to move it, Today to make it due today,
        // Completed to tick it off.
        .dropDestination(for: String.self) { items, _ in
            let ids = items.compactMap(TodoDrag.id(from:))
            for id in ids { drop(id, on: target) }
            return !ids.isEmpty && target != .board && target != .upcoming
        } isTargeted: { inside in
            if inside { dropTarget = target } else if dropTarget == target { dropTarget = nil }
        }
    }

    private func drop(_ id: UUID, on target: TaskScope) {
        switch target {
        case .list(let listID): model.updateTodo(id) { $0.listID = listID }
        case .today: model.updateTodo(id) { $0.due = Calendar.current.startOfDay(for: Date()) }
        case .completed:
            if model.todos.first(where: { $0.id == id })?.isDone == false { model.toggleDone(id) }
        case .board, .upcoming: break
        }
    }
}

// MARK: - Adding

/// The short form behind "New task": what, which list, how long, and when.
private struct NewTodoSheet: View {
    @Environment(AppModel.self) private var model
    @State private var makingList = false
    @State private var newListName = ""
    @FocusState private var listNameFocused: Bool
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
                    if makingList {
                        TextField("List name", text: $newListName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                            .focused($listNameFocused)
                            .onSubmit(createList)
                            .onExitCommand { makingList = false }
                    } else {
                        Button {
                            makingList = true
                            listNameFocused = true
                        } label: {
                            Label("New list", systemImage: "plus")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(NonnaTheme.terracotta)
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .overlay { Capsule().strokeBorder(NonnaTheme.strongLine, style: StrokeStyle(lineWidth: 0.8, dash: [3, 3])) }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let list = model.tasks.first(where: { $0.id == listID }) {
                field("\(list.name) colour") {
                    ListColorPicker(hex: Binding(
                        get: { list.colorHex },
                        set: { model.setListColor(list.id, to: $0) }
                    ), size: 22)
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

    /// A list made right here, picked for this task, with the next colour in line.
    private func createList() {
        let name = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { makingList = false; return }
        listID = model.list(named: name)
        newListName = ""
        makingList = false
    }

    private func add() {
        guard !trimmed.isEmpty else { return }
        // Typed shortcuts like "1h" or "tomorrow" still work; the picks win when made.
        let parsed = TodoParser.parseLine(trimmed, focusMinutes: model.settings.focusMinutes)
        model.addTodo(title: parsed?.title ?? trimmed, listID: listID, minutes: minutes ?? parsed?.minutes, due: due ?? parsed?.due)
        onDone()
    }
}

/// The "Add a task" line. Typing opens separate rows for the date, the length and the list,
/// so nothing has to be remembered as a shortcut; Return adds it.
private struct QuickAddBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let scope: TaskScope
    /// The new task's id, and whether it already has a length.
    let onAdd: (UUID, Bool) -> Void
    @State private var text = ""
    @State private var due: Date?
    @State private var minutes: Int?
    @State private var listID: UUID?
    @FocusState private var focused: Bool

    private var expanded: Bool { !text.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NonnaTheme.terracotta)
                TextField("Add a task", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($focused)
                    .onSubmit(add)
                if expanded {
                    Text("Return to add")
                        .font(.system(size: 10))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
            }
            .frame(height: 50)

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    row("When", icon: "calendar") { DueChips(selected: due, small: true) { due = $0 } }
                    row("How long", icon: "clock") { LengthChips(selected: minutes, small: true) { minutes = $0 } }
                    if !model.tasks.isEmpty {
                        row("List", icon: "tag") {
                            FlowChips {
                                ForEach(model.tasks) { list in
                                    PillButton(title: list.name, dot: NonnaTheme.taskColor(for: list.colorHex), selected: listID == list.id, small: true) {
                                        listID = listID == list.id ? nil : list.id
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 18)
        .background(NonnaTheme.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(focused ? NonnaTheme.terracotta.opacity(0.6) : NonnaTheme.line, lineWidth: focused ? 1.2 : 0.8)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: expanded)
        .onAppear(perform: resetPicks)
        .onChange(of: scope) { _, _ in resetPicks() }
    }

    private func row<Content: View>(_ label: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Label(label, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NonnaTheme.secondaryInk)
                .frame(width: 84, alignment: .leading)
            content()
        }
    }

    /// Starts from where you are: a list's page picks that list, Today picks today.
    private func resetPicks() {
        due = scope.defaultDue
        minutes = nil
        listID = scope.listID
    }

    private func add() {
        guard let parsed = TodoParser.parseLine(text, focusMinutes: model.settings.focusMinutes) else { return }
        // Typed shortcuts still work; the rows fill in whatever wasn't typed.
        let entry = ParsedTodo(title: parsed.title, minutes: parsed.minutes ?? minutes, due: parsed.due ?? due, listName: parsed.listName)
        let id = model.addTodo(entry, defaultList: listID, defaultDue: nil)
        text = ""
        resetPicks()
        focused = true
        onAdd(id, entry.minutes != nil)
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
struct PillButton: View {
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
struct FlowChips<Content: View>: View {
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

    @State private var picking = false

    var body: some View {
        let presetPicked = choices.contains { _, date in
            date.flatMap { d in selected.map { Calendar.current.isDate($0, inSameDayAs: d) } } ?? (selected == nil && date == nil)
        }
        FlowChips {
            ForEach(choices, id: \.0) { title, date in
                let isSelected = date.flatMap { d in selected.map { Calendar.current.isDate($0, inSameDayAs: d) } } ?? (selected == nil && date == nil)
                PillButton(title: title, selected: isSelected, small: small) { onPick(date) }
            }
            // Any other day, from a calendar.
            PillButton(title: !presetPicked ? (selected?.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) ?? "Pick a date") : "Pick a date…",
                       selected: !presetPicked, small: small) { picking = true }
                .popover(isPresented: $picking, arrowEdge: .bottom) {
                    DatePicker("Due", selection: Binding(
                        get: { selected ?? Calendar.current.startOfDay(for: Date()) },
                        set: { date in
                            onPick(Calendar.current.startOfDay(for: date))
                            picking = false
                        }
                    ), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(12)
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
        HStack(spacing: 10) {
            time
            let steps = todo.steps
            if !steps.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "checklist").font(.system(size: 10))
                    Text("\(steps.filter(\.isDone).count) of \(steps.count)")
                        .monospacedDigit()
                }
                .help("Steps done")
            }
        }
    }

    @ViewBuilder
    private var time: some View {
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
                    Image(systemName: "clock").font(.system(size: 11))
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
            Text(group.title)
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(group.color == NonnaTheme.alert ? NonnaTheme.alert : NonnaTheme.secondaryInk)
            if left > 0 {
                Text("\(left.minutesString) left")
                    .font(.system(size: 10).monospacedDigit())
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
        .draggable(TodoDrag.payload(for: todo.id)) {
            Text(todo.title)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(NonnaTheme.raisedPaper, in: Capsule())
        }
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
                .font(.system(size: 10, weight: .bold))
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
                        .font(.system(size: 11, weight: .heavy))
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
        Button("Delete…", role: .destructive) { model.confirmDeleteTodo(todo.id) }
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
            field("Steps") {
                SubtaskList(todo: todo)
            }
            if let planned = todo.scheduledAt {
                field("On the timeline") {
                    HStack(spacing: 10) {
                        Text(planned.formatted(.dateTime.weekday(.wide).hour().minute()))
                            .font(.system(size: 12))
                        Button("Take it off") { model.schedule(todo.id, at: nil) }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(NonnaTheme.terracotta)
                    }
                }
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
                    model.confirmDeleteTodo(todo.id)
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
            Text(label)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
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
    let onOpen: (UUID) -> Void

    var body: some View {
        let hasLoose = model.todos.contains { todo in
            !todo.isDone && (todo.listID == nil || !model.tasks.contains { $0.id == todo.listID })
        }
        let active = model.tasks.filter { list in model.todos.contains { !$0.isDone && $0.listID == list.id } }
        let empty = model.tasks.filter { list in !model.todos.contains { !$0.isDone && $0.listID == list.id } }
        VStack(alignment: .leading, spacing: 26) {
            if active.isEmpty && !hasLoose {
                Text("Nothing to do yet. Add a task to any list below, or start a new list.")
                    .font(.system(size: 13))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 18, alignment: .top)], alignment: .leading, spacing: 18) {
                    ForEach(active) { list in
                        BoardCard(list: list)
                    }
                    if hasLoose {
                        BoardCard(list: nil)
                    }
                }
            }

            // Lists with nothing left wait quietly in one row instead of taking up cards.
            VStack(alignment: .leading, spacing: 10) {
                if !empty.isEmpty {
                    Text("Empty lists")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
                FlowChips {
                    ForEach(empty) { list in
                        Button { onOpen(list.id) } label: {
                            HStack(spacing: 7) {
                                Circle().fill(NonnaTheme.taskColor(for: list.colorHex)).frame(width: 8, height: 8)
                                Text(list.name).font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(NonnaTheme.paper, in: Capsule())
                            .overlay { Capsule().stroke(NonnaTheme.line, lineWidth: 0.8) }
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Open \(list.name) to add tasks, or drop a task here to move it")
                        .dropDestination(for: String.self) { items, _ in
                            let ids = items.compactMap(TodoDrag.id(from:))
                            for id in ids { model.updateTodo(id) { $0.listID = list.id } }
                            return !ids.isEmpty
                        }
                    }
                    Button(action: onNewList) {
                        Label("New list", systemImage: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(NonnaTheme.terracotta)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .overlay { Capsule().strokeBorder(NonnaTheme.strongLine, style: StrokeStyle(lineWidth: 0.8, dash: [3, 3])) }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
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
    @State private var pickingColor = false

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
                if let list {
                    Button { pickingColor = true } label: {
                        Circle().fill(tint).frame(width: 12, height: 12)
                            .padding(4)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Change colour")
                    .popover(isPresented: $pickingColor, arrowEdge: .bottom) {
                        ListColorPicker(hex: Binding(
                            get: { list.colorHex },
                            set: { model.setListColor(list.id, to: $0) }
                        ), size: 22)
                        .frame(width: 236)
                        .padding(14)
                    }
                } else {
                    Circle().fill(tint).frame(width: 10, height: 10)
                }
                if let list {
                    TextField("List name", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .semibold))
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
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(open.isEmpty ? "All done" : "\(open.count) to do\(left > 0 ? ", \(left.minutesString)" : "")")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(NonnaTheme.sunken.opacity(0.7), in: Capsule())
                if let list {
                    Menu {
                        Button("Rename") { naming = true }
                        Button("Change colour…") { pickingColor = true }
                        Button("Archive list") { model.archiveTask(list.id) }
                        Divider()
                        Button("Delete list…", role: .destructive) { model.confirmDeleteList(list.id) }
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
        .overlay(alignment: .leading) {
            // The list's colour runs down the side, so lists read apart at a glance.
            UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16, style: .continuous)
                .fill(tint)
                .frame(width: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isTargeted ? tint : NonnaTheme.line, lineWidth: isTargeted ? 1.6 : 0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .dropDestination(for: String.self) { items, _ in
            guard let list else { return false }
            let ids = items.compactMap(TodoDrag.id(from:))
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
        .draggable(TodoDrag.payload(for: todo.id)) {
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
                            .font(.system(size: 14).monospacedDigit())
                            .foregroundStyle(NonnaTheme.secondaryInk.opacity(0.5))
                            .padding(.horizontal, 15)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(.system(size: 14).monospacedDigit())
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
                Text("Working on")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint)
                Text(todo.title)
                    .font(.system(size: 12, weight: .medium))
                    .strikethrough(todo.isDone, color: NonnaTheme.secondaryInk)
                    .lineLimit(1)
                if let next = todo.steps.first(where: { !$0.isDone }) {
                    // The next small step, checkable right here.
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.2)) { model.toggleSubtask(next.id, in: todo.id) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "circle").font(.system(size: 10))
                            Text("Next: \(next.title)").lineLimit(1)
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                    }
                    .buttonStyle(.plain)
                    .help("Check off this step")
                }
            }
            TaskProgress(todo: todo, tint: tint)
                .font(.system(size: 10.5))
                .foregroundStyle(NonnaTheme.secondaryInk)
            Button {
                model.unlinkTodo()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
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
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
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
        let left = todo.minutes.map { _ in ", \(model.minutesLeft(on: todo).minutesString) left" } ?? ""
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


/// A task's steps: tick them off, rename in place, remove, or add one with Return.
private struct SubtaskList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let todo: TodoItem
    @State private var newStep = ""
    @FocusState private var adding: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(todo.steps) { step in
                SubtaskRow(todo: todo, step: step)
            }
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NonnaTheme.terracotta)
                    .frame(width: 16)
                TextField(todo.steps.isEmpty ? "Break it into a first small step" : "Add a step", text: $newStep)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($adding)
                    .onSubmit {
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.1)) {
                            model.addSubtask(to: todo.id, title: newStep)
                        }
                        newStep = ""
                        adding = true
                    }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct SubtaskRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let todo: TodoItem
    let step: Subtask
    @State private var title = ""
    @State private var hovering = false
    @FocusState private var editing: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.25)) { model.toggleSubtask(step.id, in: todo.id) }
            } label: {
                Image(systemName: step.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(step.isDone ? NonnaTheme.terracotta : NonnaTheme.secondaryInk)
                    .frame(width: 16)
            }
            .buttonStyle(.plain)
            TextField("Step", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .strikethrough(step.isDone, color: NonnaTheme.secondaryInk)
                .foregroundStyle(step.isDone ? NonnaTheme.secondaryInk : NonnaTheme.ink)
                .focused($editing)
                .onSubmit { model.renameSubtask(step.id, in: todo.id, to: title) }
                .onExitCommand { title = step.title; editing = false }
                .onChange(of: editing) { _, isEditing in if !isEditing { model.renameSubtask(step.id, in: todo.id, to: title) } }
            Spacer(minLength: 4)
            Button { model.removeSubtask(step.id, from: todo.id) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(NonnaTheme.secondaryInk)
            .opacity(hovering ? 1 : 0)
            .help("Remove this step")
        }
        .onHover { hovering = $0 }
        .onAppear { title = step.title }
        .onChange(of: step.title) { _, value in if !editing { title = value } }
    }
}
