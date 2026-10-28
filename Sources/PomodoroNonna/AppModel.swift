import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers
import UserNotifications

/// Observed with the Observation framework, so a view only redraws when a property it
/// actually reads changes. The once-a-second clock no longer redraws the dashboard, the
/// history list, or anything else that does not show the time.
@MainActor
@Observable
final class AppModel {
    private(set) var data: AppData = .starter {
        didSet { invalidateDerivedData() }
    }
    var phase: TimerPhase = .focus
    var status: TimerStatus = .idle
    var selectedTaskID: UUID?
    var intention = ""
    var note = ""
    var noteImages: [SessionImageAttachment] = []
    var remainingSeconds = 25 * 60
    var elapsedSeconds = 0
    var pausedSeconds = 0
    var plannedSeconds = 25 * 60
    var isOvertime = false
    var breathingRemaining = 0
    var completedFocusCycleCount = 0
    var reflectionSession: FocusSession?
    /// Set when the away guard paused an overtime timer; the moment counting stopped.
    var awayPausedAt: Date?
    /// The end-of-day wrap-up sheet.
    var showsWrapUp = false
    /// The last day wrapped up, kept here so the evening banner hides as soon as it's done.
    var lastWrapUpDay: Date?
    /// The blocks a session-end rating applies to (empty when rating a single block).
    var reflectionRunIDs: [UUID] = []
    @ObservationIgnored private var awayStartedAt: Date?
    @ObservationIgnored private var awayObserversStarted = false
    var awaitingNextPhase: TimerPhase?
    var storageError: String?
    private(set) var activityIntervals: [ActivityInterval] = []

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTick = Date()
    private var sessionStartedAt: Date?
    @ObservationIgnored private var lastPersistSecond = 0
    @ObservationIgnored private var lastWidgetSyncSecond = 0
    private var breathingEndsAt: Date?
    @ObservationIgnored private var lastOvertimeReminderMark = 0
    @ObservationIgnored private let ambientPlayer = AmbientSoundPlayer()
    @ObservationIgnored private let cuePlayer = CueSoundPlayer()
    @ObservationIgnored private var ambientPreviewToken: UUID?

    // Derived collections are rebuilt lazily, once per change to `data`, instead of
    // being re-sorted and re-aggregated on every view evaluation.
    @ObservationIgnored private var cachedSessions: [FocusSession]?
    @ObservationIgnored private var cachedBreaks: [BreakSession]?
    @ObservationIgnored private var cachedAnalytics: AnalyticsSnapshot?
    @ObservationIgnored private var cachedTodayFocus: (day: Date, seconds: Int)?
    @ObservationIgnored private var cachedTodoStats: [UUID: TodoStats]?

    var tasks: [FocusTask] { data.tasks.filter { !$0.isArchived } }
    var sessions: [FocusSession] {
        let source = data.sessions
        if let cachedSessions { return cachedSessions }
        let sorted = source.sorted { $0.startedAt > $1.startedAt }
        cachedSessions = sorted
        return sorted
    }
    var breakSessions: [BreakSession] {
        let source = data.breaks ?? []
        if let cachedBreaks { return cachedBreaks }
        let sorted = source.sorted { $0.startedAt > $1.startedAt }
        cachedBreaks = sorted
        return sorted
    }
    var settings: NonnaSettings { data.settings }
    var analytics: AnalyticsSnapshot {
        let (sessions, tasks) = (data.sessions, data.tasks)
        if let cachedAnalytics { return cachedAnalytics }
        let snapshot = AnalyticsSnapshot.calculate(sessions: sessions, tasks: tasks)
        cachedAnalytics = snapshot
        return snapshot
    }

    /// Focus recorded today, not counting the block that is running now.
    var todayRecordedFocusSeconds: Int {
        let source = data.sessions
        let today = Calendar.current.startOfDay(for: Date())
        if let cachedTodayFocus, cachedTodayFocus.day == today { return cachedTodayFocus.seconds }
        let seconds = source
            .filter { Calendar.current.isDate($0.startedAt, inSameDayAs: today) && $0.outcome != .abandoned }
            .reduce(0) { $0 + $1.focusedSeconds }
        cachedTodayFocus = (today, seconds)
        return seconds
    }

    private func invalidateDerivedData() {
        cachedSessions = nil
        cachedBreaks = nil
        cachedAnalytics = nil
        cachedTodayFocus = nil
        cachedTodoStats = nil
    }
    var activeTimerStartedAt: Date? { sessionStartedAt }

    var selectedTask: FocusTask? {
        data.tasks.first { $0.id == selectedTaskID }
    }

    var progress: Double {
        guard plannedSeconds > 0 else { return 0 }
        return min(1, max(0, Double(elapsedSeconds) / Double(plannedSeconds)))
    }

    var displaySeconds: Int {
        if breathingRemaining > 0 { return breathingRemaining }
        return isOvertime ? max(0, elapsedSeconds - plannedSeconds) : remainingSeconds
    }

    static let breathingCycleCount = 3
    static let breathingInhaleSeconds = 4
    static let breathingExhaleSeconds = 6
    static let breathingCycleSeconds = breathingInhaleSeconds + breathingExhaleSeconds
    static let breathingTotalSeconds = breathingCycleCount * breathingCycleSeconds

    var isBreathing: Bool { breathingRemaining > 0 }

    var breathingStage: BreathingStage {
        let elapsed = max(0, Self.breathingTotalSeconds - breathingRemaining)
        return elapsed % Self.breathingCycleSeconds < Self.breathingInhaleSeconds ? .inhale : .exhale
    }

    /// How full the menu-bar tank should be during the opening breath ritual:
    /// it rises over the inhale and falls over the exhale, smoothly rather than per second.
    var breathFill: Double? {
        guard isBreathing, let end = breathingEndsAt else { return nil }
        let remaining = max(0, end.timeIntervalSinceNow)
        let elapsed = Double(Self.breathingTotalSeconds) - remaining
        let inCycle = elapsed.truncatingRemainder(dividingBy: Double(Self.breathingCycleSeconds))
        if inCycle < Double(Self.breathingInhaleSeconds) {
            return inCycle / Double(Self.breathingInhaleSeconds)
        }
        return 1 - (inCycle - Double(Self.breathingInhaleSeconds)) / Double(Self.breathingExhaleSeconds)
    }

    var breathingCycle: Int {
        let elapsed = max(0, Self.breathingTotalSeconds - breathingRemaining)
        return min(Self.breathingCycleCount, elapsed / Self.breathingCycleSeconds + 1)
    }

    var cycleNextPhase: TimerPhase? {
        if isOvertime { return phase == .focus ? upcomingBreakPhase() : .focus }
        return awaitingNextPhase
    }

    var canAdvanceCycle: Bool { cycleNextPhase != nil }

    var nextActionTitle: String {
        guard let next = cycleNextPhase else { return "Next" }
        let minutes: Int = switch next {
        case .focus: settings.focusMinutes
        case .shortBreak: settings.shortBreakMinutes
        case .longBreak: settings.longBreakMinutes
        }
        return next == .focus ? "Next: \(minutes) min focus" : "Next: \(minutes) min break"
    }

    init() {
        Task { await load() }
    }

    /// The one-second clock only exists while something is timing (breathing, running,
    /// overtime, or paused). An idle app schedules no wakeups at all.
    private func ensureTicking() {
        syncMenuPulse()
        guard timer == nil else { return }
        let clock = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        clock.tolerance = 0.05
        // .common keeps the clock moving while a menu is open or a list is scrolling.
        RunLoop.main.add(clock, forMode: .common)
        timer = clock
    }

    private func stopTickingIfIdle() {
        guard status == .idle, !isBreathing else { return }
        timer?.invalidate()
        timer = nil
        syncMenuPulse()
    }

    /// Ticks only while the menu bar has something moving (the breath, or the overtime
    /// blink). It lives on its own tiny object, so the fast pulse redraws the menu-bar
    /// label and nothing else.
    @ObservationIgnored let menuPulse = MenuPulse()
    @ObservationIgnored private var pulseTimer: Timer?

