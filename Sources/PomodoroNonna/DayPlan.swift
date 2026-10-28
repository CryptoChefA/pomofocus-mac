import Foundation

/// Planning the day on the timeline, steps inside a task, and the end-of-day wrap-up.
extension AppModel {
    // MARK: Timeline planning

    /// Open tasks planned on `day`, earliest first.
    func scheduledTodos(on day: Date, calendar: Calendar = .current) -> [TodoItem] {
        todos
            .filter { todo in todo.scheduledAt.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
            .sorted { ($0.scheduledAt ?? .distantPast) < ($1.scheduledAt ?? .distantPast) }
    }

    /// Open tasks that could still go on `day`'s timeline: due by then first, then undated, then later.
    func planCandidates(for day: Date, calendar: Calendar = .current) -> [TodoItem] {
        let dayStart = calendar.startOfDay(for: day)
        func rank(_ todo: TodoItem) -> Int {
            guard let due = todo.due else { return 1 }
            return due <= dayStart ? 0 : 2
        }
        return todos
            .filter { !$0.isDone && !($0.scheduledAt.map { calendar.isDate($0, inSameDayAs: day) } ?? false) }
            .sorted {
                rank($0) != rank($1) ? rank($0) < rank($1)
                    : ($0.due ?? .distantFuture) != ($1.due ?? .distantFuture) ? ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture)
                    : $0.createdAt < $1.createdAt
            }
    }

    /// Puts a task on the timeline at `start` (nil takes it off). A task without a date
    /// becomes due that day, so it shows up in Today too.
    func schedule(_ id: UUID, at start: Date?, calendar: Calendar = .current) {
        updateTodo(id) { todo in
            todo.scheduledAt = start
            if let start, todo.due == nil {
                todo.due = calendar.startOfDay(for: start)
            }
        }
    }

    /// Fits today's due and overdue tasks into the free time left in `day`, around
    /// calendar events, what's already planned, and the block that's running.
    /// Returns how many tasks were placed.
    @discardableResult
    func planDay(_ day: Date, busy events: [DayPlanner.Slot], calendar: Calendar = .current) -> Int {
        let dayStart = calendar.startOfDay(for: day)
        guard let morning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: dayStart),
              let night = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: dayStart) else { return 0 }
        let now = Date()
        let from = calendar.isDateInToday(day) ? max(now, morning) : morning
        guard from < night else { return 0 }

        var busy = events
        busy += scheduledTodos(on: day).compactMap { todo in
            todo.scheduledAt.map { DayPlanner.Slot(start: $0, end: $0.addingTimeInterval(TimeInterval(todo.plannedMinutes * 60))) }
        }
        if calendar.isDateInToday(day), status != .idle {
            busy.append(DayPlanner.Slot(start: now, end: now.addingTimeInterval(TimeInterval(max(remainingSeconds, 0)))))
        }
        let due = planCandidates(for: day).filter { ($0.due.map { $0 <= dayStart }) ?? false }
        let gap = focusPlan?.level.breakMinutes ?? settings.shortBreakMinutes
        let placed = DayPlanner.place(due.map { ($0.id, $0.plannedMinutes) }, busy: busy, from: from, until: night,
                                      gapMinutes: gap, calendar: calendar)
        for (id, start) in placed { schedule(id, at: start, calendar: calendar) }
        return placed.count
    }

    // MARK: Steps

    func addSubtask(to id: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateTodo(id) { $0.subtasks = $0.steps + [Subtask(title: trimmed)] }
    }

    func toggleSubtask(_ stepID: UUID, in id: UUID) {
        updateTodo(id) { todo in
            todo.subtasks = todo.steps.map { var step = $0; if step.id == stepID { step.isDone.toggle() }; return step }
        }
    }

    func renameSubtask(_ stepID: UUID, in id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateTodo(id) { todo in
            todo.subtasks = todo.steps.map { var step = $0; if step.id == stepID { step.title = trimmed }; return step }
        }
    }

    func removeSubtask(_ stepID: UUID, from id: UUID) {
        updateTodo(id) { todo in
            let rest = todo.steps.filter { $0.id != stepID }
            todo.subtasks = rest.isEmpty ? nil : rest
        }
    }

    // MARK: Wrap-up

    struct DayWrapUp {
        let day: Date
        let focusedSeconds: Int
        let blocks: Int
        let finished: [TodoItem]
        let leftovers: [TodoItem]
        /// Focus per list, largest first.
        let lists: [(name: String, colorHex: String, seconds: Int)]
    }

    func wrapUp(for day: Date = Date(), calendar: Calendar = .current) -> DayWrapUp {
        let dayStart = calendar.startOfDay(for: day)
        let parts = sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: day) && $0.outcome != .abandoned }
        let blocks = FocusSession.mergedBlocks(parts)
        let finished = todos.filter { $0.completedAt.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
        let leftovers = todos.filter { todo in
            guard !todo.isDone else { return false }
            let planned = todo.scheduledAt.map { calendar.isDate($0, inSameDayAs: day) } ?? false
            let due = todo.due.map { $0 <= dayStart } ?? false
            return planned || due
        }
        var perList: [String: (String, Int)] = [:]
        for block in parts {
            let list = data.tasks.first { $0.id == block.taskID }
            let entry = perList[block.taskName] ?? (list?.colorHex ?? "8D8379", 0)
            perList[block.taskName] = (entry.0, entry.1 + block.focusedSeconds)
        }
        let lists = perList.map { (name: $0.key, colorHex: $0.value.0, seconds: $0.value.1) }.sorted { $0.seconds > $1.seconds }
        return DayWrapUp(day: dayStart, focusedSeconds: blocks.reduce(0) { $0 + $1.focusedSeconds }, blocks: blocks.count,
                         finished: finished, leftovers: leftovers, lists: lists)
    }

    /// Moves unfinished tasks to the next day and takes them off today's timeline.
    func moveToTomorrow(_ ids: [UUID], from day: Date = Date(), calendar: Calendar = .current) {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) else { return }
        for id in ids {
            updateTodo(id) { todo in
                todo.due = tomorrow
                todo.scheduledAt = nil
            }
        }
        markWrappedUp()
    }

    static let lastWrapUpKey = "lastWrapUpDay"

    /// Evening, something left over, and today not wrapped up yet.
    var shouldOfferWrapUp: Bool {
        let calendar = Calendar.current
        guard calendar.component(.hour, from: Date()) >= 19 else { return false }
        if let last = lastWrapUpDay ?? (UserDefaults.standard.object(forKey: Self.lastWrapUpKey) as? Date),
           calendar.isDateInToday(last) { return false }
        let summary = wrapUp()
        return summary.blocks > 0 || !summary.leftovers.isEmpty
    }

    func markWrappedUp() {
        let today = Calendar.current.startOfDay(for: Date())
        UserDefaults.standard.set(today, forKey: Self.lastWrapUpKey)
        lastWrapUpDay = today
    }
}