    func syncMenuPulse() {
        let wanted: TimeInterval? = isBreathing ? 1.0 / 12
            : (isOvertime && settings.overtimeAlert && status == .overtime) ? 0.5
            : nil
        guard pulseTimer?.timeInterval != wanted else { return }
        pulseTimer?.invalidate()
        pulseTimer = nil
        guard let wanted else {
            menuPulse.tick &+= 1   // one last redraw so the chip settles
            return
        }
        let pulse = Timer(timeInterval: wanted, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuPulse.tick &+= 1 }
        }
        pulse.tolerance = wanted * 0.1
        RunLoop.main.add(pulse, forMode: .common)
        pulseTimer = pulse
    }

    func load() async {
        do {
            data = try await LocalStore.shared.load()
            applyTheme()
            hasLoaded = true
            startAwayObservers()
            // 0.21.0 stored estimates as pomodoros; they're minutes now.
            if data.todos?.contains(where: { $0.estimate != nil }) == true {
                data.todos = data.todos?.map { todo in
                    var todo = todo
                    if let count = todo.estimate {
                        if todo.minutes == nil { todo.minutes = count * data.settings.focusMinutes }
                        todo.estimate = nil
                    }
                    return todo
                }
            }
            selectedTaskID = data.draft?.taskID ?? tasks.first?.id
            intention = data.draft?.intention ?? ""
            selectedTodoID = data.draft?.todoID
            note = data.draft?.note ?? ""
            noteImages = data.draft?.attachments ?? []
            awaitingNextPhase = data.pendingPhase
            completedFocusCycleCount = FocusSession.mergedBlocks(data.sessions.filter {
                Calendar.current.isDateInToday($0.startedAt)
            }).filter { $0.outcome == .completed }.count
            applyIdleDuration()
            if awaitingNextPhase != nil {
                remainingSeconds = 0
                elapsedSeconds = plannedSeconds
            }
            if let snapshot = data.activeTimer {
                restore(snapshot)
                ensureTicking()
            }
            if data.runStartedAt == nil, data.activeTimer != nil || data.pendingPhase != nil {
                data.runStartedAt = inferredRunStart()
            }
            evaluatePlanProgress()
            synchronizeWidget()
        } catch {
            storageError = "Could not read local data: \(error.localizedDescription)"
        }
    }

    func updateSettings(_ mutate: (inout NonnaSettings) -> Void) {
        let previousAmbientSound = data.settings.ambientSound
        mutate(&data.settings)
        applyTheme()
        if status == .idle { applyIdleDuration() }
        ambientPlayer.setVolume(data.settings.ambientVolume)
        if previousAmbientSound != data.settings.ambientSound {
            syncAmbientPlayback()
        }
        save()
    }

    func previewAmbientSound() {
        let sound = settings.ambientSound
        guard sound != .off else {
            ambientPlayer.stop()
            ambientPreviewToken = nil
            return
        }

        let token = UUID()
        ambientPreviewToken = token
        ambientPlayer.start(sound, volume: settings.ambientVolume)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, self.ambientPreviewToken == token else { return }
            if self.phase == .focus, self.status == .running || self.status == .overtime {
                self.syncAmbientPlayback()
            } else {
                self.ambientPlayer.stop()
                self.ambientPreviewToken = nil
            }
        }
    }

    func addTask(name: String, colorHex: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let task = FocusTask(name: trimmed, colorHex: colorHex)
        data.tasks.append(task)
        // A new list becomes the timer's list only when nothing is running.
        if status == .idle {
            selectedTaskID = task.id
            persistDraft()
        } else {
            save()
        }
    }

    func archiveTask(_ id: UUID) {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        data.tasks[index].isArchived = true
        if selectedTaskID == id { selectedTaskID = tasks.first?.id }
        save()
    }

    func pasteImageFromClipboard() {
        guard let image = NSImage(pasteboard: .general) else {
            storageError = "Copy an image first, then choose Paste image."
            return
        }
        importImages([image])
    }

    func chooseImages() {
        let panel = NSOpenPanel()
        panel.title = "Add images to this session"
        panel.prompt = "Add"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        importImageFiles(panel.urls)
    }

    func importImageFiles(_ urls: [URL]) {
        let images = urls.compactMap { NSImage(contentsOf: $0) }
        guard !images.isEmpty else {
            storageError = "Pomofocus could not read that image."
            return
        }
        importImages(images)
    }

    func updateImageWidth(_ width: Double, for id: UUID) {
        guard let index = noteImages.firstIndex(where: { $0.id == id }) else { return }
        noteImages[index].displayWidth = min(360, max(140, width))
        if status == .idle { persistDraft() }
    }

    func updateImageCaption(_ caption: String, for id: UUID) {
        guard let index = noteImages.firstIndex(where: { $0.id == id }) else { return }
        noteImages[index].caption = caption
        if status == .idle { persistDraft() }
    }

    func moveImage(_ id: UUID, by offset: Int) {
        guard let source = noteImages.firstIndex(where: { $0.id == id }) else { return }
        let destination = min(noteImages.count - 1, max(0, source + offset))
        guard source != destination else { return }
        let attachment = noteImages.remove(at: source)
        noteImages.insert(attachment, at: destination)
        status == .idle ? persistDraft() : persistActiveTimer()
    }

    func removeImage(_ id: UUID) {
        guard let index = noteImages.firstIndex(where: { $0.id == id }) else { return }
        let attachment = noteImages.remove(at: index)
        Task {
            try? await LocalStore.shared.deleteImage(named: attachment.fileName)
        }
        status == .idle ? persistDraft() : persistActiveTimer()
    }

    func persistDraft() {
        guard status == .idle else { return }
        syncDraft()
        // Drafts change on every keystroke; the widget only needs the settled text.
        save(synchronizesWidget: false)
        scheduleWidgetSync()
    }

    @ObservationIgnored private var widgetSyncTask: Task<Void, Never>?

    private func scheduleWidgetSync() {
        widgetSyncTask?.cancel()
        widgetSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.synchronizeWidget()
        }
    }

    func selectPhase(_ selectedPhase: TimerPhase) {
        guard selectedPhase != phase else { return }

        if isBreathing {
            breathingRemaining = 0
            breathingEndsAt = nil
        } else if status != .idle {
            if phase == .focus {
                let outcome: SessionOutcome = elapsedSeconds >= plannedSeconds ? .completed : .finishedEarly
                finish(outcome: outcome, showsReflection: false)
            } else {
                finish(showsReflection: false)
            }
        }

        awaitingNextPhase = nil
        data.pendingPhase = nil
        phase = selectedPhase
        applyIdleDuration()
        persistDraft()
    }

    func openImage(_ attachment: SessionImageAttachment) {
        guard let url = LocalStore.attachmentURL(for: attachment.fileName) else { return }
        NSWorkspace.shared.open(url)
    }

    func start() {
        guard status == .idle else {
            if status == .paused { resume() }
            return
        }
        guard breathingRemaining == 0 else { return }
        if phase == .focus, settings.breathingEnabled {
            breathingRemaining = Self.breathingTotalSeconds
            breathingEndsAt = Date().addingTimeInterval(TimeInterval(Self.breathingTotalSeconds))
            lastTick = Date()
            ensureTicking()
            return
        }
        beginTimer()
    }

    func skipBreathing() {
        guard breathingRemaining > 0 else { return }
        breathingRemaining = 0
        breathingEndsAt = nil
        beginTimer()
    }

    func cancelBreathing() {
        breathingRemaining = 0
        breathingEndsAt = nil
        applyIdleDuration()
        persistDraft()
        stopTickingIfIdle()
    }

    private func beginTimer() {
        breathingRemaining = 0
        breathingEndsAt = nil
        data.draft = nil
        awaitingNextPhase = nil
        data.pendingPhase = nil
        lastOvertimeReminderMark = 0
        let now = Date()
        // A sitting starts with its first block. It runs past midnight happily; only one
        // left idle for many hours is treated as over, so it never swallows the next one.
        if !hasOpenRun {
            data.runStartedAt = now
        }
        sessionStartedAt = now
        lastTick = now
        activityIntervals = [ActivityInterval(startedAt: now, endedAt: nil)]
        elapsedSeconds = 0
        pausedSeconds = 0
        isOvertime = false
        plannedSeconds = duration(for: phase)
        remainingSeconds = plannedSeconds
        status = .running
        requestNotifications()
        play(.start)
        syncAmbientPlayback()
        persistActiveTimer()
        ensureTicking()
    }

    func togglePause() {
        let now = Date()
        switch status {
        case .running, .overtime:
            closeCurrentActivityInterval(at: now)
            refreshTrackedDurations(at: now)
            status = .paused
            play(.pause)
            ambientPlayer.pause()
        case .paused:
            resume(at: now)
        case .idle:
            break
        }
        lastTick = now
        syncMenuPulse()
        persistActiveTimer()
    }

    private func resume(at date: Date = Date()) {
        awayPausedAt = nil
        startActivityInterval(at: date)
        status = isOvertime ? .overtime : .running
        lastTick = date
        play(.resume)
        syncAmbientPlayback()
    }

    func finish(outcome: SessionOutcome? = nil, showsReflection: Bool = true) {
        guard status != .idle, let started = sessionStartedAt else { return }
        let endedAt = Date()
        closeCurrentActivityInterval(at: endedAt)
        refreshTrackedDurations(at: endedAt)
        if phase == .focus {
            let resolved: SessionOutcome = outcome ?? (elapsedSeconds >= plannedSeconds ? .completed : .finishedEarly)
            let session = FocusSession(
                taskID: selectedTaskID,
                taskName: selectedTask?.name ?? "Uncategorized",
                intention: intention.trimmingCharacters(in: .whitespacesAndNewlines),
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                startedAt: started,
                endedAt: endedAt,
                focusedSeconds: elapsedSeconds,
                pausedSeconds: pausedSeconds,
                plannedSeconds: plannedSeconds,
                outcome: resolved,
                focusRating: nil,
                attachments: noteImages.isEmpty ? nil : noteImages,
                activeIntervals: activityIntervals,
                todoID: selectedTodoID
            )
            if elapsedSeconds > 0, !blockSegments.isEmpty {
                // The block switched lists part-way: record each part under its own list.
                let parts = splitParts(of: session)
                data.sessions.append(contentsOf: parts)
                if resolved == .completed { completedFocusCycleCount += 1 }
                evaluatePlanProgress()
                if showsReflection, settings.rateFocus == .everyBlock, let last = parts.last {
                    reflectionRunIDs = parts.map(\.id)
                    reflectionSession = last
                }
            } else if elapsedSeconds > 0 {
                data.sessions.append(session)
                if resolved == .completed { completedFocusCycleCount += 1 }
                evaluatePlanProgress()
                if showsReflection, settings.rateFocus == .everyBlock {
                    reflectionRunIDs = []
                    reflectionSession = session
                }
            }
        } else {
            recordBreakSession(startedAt: started)
        }
        clearTimer()
        save()
    }

    // MARK: - To-dos

    /// The task the timer is working on, if one is linked.
    var selectedTodoID: UUID?

    var todos: [TodoItem] { data.todos ?? [] }

    var selectedTodo: TodoItem? {
        guard let selectedTodoID else { return nil }
        return todos.first { $0.id == selectedTodoID }
    }

    struct TodoStats: Equatable {
        var blocks = 0
        var seconds = 0
    }

    /// Focus blocks and time spent on each task, from the session history.
    func stats(for id: UUID) -> TodoStats {
        let sessions = data.sessions
        if cachedTodoStats == nil {
            var result: [UUID: TodoStats] = [:]
            for session in sessions where session.outcome != .abandoned && session.focusedSeconds > 0 {
                guard let todoID = session.todoID else { continue }
                // A block counts toward the estimate once it's at least half its planned length.
                if session.focusedSeconds * 2 >= max(60, session.plannedSeconds) { result[todoID, default: TodoStats()].blocks += 1 }
                result[todoID, default: TodoStats()].seconds += session.focusedSeconds
            }
            cachedTodoStats = result
        }
        return cachedTodoStats?[id] ?? TodoStats()
    }

    /// Estimated minutes still to go on a task (never below zero).
    func minutesLeft(on todo: TodoItem) -> Int {
        guard let minutes = todo.minutes else { return 0 }
        return max(0, minutes - stats(for: todo.id).seconds / 60)
    }

    @discardableResult
    func addTodo(title: String, listID: UUID?, minutes: Int?, due: Date?) -> UUID {
        addTodo(ParsedTodo(title: title, minutes: minutes, due: due), defaultList: listID, defaultDue: nil)
    }

    @discardableResult
    func addTodo(_ parsed: ParsedTodo, defaultList: UUID?, defaultDue: Date?) -> UUID {
        // A typed #tag files the task into a list you already have. An unknown tag stays in
        // the title rather than quietly creating a new list.
        let existing = parsed.listName.flatMap { name in
            tasks.first { $0.name.caseInsensitiveCompare(name.trimmingCharacters(in: .whitespaces)) == .orderedSame }?.id
        }
        let title = existing == nil ? parsed.listName.map { "\(parsed.title) #\($0)" } ?? parsed.title : parsed.title
        let item = TodoItem(
            title: title,
            listID: existing ?? defaultList,
            minutes: parsed.minutes,
            due: parsed.due ?? defaultDue,
            isDone: parsed.isDone,
            completedAt: parsed.isDone ? Date() : nil
        )
        data.todos = todos + [item]
        save()
        return item.id
    }

    func addTodos(_ parsed: [ParsedTodo], defaultList: UUID?, defaultDue: Date?) {
        let items = parsed.map { entry in
            TodoItem(title: entry.title, listID: entry.listName.map(list(named:)) ?? defaultList, minutes: entry.minutes,
                     due: entry.due ?? defaultDue, isDone: entry.isDone, completedAt: entry.isDone ? Date() : nil)
        }
        data.todos = todos + items
        save()
    }

    func updateTodo(_ id: UUID, _ mutate: (inout TodoItem) -> Void) {
        guard var list = data.todos, let index = list.firstIndex(where: { $0.id == id }) else { return }
        let oldTitle = list[index].title
        mutate(&list[index])
        data.todos = list
        if selectedTodoID == id, status == .idle, phase == .focus, list[index].title != oldTitle { intention = list[index].title }
        save()
    }

    func toggleDone(_ id: UUID) {
        updateTodo(id) { todo in
            todo.isDone.toggle()
            todo.completedAt = todo.isDone ? Date() : nil
        }
        // While a block is running it still counts toward the task; the link clears when it ends.
        if selectedTodoID == id, status == .idle, todos.first(where: { $0.id == id })?.isDone == true { unlinkTodo() }
    }

    /// Removes a list and its tasks. Focus history keeps the list's name.
    func deleteList(_ id: UUID) {
        data.tasks.removeAll { $0.id == id }
        let removed = todos.filter { $0.listID == id }.map(\.id)
        data.todos = todos.filter { $0.listID != id }
        if let linked = selectedTodoID, removed.contains(linked) { unlinkTodo() }
        if selectedTaskID == id { selectedTaskID = tasks.first?.id }
        save()
    }

    /// Asks before deleting a list, unless "Do not ask again" was ticked.
    @discardableResult
    func confirmDeleteList(_ id: UUID) -> Bool {
        guard let list = data.tasks.first(where: { $0.id == id }) else { return false }
        let count = todos.filter { $0.listID == id }.count
        let detail = count == 0
            ? "Your focus history keeps it."
            : "Its \(count) \(count == 1 ? "task is" : "tasks are") deleted too. Your focus history keeps it."
        if DeleteConfirmation.ask(key: "confirmDeleteList", title: "Delete \u{201C}\(list.name)\u{201D}?", detail: detail) {
            deleteList(id)
            return true
        }
        return false
    }

    /// Asks before deleting a task, unless "Do not ask again" was ticked.
    func confirmDeleteTodo(_ id: UUID) {
        guard let todo = todos.first(where: { $0.id == id }) else { return }
        if DeleteConfirmation.ask(key: "confirmDeleteTodo", title: "Delete \u{201C}\(todo.title)\u{201D}?", detail: "This can't be undone.") {
            deleteTodo(id)
        }
    }

    func deleteTodo(_ id: UUID) {
        data.todos = todos.filter { $0.id != id }
        if selectedTodoID == id { unlinkTodo() }
        save()
    }

    /// Links a task to the timer: its list and title become the block's list and intention.
    func linkTodo(_ id: UUID) {
        guard let todo = todos.first(where: { $0.id == id }) else { return }
        // Mid-block with a task already linked: the time so far belongs to that task, so
        // this one waits for the next block.
        if status != .idle, phase == .focus, selectedTodoID != nil, selectedTodoID != id {
            queuedTodoID = id
            return
        }
        queuedTodoID = nil
        splitBlockIfSwitching(toList: todo.listID ?? selectedTaskID, todo: id)
        selectedTodoID = id
        if let listID = todo.listID { selectedTaskID = listID }
        intention = todo.title
        if status == .idle { persistDraft() }
    }

    /// Cuts a finished block into one record per list it was spent on. Planned time is
    /// shared out in proportion, so each part keeps the block's outcome.
    private func splitParts(of session: FocusSession) -> [FocusSession] {
        let intervals = session.activeIntervals ?? []
        var parts: [FocusSession] = []
        var partStart = session.startedAt
        let pieces = blockSegments.map { ($0.taskID, $0.taskName, $0.intention, $0.todoID, $0.endsAt) }
            + [(session.taskID, session.taskName, session.intention, session.todoID, session.endedAt)]
        // Share planned time by each part's measured time, so the parts add up to the block.
        var starts = session.startedAt
        let measured = pieces.map { piece -> Int in
            defer { starts = piece.4 }
            return Int(Self.activeSeconds(in: intervals, from: starts, to: piece.4).rounded())
        }
        let total = max(1, measured.reduce(0, +))
        var plannedLeft = session.plannedSeconds
        let block = UUID()
        for (taskID, taskName, intention, todoID, endsAt) in pieces {
            let clipped = Self.clip(intervals, from: partStart, to: endsAt)
            let focused = Int(clipped.reduce(0) { $0 + $1.duration(through: endsAt) }.rounded())
            if focused > 0 {
                var part = session
                part.id = UUID()
                part.taskID = taskID
                part.taskName = taskName
                part.intention = intention
                part.todoID = todoID
                part.startedAt = partStart
                part.endedAt = endsAt
                part.focusedSeconds = focused
                part.pausedSeconds = max(0, Int(endsAt.timeIntervalSince(partStart)) - focused)
                let share = Int((Double(session.plannedSeconds) * Double(focused) / Double(total)).rounded())
                part.plannedSeconds = max(1, endsAt == session.endedAt ? plannedLeft : min(plannedLeft, share))
                plannedLeft -= part.plannedSeconds
                part.activeIntervals = clipped
                part.blockID = block
                // The note and pictures belong to the block once, not to every part.
                part.note = ""
                part.attachments = nil
                parts.append(part)
            }
            partStart = endsAt
        }
        guard !parts.isEmpty else { return [session] }
        parts[parts.count - 1].note = session.note
        parts[parts.count - 1].attachments = session.attachments
        parts[parts.count - 1].plannedSeconds += max(0, plannedLeft)
        return parts
    }

    /// Picks the list the timer is counting toward. Mid-block, the time so far stays with
    /// the old list and the rest goes to the new one.
    func selectList(_ id: UUID) {
        guard id != selectedTaskID else { return }
        splitBlockIfSwitching(toList: id, todo: selectedTodoID)
        selectedTaskID = id
        persistDraft()
    }

    /// Earlier parts of the running block, oldest first; the current part is the live state.
    @ObservationIgnored var blockSegments: [BlockSegment] = []

    /// Under a minute in, a switch just relabels the block instead of splitting it.
    private static let minimumSplitSeconds: TimeInterval = 60

    private func splitBlockIfSwitching(toList listID: UUID?, todo: UUID?) {
        guard phase == .focus, status != .idle, let started = sessionStartedAt,
              listID != selectedTaskID || todo != selectedTodoID else { return }
        let now = Date()
        let partStart = blockSegments.last?.endsAt ?? started
        let partSeconds = Self.activeSeconds(in: activityIntervals, from: partStart, to: now)
        guard partSeconds >= Self.minimumSplitSeconds else { return }
        blockSegments.append(BlockSegment(
            taskID: selectedTaskID,
            taskName: selectedTask?.name ?? "Uncategorized",
            intention: intention.trimmingCharacters(in: .whitespacesAndNewlines),
            todoID: selectedTodoID,
            endsAt: now
        ))
    }

    /// Active (unpaused) time inside a window.
    static func activeSeconds(in intervals: [ActivityInterval], from start: Date, to end: Date) -> TimeInterval {
        clip(intervals, from: start, to: end).reduce(0) { $0 + $1.duration(through: end) }
    }

    static func clip(_ intervals: [ActivityInterval], from start: Date, to end: Date) -> [ActivityInterval] {
        intervals.compactMap { interval in
            let a = max(interval.startedAt, start)
            let b = min(interval.endedAt ?? end, end)
            return b > a ? ActivityInterval(startedAt: a, endedAt: b) : nil
        }
    }

    /// A task picked while another one's block was running; it's linked when that block ends.
    var queuedTodoID: UUID?

    /// Bumped to ask the window to show the timer, e.g. after starting a task from Tasks.
    var focusScreenRequest = 0

    func unlinkTodo() {
        selectedTodoID = nil
        if status == .idle { persistDraft() }
    }

    /// Starts a focus block on a task (only when nothing is timing).
    func startFocus(on id: UUID) {
        guard status == .idle, !isBreathing else { return }
        if phase != .focus { selectPhase(.focus) }
        awaitingNextPhase = nil
        data.pendingPhase = nil
        linkTodo(id)
        start()
    }

    /// Finds a list by name, ignoring case, or makes a new one.
    func list(named name: String) -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let existing = tasks.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) { return existing.id }
        // An archived list with that name comes back rather than being duplicated.
        if let index = data.tasks.firstIndex(where: { $0.isArchived && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            data.tasks[index].isArchived = false
            return data.tasks[index].id
        }
        let palette = ["BDA56F", "738B80", "A9A4B5", "788897", "8F7581", "6F858F", "837765"]
        let task = FocusTask(name: trimmed, colorHex: palette[data.tasks.count % palette.count])
        data.tasks.append(task)
        return task.id
    }

    func renameList(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = data.tasks.firstIndex(where: { $0.id == id }), data.tasks[index].name != trimmed else { return }
        data.tasks[index].name = trimmed
        save()
    }

    func setListColor(_ id: UUID, to hex: String) {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }), data.tasks[index].colorHex != hex else { return }
        data.tasks[index].colorHex = hex
        save()
    }

    // MARK: - Theme and welcome

    private func applyTheme() {
        ThemeManager.shared.apply(themeID: data.settings.themeID, custom: data.settings.customTheme, saved: data.settings.savedThemes)
    }

    /// Set once the saved data has been read. Until then `data` is the blank starter,
    /// which must not be mistaken for a fresh install.
    private(set) var hasLoaded = false

    /// True on a fresh install until the welcome screen is finished.
    var needsOnboarding: Bool { hasLoaded && !data.settings.hasCompletedOnboarding }

    func completeOnboarding() {
        updateSettings { $0.hasCompletedOnboarding = true }
    }

    // MARK: - Focus plan

    /// Set when the plan changes level; the Focus and Plan screens show it until dismissed.
    var planChange: PlanChange?

    struct PlanChange: Equatable {
        let adjustment: FocusPlan.Adjustment
        let level: FocusPlan.Level
        let isFinal: Bool
    }

    var focusPlan: FocusPlan? { data.focusPlan }

    func startPlan(with answers: FocusPlanAnswers) {
        let plan = FocusPlan.build(from: answers)
        data.focusPlan = plan
        planChange = nil
        applyPlanSettings(plan)
    }

    func setPlanReward(_ reward: String) {
        guard var plan = data.focusPlan, plan.answers.reward != reward else { return }
        plan.answers.reward = reward
        data.focusPlan = plan
        save()
    }

    func removePlan() {
        data.focusPlan = nil
        planChange = nil
        save()
    }

    /// Points the timer at the plan's current level. The breathing ritual stays on: a
    /// calm, identical start is part of the plan.
    private func applyPlanSettings(_ plan: FocusPlan) {
        updateSettings { settings in
            settings.focusMinutes = plan.level.focusMinutes
            settings.shortBreakMinutes = plan.level.breakMinutes
            settings.longBreakMinutes = plan.longBreakMinutes
            settings.longBreakEvery = plan.longBreakEvery
            settings.dailyGoalMinutes = plan.dailyGoalMinutes
            settings.breathingEnabled = true
        }
    }

    /// After each recorded block: climb a rung once it has been earned, or step back one
    /// if the current length keeps beating you.
    private func evaluatePlanProgress() {
        guard var plan = data.focusPlan, let adjustment = plan.adjustment(sessions: data.sessions) else { return }
        plan.levelIndex += adjustment == .levelUp ? 1 : -1
        plan.levelStartedAt = Date()
        data.focusPlan = plan
        planChange = PlanChange(adjustment: adjustment, level: plan.level, isFinal: plan.isFinalLevel)
        applyPlanSettings(plan)
        guard adjustment == .levelUp else {
            let content = UNMutableNotificationContent()
            content.title = "Consolidating at \(plan.level.focusMinutes) minutes"
            content.body = "The last level was a stretch. A few wins at \(plan.level.focusMinutes)-minute blocks will set you up to climb again."
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            return
        }

        let content = UNMutableNotificationContent()
        content.title = plan.isFinalLevel ? "Target reached" : "Level up"
        content.body = plan.isFinalLevel
            ? "\(plan.level.focusMinutes)-minute blocks are yours now. That's the focus you set out to rebuild."
            : "You've earned \(plan.level.focusMinutes)-minute blocks with \(plan.level.breakMinutes)-minute breaks. Your next block uses them."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// Whether there is anything for End session to end.
    var canEndSession: Bool { status != .idle || isBreathing || awaitingNextPhase != nil || hasOpenRun }

    /// A sitting is under way: at least one block has started since the last End session.
    /// It stays open through midnight and through any running or paused timer; it lapses
    /// only after `sittingIdleLimit` with nothing timing.
    var hasOpenRun: Bool {
        guard let started = data.runStartedAt else { return false }
        if status != .idle || isBreathing || awaitingNextPhase != nil { return true }
        let lastActivity = max(
            started,
            data.sessions.last?.endedAt ?? .distantPast,
            data.breaks?.last?.endedAt ?? .distantPast
        )
        return Date().timeIntervalSince(lastActivity) < Self.sittingIdleLimit
    }

    static let sittingIdleLimit: TimeInterval = 8 * 3600

    /// Ends the whole sitting without losing anything. Whatever was tracked is kept (a
    /// focus block is saved as completed or finished early, a break as a break record),
    /// nothing new starts, and the sitting's breakdown is celebrated.
    func endSession() {
        if isBreathing {
            // Nothing has been tracked in this block; keep the intention and notes as a draft.
            cancelBreathing()
            if hasOpenRun { closeRun() }
            return
        }
        if status != .idle {
            if phase == .focus {
                // The celebration covers the end of a sitting; don't stack the reflection on it.
                finish(outcome: elapsedSeconds >= plannedSeconds ? .completed : .finishedEarly,
                       showsReflection: !settings.celebrateSessions)
            } else {
                finish(showsReflection: false)
            }
        }
        awaitingNextPhase = nil
        data.pendingPhase = nil
        if phase != .focus { phase = .focus }
        applyIdleDuration()
        let runStart = data.runStartedAt
        closeRun()
        persistDraft()
        stopTickingIfIdle()
        askForSessionRating(since: runStart)
    }

    /// One rating for the whole sitting, when the user prefers that to rating every block.
    private func askForSessionRating(since runStart: Date?) {
        guard settings.rateFocus == .endOfSession, let runStart else { return }
        let blocks = data.sessions.filter { $0.startedAt >= runStart && $0.outcome != .abandoned && $0.focusedSeconds > 0 }
        guard let last = blocks.last else { return }
        let present = { [weak self] in
            self?.reflectionRunIDs = blocks.map(\.id)
            self?.reflectionSession = last
        }
        // Don't stack the rating on the celebration; ask once it has gone.
        if CelebrationController.shared.isShowing {
            CelebrationController.shared.onDismiss = present
        } else {
            present()
        }
    }

    /// For data saved before sittings were tracked: walk back from the current block
    /// through recent blocks and breaks while each follows the last within 20 minutes.
    private func inferredRunStart() -> Date {
        var start = data.activeTimer?.startedAt ?? Date()
        let records = (data.sessions.map { ($0.startedAt, $0.endedAt) } + (data.breaks ?? []).map { ($0.startedAt, $0.endedAt) })
            .filter { start.timeIntervalSince($0.0) < 18 * 3600 && $0.0 < start }
            .sorted { $0.1 > $1.1 }
        for (startedAt, endedAt) in records {
            guard start.timeIntervalSince(endedAt) < 20 * 60 else { break }
            start = min(start, startedAt)
        }
        return start
    }

    /// Celebrates the sitting that just ended and starts counting a fresh one.
    private func closeRun() {
        guard let started = data.runStartedAt else { return }
        data.runStartedAt = nil
        celebrateRun(since: started)
    }

    func abandon() {
        guard status != .idle else { return }
        discardWorkingImages()
        clearTimer()
        save()
    }

    func advanceToNextPhase() {
        if phase == .focus, isOvertime {
            let breakPhase = upcomingBreakPhase()
            finish(outcome: .completed, showsReflection: false)
            phase = breakPhase
            applyIdleDuration()
            beginTimer()
            return
        }

        if phase != .focus, isOvertime {
            finish(showsReflection: false)
            phase = .focus
            applyIdleDuration()
            beginTimer()
            return
        }

        guard awaitingNextPhase == .focus else { return }
        awaitingNextPhase = nil
        data.pendingPhase = nil
        phase = .focus
        applyIdleDuration()
        beginTimer()
    }

    func skipBreakAndStartFocus() {
        guard phase != .focus || isOvertime else { return }

        if phase == .focus, isOvertime {
            finish(outcome: .completed, showsReflection: false)
        } else if status != .idle {
            finish(showsReflection: false)
        }

        awaitingNextPhase = nil
        data.pendingPhase = nil
        phase = .focus
        applyIdleDuration()
        beginTimer()
    }

    func startBreak() {
        if status != .idle && phase == .focus { finish() }
        phase = nextBreakPhase()
        applyIdleDuration()
        start()
    }

    func startFocus() {
        if status != .idle && phase != .focus { finish(showsReflection: false) }
        phase = .focus
        applyIdleDuration()
        start()
    }

    /// Starts a focus block named after a calendar event. Reads the title only; nothing is written back.
    func startFocus(fromEventTitle title: String) {
        guard status == .idle, !isBreathing else { return }
        if phase != .focus { selectPhase(.focus) }
        awaitingNextPhase = nil
        data.pendingPhase = nil
        intention = title.trimmingCharacters(in: .whitespacesAndNewlines)
        persistDraft()
        start()
    }

    func skipToNextPhase() {
        if phase == .focus { startBreak() } else { skipBreakAndStartFocus() }
    }

    func saveReflection(rating: Int, note: String) {
        guard var reflected = reflectionSession,
              let index = data.sessions.firstIndex(where: { $0.id == reflected.id }) else {
            reflectionSession = nil
            return
        }
        reflected.focusRating = rating
        reflected.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        data.sessions[index] = reflected
        // A session rating covers every block in the sitting.
        for id in reflectionRunIDs where id != reflected.id {
            if let other = data.sessions.firstIndex(where: { $0.id == id }) { data.sessions[other].focusRating = rating }
        }
        reflectionRunIDs = []
        reflectionSession = nil
        save()
    }

    /// Fixes a finished block's name or list, e.g. when it was started under the wrong one.
    func updateSession(id: UUID, intention: String, taskID: UUID?) {
        guard let index = data.sessions.firstIndex(where: { $0.id == id }) else { return }
        var session = data.sessions[index]
        session.intention = intention.trimmingCharacters(in: .whitespacesAndNewlines)
        if session.taskID != taskID {
            session.taskID = taskID
            session.taskName = data.tasks.first { $0.id == taskID }?.name ?? "Uncategorized"
        }
        guard session != data.sessions[index] else { return }
        data.sessions[index] = session
        save()
    }

    func deleteSessions(at offsets: IndexSet) {
        let visible = sessions
        let removed = offsets.map { visible[$0] }
        let ids = removed.map(\.id)
        data.sessions.removeAll { ids.contains($0.id) }
        let stillUsed = Set(data.sessions.flatMap { $0.attachments ?? [] }.map(\.fileName))
        let fileNames = removed.flatMap { $0.attachments ?? [] }.map(\.fileName).filter { !stillUsed.contains($0) }
        Task {
            for fileName in fileNames {
                try? await LocalStore.shared.deleteImage(named: fileName)
            }
        }
        save()
    }

    func exportCSV() throws -> URL {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Pomofocus-Export.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else {
            throw CocoaError(.userCancelled)
        }
        let formatter = ISO8601DateFormatter()
        let focusRows: [(Date, String)] = data.sessions.map { session -> (Date, String) in
            let columns: [String] = [
                "focus",
                formatter.string(from: session.startedAt),
                formatter.string(from: session.endedAt),
                csvEscape(session.taskName),
                csvEscape(session.intention),
                String(session.focusedSeconds),
                String(session.pausedSeconds),
                String(session.plannedSeconds),
                String(max(0, session.focusedSeconds - session.plannedSeconds)),
                session.outcome.rawValue,
                session.focusRating.map(String.init) ?? "",
                csvEscape(session.note),
                String(session.attachments?.count ?? 0)
            ]
            return (session.startedAt, columns.joined(separator: ","))
        }
        let breakRows: [(Date, String)] = (data.breaks ?? []).map { session -> (Date, String) in
            let columns: [String] = [
                "break",
                formatter.string(from: session.startedAt),
                formatter.string(from: session.endedAt),
                csvEscape(session.phase.title),
                "\"\"",
                String(session.restedSeconds),
                String(session.pausedSeconds),
                String(session.plannedSeconds),
                String(session.overtimeSeconds),
                session.wasSkipped ? "skipped" : "completed",
                "",
                "\"\"",
                "0"
            ]
            return (session.startedAt, columns.joined(separator: ","))
        }
        let rows = (focusRows + breakRows).sorted { $0.0 < $1.0 }.map { $0.1 }
        let header = "record_type,started_at,ended_at,task_or_break,intention,duration_seconds,paused_seconds,planned_seconds,overtime_seconds,outcome,focus_rating,note,image_count"
        try ([header] + rows).joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func revealDataFile() async {
        do {
            let url = try await LocalStore.shared.url()
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            storageError = error.localizedDescription
        }
    }

    func persistActiveTimer(synchronizesWidget: Bool = true) {
        guard status != .idle, let started = sessionStartedAt else {
            data.activeTimer = nil
            syncDraft()
            save()
            return
        }
        refreshTrackedDurations(at: Date())
        data.activeTimer = ActiveTimerSnapshot(
            phase: phase,
            status: status,
            taskID: selectedTaskID,
            intention: intention,
            note: note,
            startedAt: started,
            lastSavedAt: Date(),
            remainingSeconds: remainingSeconds,
            elapsedSeconds: elapsedSeconds,
            pausedSeconds: pausedSeconds,
            plannedSeconds: plannedSeconds,
            isOvertime: isOvertime,
            attachments: noteImages.isEmpty ? nil : noteImages,
            activeIntervals: activityIntervals,
            todoID: selectedTodoID,
            segments: blockSegments.isEmpty ? nil : blockSegments
        )
        save(synchronizesWidget: synchronizesWidget)
    }

    private func tick() {
        defer { stopTickingIfIdle() }
        syncMenuPulse()
        if breathingRemaining > 0 {
            let now = Date()
            let remaining = breathingEndsAt.map { max(0, Int(ceil($0.timeIntervalSince(now)))) } ?? 0
            if remaining != breathingRemaining { breathingRemaining = remaining }
            lastTick = now
            if breathingRemaining == 0 { beginTimer() }
            return
        }
        let now = Date()
        guard status == .running || status == .overtime else {
            if status == .paused { refreshTrackedDurations(at: now) }
            lastTick = now
            return
        }
        lastTick = now
        refreshTrackedDurations(at: now)

        if isOvertime {
            if status != .overtime { status = .overtime }
            checkAway(now: now)
            if status == .paused { return }
        } else {
            if remainingSeconds == 0 { timerReachedZero() }
        }

        let chimeEvery = settings.presenceChimeMinutes * 60
        if phase == .focus, settings.playSounds, chimeEvery > 0,
           elapsedSeconds > 0, elapsedSeconds % chimeEvery == 0 {
            play(.presence)
        }
        let overtimeReminderEvery = settings.overtimeReminderMinutes * 60
        if isOvertime, overtimeReminderEvery > 0 {
            let overtimeSeconds = max(0, elapsedSeconds - plannedSeconds)
            let reminderMark = overtimeSeconds / overtimeReminderEvery
            if reminderMark > lastOvertimeReminderMark {
                lastOvertimeReminderMark = reminderMark
                play(.overtimeReminder)
            }
        }
        if elapsedSeconds - lastPersistSecond >= 15 {
            lastPersistSecond = elapsedSeconds
            // Crash recovery wants a fresh snapshot often; the widget already counts
            // down from its end date, so it only needs a nudge once a minute.
            let refreshWidget = elapsedSeconds - lastWidgetSyncSecond >= 60
            if refreshWidget { lastWidgetSyncSecond = elapsedSeconds }
            persistActiveTimer(synchronizesWidget: refreshWidget)
        }
    }

    private func timerReachedZero() {
        play(.complete)
        sendCompletionNotification()
        if phase == .focus, settings.allowOvertime, !settings.autoStartBreaks {
            isOvertime = true
            status = .overtime
            lastOvertimeReminderMark = 0
            persistActiveTimer()
            return
        }

        if phase == .focus {
            finish(outcome: .completed)
            if settings.autoStartBreaks { startBreak() }
        } else if settings.autoStartFocus {
            completeBreak()
            advanceToNextPhase()
        } else {
            isOvertime = true
            status = .overtime
            lastOvertimeReminderMark = 0
            persistActiveTimer()
        }
        syncMenuPulse()
    }

    private func completeBreak() {
        let endedAt = Date()
        closeCurrentActivityInterval(at: endedAt)
        refreshTrackedDurations(at: endedAt)
        if let started = sessionStartedAt { recordBreakSession(startedAt: started, endedAt: endedAt) }
        ambientPlayer.stop()
        ambientPreviewToken = nil
        status = .idle
        awayPausedAt = nil
        isOvertime = false
        sessionStartedAt = nil
        remainingSeconds = 0
        elapsedSeconds = plannedSeconds
        pausedSeconds = 0
        data.activeTimer = nil
        activityIntervals = []
        awaitingNextPhase = .focus
        data.pendingPhase = .focus
        lastPersistSecond = 0
        save()
    }

    private func clearTimer() {
        blockSegments = []
        ambientPlayer.stop()
        ambientPreviewToken = nil
        status = .idle
        awayPausedAt = nil
        breathingRemaining = 0
        breathingEndsAt = nil
        isOvertime = false
        sessionStartedAt = nil
        activityIntervals = []
        data.activeTimer = nil
        awaitingNextPhase = nil
        data.pendingPhase = nil
        lastPersistSecond = 0
        lastWidgetSyncSecond = 0
        lastOvertimeReminderMark = 0
        if phase == .focus {
            note = ""
            noteImages = []
            data.draft = nil
            // Stay on the linked task, so the next block picks up where this one left off.
            if let queued = queuedTodoID, todos.contains(where: { $0.id == queued && !$0.isDone }) {
                queuedTodoID = nil
                linkTodo(queued)
            } else if let todo = selectedTodo, !todo.isDone {
                intention = todo.title
            } else if selectedTodoID != nil {
                // The linked task is done, so its title no longer describes the next block.
                selectedTodoID = nil
                intention = ""
            }
            // A typed intention carries into the next block until it's changed.
            syncDraft()
        }
        applyIdleDuration()
    }

    private func restore(_ snapshot: ActiveTimerSnapshot) {
        awaitingNextPhase = nil
        data.pendingPhase = nil
        phase = snapshot.phase
        status = snapshot.status
        selectedTaskID = snapshot.taskID
        intention = snapshot.intention
        selectedTodoID = snapshot.todoID
        blockSegments = snapshot.segments ?? []
        note = snapshot.note
        noteImages = snapshot.attachments ?? []
        sessionStartedAt = snapshot.startedAt
        plannedSeconds = snapshot.plannedSeconds
        elapsedSeconds = snapshot.elapsedSeconds
        pausedSeconds = snapshot.pausedSeconds
        remainingSeconds = snapshot.remainingSeconds
        isOvertime = snapshot.isOvertime
        activityIntervals = restoredIntervals(from: snapshot)

        let now = Date()
        refreshTrackedDurations(at: now)
        if snapshot.status == .running || snapshot.status == .overtime {
            let supportsOvertime = phase == .focus ? settings.allowOvertime : true
            if elapsedSeconds >= plannedSeconds && supportsOvertime {
                isOvertime = true
                status = .overtime
            }
        }
        // The app was closed (or crashed) with a timer running: if that was a while ago,
        // treat it like stepping away and stop counting at the last save.
        if settings.pauseWhenAway, status == .running || status == .overtime,
           now.timeIntervalSince(snapshot.lastSavedAt) >= TimeInterval(max(1, settings.awayMinutes) * 60) {
            pauseForAway(leftAt: snapshot.lastSavedAt)
        }
        if isOvertime, settings.overtimeReminderMinutes > 0 {
            lastOvertimeReminderMark = max(0, elapsedSeconds - plannedSeconds) / (settings.overtimeReminderMinutes * 60)
        }
        lastTick = now
        syncAmbientPlayback()
    }

    private func duration(for phase: TimerPhase) -> Int {
        switch phase {
        case .focus: min(focusPlan?.reentry(sessions: data.sessions)?.warmupMinutes ?? settings.focusMinutes, settings.focusMinutes) * 60
        case .shortBreak: settings.shortBreakMinutes * 60
        case .longBreak: settings.longBreakMinutes * 60
        }
    }

    private func applyIdleDuration() {
        plannedSeconds = duration(for: phase)
        remainingSeconds = plannedSeconds
        elapsedSeconds = 0
        pausedSeconds = 0
    }

    private func startActivityInterval(at date: Date) {
        if let last = activityIntervals.last, last.endedAt == nil { return }
        activityIntervals.append(ActivityInterval(startedAt: date, endedAt: nil))
    }

    private func closeCurrentActivityInterval(at date: Date) {
        guard let index = activityIntervals.indices.last,
              activityIntervals[index].endedAt == nil else { return }
        activityIntervals[index].endedAt = max(activityIntervals[index].startedAt, date)
    }

    private func refreshTrackedDurations(at date: Date) {
        guard let started = sessionStartedAt else { return }
        let active = activityIntervals.reduce(0.0) { $0 + $1.duration(through: date) }
        let elapsed = max(0, Int(active.rounded(.down)))
        let wallSeconds = max(0, Int(date.timeIntervalSince(started).rounded(.down)))
        let paused = max(0, wallSeconds - elapsed)
        let remaining = max(0, plannedSeconds - elapsed)
        // Only write what moved, so observers are not woken for identical values.
        if elapsed != elapsedSeconds { elapsedSeconds = elapsed }
        if paused != pausedSeconds { pausedSeconds = paused }
        if remaining != remainingSeconds { remainingSeconds = remaining }
    }

    private func restoredIntervals(from snapshot: ActiveTimerSnapshot) -> [ActivityInterval] {
        if var stored = snapshot.activeIntervals, !stored.isEmpty {
            if snapshot.status == .paused,
               let index = stored.indices.last,
               stored[index].endedAt == nil {
                stored[index].endedAt = snapshot.lastSavedAt
            } else if (snapshot.status == .running || snapshot.status == .overtime),
                      stored.last?.endedAt != nil {
                stored.append(ActivityInterval(startedAt: snapshot.lastSavedAt, endedAt: nil))
            }
            return stored
        }

        let tracked = TimeInterval(max(0, snapshot.elapsedSeconds))
        if snapshot.status == .paused {
            let end = min(snapshot.lastSavedAt, snapshot.startedAt.addingTimeInterval(tracked))
            return tracked > 0 ? [ActivityInterval(startedAt: snapshot.startedAt, endedAt: end)] : []
        }

        let inferredStart = snapshot.lastSavedAt.addingTimeInterval(-tracked)
        return [ActivityInterval(startedAt: inferredStart, endedAt: nil)]
    }

    private func nextBreakPhase() -> TimerPhase {
        let interval = max(1, settings.longBreakEvery)
        return completedFocusCycleCount > 0 && completedFocusCycleCount % interval == 0 ? .longBreak : .shortBreak
    }

    private func upcomingBreakPhase() -> TimerPhase {
        let interval = max(1, settings.longBreakEvery)
        let completedAfterCurrentFocus = completedFocusCycleCount + 1
        return completedAfterCurrentFocus % interval == 0 ? .longBreak : .shortBreak
    }

    private func recordBreakSession(startedAt: Date, endedAt: Date = Date()) {
        guard phase != .focus, elapsedSeconds > 0 else { return }
        let record = BreakSession(
            phase: phase,
            startedAt: startedAt,
            endedAt: endedAt,
            restedSeconds: elapsedSeconds,
            pausedSeconds: pausedSeconds,
            plannedSeconds: plannedSeconds,
            wasSkipped: elapsedSeconds < plannedSeconds,
            activeIntervals: activityIntervals
        )
        var records = data.breaks ?? []
        records.append(record)
        data.breaks = records
    }

    @ObservationIgnored private var pendingSave: AppData?
    @ObservationIgnored private var isWriting = false

    /// Writes are coalesced: while one is on disk, further saves just replace the
    /// pending snapshot, and only the newest is written next. Fast typing produces two
    /// writes instead of one per keystroke, and nothing is ever lost or reordered.
    private func save(synchronizesWidget: Bool = true) {
        // Before the data has loaded (or if loading failed), saving would write the empty
        // starter data over the user's file.
        guard hasLoaded else { return }
        if synchronizesWidget {
            widgetSyncTask?.cancel()
            synchronizeWidget()
        }
        pendingSave = data
        guard !isWriting else { return }
        isWriting = true
        Task { await drainPendingSaves() }
    }

    /// Writes everything to disk and waits for it, so the app can quit safely (e.g. to update).
    /// Returns false if the data couldn't be saved (or never loaded), so callers don't quit.
    @discardableResult
    func flushForQuit() async -> Bool {
        guard hasLoaded else { return false }
        storageError = nil
        persistActiveTimer()
        while isWriting || pendingSave != nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return storageError == nil
    }

    private func drainPendingSaves() async {
        while let snapshot = pendingSave {
            pendingSave = nil
            do { try await LocalStore.shared.save(snapshot) }
            catch { storageError = "Could not save local data: \(error.localizedDescription)" }
        }
        isWriting = false
    }

    private func importImages(_ images: [NSImage]) {
        let pending = images.compactMap { image -> (SessionImageAttachment, Data)? in
            guard let data = normalizedPNGData(from: image) else { return nil }
            let attachment = SessionImageAttachment(
                fileName: "\(UUID().uuidString).png",
                displayWidth: min(200, max(160, image.size.width)),
                caption: ""
            )
            return (attachment, data)
        }
        guard !pending.isEmpty else {
            storageError = "Pomofocus could not convert that image."
            return
        }

        Task {
            do {
                for (attachment, imageData) in pending {
                    try await LocalStore.shared.saveImage(imageData, named: attachment.fileName)
                    noteImages.append(attachment)
                }
                status == .idle ? persistDraft() : persistActiveTimer()
            } catch {
                storageError = "Could not save the local image: \(error.localizedDescription)"
            }
        }
    }

    private func normalizedPNGData(from image: NSImage) -> Data? {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let source = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else { return nil }
        let maximumDimension = 2_400.0
        let scale = min(1, maximumDimension / Double(max(source.width, source.height)))
        let width = max(1, Int(Double(source.width) * scale))
        let height = max(1, Int(Double(source.height) * scale))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let resized = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: resized).representation(using: .png, properties: [:])
    }

    private func discardWorkingImages() {
        let fileNames = noteImages.map(\.fileName)
        Task {
            for fileName in fileNames {
                try? await LocalStore.shared.deleteImage(named: fileName)
            }
        }
        noteImages = []
        data.draft = nil
    }

    private func syncDraft() {
        let hasContent = !intention.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !noteImages.isEmpty || selectedTodoID != nil
        data.draft = hasContent
            ? SessionDraft(taskID: selectedTaskID, intention: intention, note: note, attachments: noteImages, todoID: selectedTodoID)
            : nil
    }

    private func syncAmbientPlayback() {
        ambientPreviewToken = nil
        guard phase == .focus, status == .running || status == .overtime else {
            if status != .paused { ambientPlayer.stop() }
            return
        }
        ambientPlayer.start(settings.ambientSound, volume: settings.ambientVolume)
    }

    private func csvEscape(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private enum SoundEvent { case start, pause, resume, complete, presence, overtimeReminder }

    private func play(_ event: SoundEvent) {
        guard settings.playSounds else { return }
        let cue: CueSoundPlayer.Cue = switch event {
        case .start: .start
        case .pause: .pause
        case .resume: .resume
        case .complete: .complete
        case .presence: .presence
        case .overtimeReminder: .overtimeReminder
        }
        cuePlayer.play(cue)
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendCompletionNotification() {
        let content = UNMutableNotificationContent()
        content.title = phase == .focus ? "Brava — time to rest" : "Ready when you are"
        content.body = phase == .focus
            ? "Your focus block is complete. Choose Next when you are ready for a break."
            : "Your break is complete. Choose Next to begin a fresh focus block."
        // The ding already marks the moment, so the banner stays silent unless cues are off.
        content.sound = settings.playSounds ? nil : .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

/// A counter the menu-bar label watches. Kept apart from `AppModel` so its fast ticks
/// (12 Hz while breathing, 2 Hz while blinking) never touch any other view.
@MainActor
@Observable
final class MenuPulse {
    var tick = 0
}

// MARK: - Away guard

extension AppModel {
    /// Seconds since the last keyboard, mouse or trackpad input anywhere on the Mac.
    nonisolated static func secondsSinceLastInput() -> TimeInterval {
        let anyInput = CGEventType(rawValue: ~0) ?? .mouseMoved
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    /// When this block's planned time ran (or will run) out, following its active stretches.
    private func plannedEndDate(now: Date = Date()) -> Date? {
        var left = TimeInterval(plannedSeconds)
        for interval in activityIntervals {
            let length = interval.duration(through: now)
            if length >= left { return interval.startedAt.addingTimeInterval(left) }
            left -= length
        }
        return nil
    }

    /// Called every second while a timer runs over: if nobody has touched the Mac for a
    /// while, stop counting from the moment they left.
    fileprivate func checkAway(now: Date) {
        guard settings.pauseWhenAway, status == .overtime else { return }
        let idle = Self.secondsSinceLastInput()
        guard idle >= TimeInterval(max(1, settings.awayMinutes) * 60) else { return }
        pauseForAway(leftAt: now.addingTimeInterval(-idle))
    }

    /// Pauses the timer as of `leftAt`, but never before the planned time ran out, so a
    /// block always keeps its full length.
    func pauseForAway(leftAt: Date) {
        guard status == .running || status == .overtime else { return }
        let now = Date()
        let cutoff = max(leftAt, plannedEndDate(now: now) ?? leftAt)
        guard cutoff < now else { return }
        closeCurrentActivityInterval(at: cutoff)
        refreshTrackedDurations(at: now)
        status = .paused
        awayPausedAt = cutoff
        ambientPlayer.pause()
        lastTick = now
        syncMenuPulse()
        persistActiveTimer()
    }

    /// "I was here": count the time after an away pause after all and keep going.
    func countAwayTime() {
        guard awayPausedAt != nil, status == .paused,
              let index = activityIntervals.indices.last else { return }
        activityIntervals[index].endedAt = nil
        let now = Date()
        refreshTrackedDurations(at: now)
        if remainingSeconds == 0 { isOvertime = true }
        status = isOvertime ? .overtime : .running
        awayPausedAt = nil
        lastTick = now
        syncAmbientPlayback()
        syncMenuPulse()
        persistActiveTimer()
        ensureTicking()
    }

    /// Sleep and screen lock are the clearest "I've left" signals; the input check above
    /// covers a Mac that just sits there awake.
    fileprivate func startAwayObservers() {
        guard !awayObserversStarted else { return }
        awayObserversStarted = true
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.wentAway() }
        }
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cameBack() }
        }
        distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.wentAway() }
        }
        distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cameBack() }
        }
    }

    private func wentAway() {
        if awayStartedAt == nil { awayStartedAt = Date() }
    }

    private func cameBack() {
        guard let left = awayStartedAt else { return }
        awayStartedAt = nil
        guard settings.pauseWhenAway, status == .running || status == .overtime,
              Date().timeIntervalSince(left) >= TimeInterval(max(1, settings.awayMinutes) * 60) else { return }
        pauseForAway(leftAt: left)
    }

    // MARK: Runaway records

    /// Blocks and breaks from before the guard existed that ran for hours unattended.
    var runawayTimerCount: Int {
        data.sessions.filter { RunawayTimers.isRunaway($0) }.count
            + (data.breaks ?? []).filter { RunawayTimers.isRunaway($0) }.count
    }

    /// Cuts every runaway block and break back to its planned length.
    func trimRunawayTimers() {
        data.sessions = data.sessions.map { RunawayTimers.isRunaway($0) ? RunawayTimers.trimmed($0) : $0 }
        data.breaks = data.breaks?.map { RunawayTimers.isRunaway($0) ? RunawayTimers.trimmed($0) : $0 }
        save()
    }

    // MARK: Focus score

    func focusScore(on day: Date = Date()) -> FocusScore? {
        FocusScore.compute(day: day, sessions: data.sessions, breaks: data.breaks ?? [], goalMinutes: settings.dailyGoalMinutes)
    }

    func focusScoreHistory(days: Int) -> [(day: Date, score: FocusScore?)] {
        FocusScore.history(days: days, sessions: data.sessions, breaks: data.breaks ?? [], goalMinutes: settings.dailyGoalMinutes)
    }
}

/// The standard Mac "are you sure?" alert, with a "Do not ask again" box that is remembered.
@MainActor
enum DeleteConfirmation {
    static func ask(key: String, title: String, detail: String) -> Bool {
        let skipKey = key + ".skip"
        if UserDefaults.standard.bool(forKey: skipKey) { return true }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Do not ask again"
        let confirmed = alert.runModal() == .alertFirstButtonReturn
        if confirmed, alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: skipKey)
        }
        return confirmed
    }
}

// MARK: - Theme codes

extension AppModel {
    /// Adds the theme in a pasted code and switches to it. Returns a sentence for the UI.
    func addTheme(fromCode code: String) -> (ok: Bool, message: String) {
        switch ThemeCodes.theme(from: code) {
        case .failure(let problem):
            return (false, problem.message)
        case .success(let theme):
            updateSettings { settings in
                settings.savedThemes.removeAll { $0.id == theme.id }
                settings.savedThemes.append(theme)
                settings.themeID = theme.themeID
            }
            return (true, theme.isRare ? "A rare theme: \(theme.name). Enjoy it." : "Added \(theme.name).")
        }
    }

    func removeSavedTheme(_ id: UUID) {
        updateSettings { settings in
            settings.savedThemes.removeAll { $0.id == id }
            if settings.themeID == SharedTheme.prefix + id.uuidString { settings.themeID = ThemeChoice.obsidian.rawValue }
        }
    }

    /// A code for the custom theme being built, named after whoever made it.
    func shareCodeForCustomTheme() -> String {
        let name = (UserDefaults.standard.string(forKey: "displayName") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let theme = SharedTheme(id: UUID(), name: name.isEmpty ? "Shared theme" : "\(name)\u{2019}s theme",
                                note: nil, spec: settings.customTheme, isRare: false)
        return ThemeCodes.code(for: theme)
    }
}
