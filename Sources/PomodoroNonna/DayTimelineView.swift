import AppKit
import SwiftUI

struct DayTimelineView: View {
    @Environment(AppModel.self) private var model
    @EnvironmentObject private var calendarStore: CalendarStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    /// The day that was "today" when last checked, so a new day can move the view along.
    @State private var knownToday = Calendar.current.startOfDay(for: Date())
    @State private var selectedEventID: String?
    @Namespace private var daySelection
    /// Where a dragged task would land, while it's over the timeline.
    @State private var dropPreview: Date?

    private let calendar = Calendar.current
    private let hourHeight: CGFloat = 58
    /// When set, the header shows a button that tucks the timeline away.
    private let onCollapse: (() -> Void)?

    init(onCollapse: (() -> Void)? = nil) {
        self.onCollapse = onCollapse
    }

    var body: some View {
        VStack(spacing: 0) {
            timelineHeader
            Divider().overlay(NonnaTheme.line)
            if showsPlanTray {
                planTray
                Divider().overlay(NonnaTheme.line)
            }
            ScrollView(.vertical, showsIndicators: false) {
                // The live block grows about a pixel a minute, so the grid follows this
                // 15-second clock rather than redrawing on every tick of the timer.
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    dayGrid(now: context.date)
                        .padding(.top, 14)
                        .padding(.bottom, 24)
                }
            }
        }
        .background(NonnaTheme.sunken.opacity(0.72).ignoresSafeArea())
    }

    private var timelineHeader: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Button { moveDay(by: -1) } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(TimelineHeaderButtonStyle())

                Text(dayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)

                Button { moveDay(by: 1) } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(TimelineHeaderButtonStyle())

                if let onCollapse {
                    Button(action: onCollapse) {
                        Image(systemName: "sidebar.right")
                    }
                    .buttonStyle(TimelineHeaderButtonStyle())
                    .keyboardShortcut("t", modifiers: [.command, .option])
                    .help("Hide the timeline (⌥⌘T)")
                    .accessibilityLabel("Hide the timeline")
                }
            }

            HStack(spacing: 6) {
                ForEach(weekDays, id: \.self) { day in
                    Button {
                        withAnimation(reduceMotion ? nil : NonnaMotion.selection) { selectedDay = day }
                    } label: {
                        ZStack {
                            if calendar.isDate(day, inSameDayAs: selectedDay) {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(NonnaTheme.raisedPaper)
                                    .matchedGeometryEffect(id: "selected-day", in: daySelection)
                            }
                            VStack(spacing: 3) {
                                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(NonnaTheme.secondaryInk)
                                Text(day.formatted(.dateTime.day()))
                                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                                Text((weekTotals[calendar.startOfDay(for: day)] ?? 0).timelineDuration)
                                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                                    .foregroundStyle(NonnaTheme.secondaryInk)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(calendar.isDate(day, inSameDayAs: selectedDay) ? NonnaTheme.strongLine : NonnaTheme.line.opacity(0.7), lineWidth: 0.8)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                }
            }
            .onAppear { showToday() }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in followNewDay() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in followNewDay() }

            HStack(spacing: 14) {
                Label("\(dayFocusSessions.count)", systemImage: "arrow.up.right")
                Label("\(dayBreakSessions.count)", systemImage: "cup.and.saucer")
                if model.settings.showCalendarEvents {
                    Label(calendarTimelineStatus, systemImage: calendarTimelineIcon)
                        .foregroundStyle(calendarTimelineColor)
                        .help(calendarTimelineHelp)
                }
                Spacer()
                Text(focusSeconds(on: selectedDay).focusDurationString + " focus")
                if breakOvertimeSeconds > 0 {
                    Text("+")
                    Text(breakOvertimeSeconds.focusDurationString + " break overtime")
                        .foregroundStyle(NonnaTheme.gold)
                }
            }
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(NonnaTheme.secondaryInk)

            if !allDayEvents.isEmpty {
                allDayRow
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var allDayRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("All day")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(NonnaTheme.secondaryInk)
                ForEach(allDayEvents) { event in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(event.color)
                            .frame(width: 5, height: 5)
                        Text(event.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(event.color.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay { Capsule().stroke(event.color.opacity(0.35), lineWidth: 0.8) }
                    .help("\(event.calendarName), all day")
                }
            }
        }
    }

    private func dayGrid(now: Date) -> some View {
        let entries = timelineEntries(now: now)
        let range = visibleHourRange(for: entries)
        let height = CGFloat(range.count) * hourHeight
        let placedEvents = placeEvents(timedEvents)

        return GeometryReader { proxy in
        let contentWidth = max(120, proxy.size.width - 68 - 14)
        let sessionInset: CGFloat = placedEvents.isEmpty ? 0 : contentWidth * 0.36
        ZStack(alignment: .topLeading) {
            ForEach(Array(range), id: \.self) { hour in
                HStack(spacing: 10) {
                    Text(hourLabel(hour))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(NonnaTheme.secondaryInk)
                        .frame(width: 52, alignment: .trailing)
                    Rectangle()
                        .fill(NonnaTheme.line.opacity(0.72))
                        .frame(height: 0.8)
                }
                .offset(y: CGFloat(hour - range.lowerBound) * hourHeight)
            }

            // Calendar events sit behind everything you tracked. They are read-only.
            ForEach(placedEvents) { placed in
                let position = blockPosition(from: placed.event.startedAt, to: placed.event.endedAt, in: range)
                let columnWidth = contentWidth / CGFloat(placed.columnCount)
                CalendarEventBlock(
                    event: placed.event,
                    isSelected: selectedEventID == placed.event.id,
                    canStartFocus: model.status == .idle && !model.isBreathing,
                    onSelect: { selectedEventID = placed.event.id },
                    onDismiss: { if selectedEventID == placed.event.id { selectedEventID = nil } },
                    onStartFocus: {
                        selectedEventID = nil
                        model.startFocus(fromEventTitle: placed.event.title)
                    }
                )
                .frame(width: max(24, columnWidth - 2), height: position.height)
                .offset(x: 68 + CGFloat(placed.column) * columnWidth, y: position.y)
            }

            // Tasks planned for this day, behind what you actually tracked.
            ForEach(scheduledHere) { todo in
                if let start = todo.scheduledAt {
                    let position = blockPosition(from: start, to: start.addingTimeInterval(TimeInterval(todo.plannedMinutes * 60)), in: range)
                    PlannedTaskBlock(
                        todo: todo,
                        list: model.data.tasks.first { $0.id == todo.listID },
                        canStart: calendar.isDateInToday(selectedDay) && model.status == .idle && !model.isBreathing
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: max(22, position.height))
                    .padding(.leading, 68 + sessionInset)
                    .padding(.trailing, 14)
                    .offset(y: position.y)
                }
            }

            if let preview = dropPreview {
                let y = blockPosition(from: preview, to: preview.addingTimeInterval(60), in: range).y
                HStack(spacing: 6) {
                    Text(preview.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 5)
                        .frame(height: 18)
                        .background(NonnaTheme.ink)
                        .foregroundStyle(NonnaTheme.cream)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    Rectangle()
                        .fill(NonnaTheme.ink.opacity(0.6))
                        .frame(height: 1.5)
                }
                .offset(x: 4, y: y - 9)
                .allowsHitTesting(false)
            }

            ForEach(entries) { entry in
                let position = blockPosition(for: entry, in: range)
                TimelineEntryBlock(entry: entry)
                    .frame(maxWidth: .infinity)
                    .frame(height: position.height)
                    .padding(.leading, 68 + sessionInset)
                    .padding(.trailing, 14)
                    .offset(y: position.y)
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
            }

            if let currentY = currentTimePosition(in: range) {
                HStack(spacing: 6) {
                    Text(Date().formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 5)
                        .frame(height: 18)
                        .background(NonnaTheme.terracotta)
                        .foregroundStyle(NonnaTheme.onAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    Rectangle()
                        .fill(NonnaTheme.terracotta)
                        .frame(height: 1)
                }
                .offset(x: 4, y: currentY - 9)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        .contentShape(Rectangle())
        .onDrop(of: [.text], delegate: TimelineDropDelegate(
            time: { y in dropTime(atY: y, in: range) },
            preview: $dropPreview,
            onDrop: { id, start in
                withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.1)) { model.schedule(id, at: start) }
            }
        ))
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.1), value: scheduledHere.map(\.scheduledAt))
        .animation(reduceMotion ? nil : NonnaMotion.page, value: selectedDay)
        // Blocks animate when they appear, split, or finish. The live block grows about a
        // pixel a minute, so animating every second of that kept the whole timeline
        // redrawing for motion no one could see.
        .animation(reduceMotion ? nil : .linear(duration: 0.82), value: entries.map(\.id))
        }
        .frame(height: height)
    }

    private var dayCalendarEvents: [CalendarEvent] {
        guard model.settings.showCalendarEvents else { return [] }
        return calendarStore.events(on: selectedDay, hiddenIDs: model.settings.hiddenCalendarIDs)
    }

    private var timedEvents: [CalendarEvent] { dayCalendarEvents.filter { !$0.isAllDay } }
    private var allDayEvents: [CalendarEvent] { dayCalendarEvents.filter(\.isAllDay) }

    private var calendarTimelineStatus: String {
        switch calendarStore.access {
        case .granted: "Calendar"
        case .notDetermined: "Calendar setup"
        case .denied: "Calendar off"
        }
    }

    private var calendarTimelineIcon: String {
        switch calendarStore.access {
        case .granted: "calendar.badge.checkmark"
        case .notDetermined: "calendar.badge.exclamationmark"
        case .denied: "calendar.badge.minus"
        }
    }

    private var calendarTimelineColor: Color {
        switch calendarStore.access {
        case .granted: NonnaTheme.sage
        case .notDetermined: NonnaTheme.gold
        case .denied: NonnaTheme.alert
        }
    }

    private var calendarTimelineHelp: String {
        switch calendarStore.access {
        case .granted: "Calendar overlay connected"
        case .notDetermined: "Allow calendar access in Settings"
        case .denied: "Reconnect calendar access in Settings"
        }
    }

    /// Gives overlapping calendar events their own columns so none hides another.
    private func placeEvents(_ events: [CalendarEvent]) -> [PlacedCalendarEvent] {
        var result: [PlacedCalendarEvent] = []
        var cluster: [(event: CalendarEvent, column: Int)] = []
        var columnEnds: [Date] = []
        var clusterEnd = Date.distantPast

        func flush() {
            let count = max(1, columnEnds.count)
            result += cluster.map { PlacedCalendarEvent(event: $0.event, column: $0.column, columnCount: count) }
            cluster = []
            columnEnds = []
            clusterEnd = .distantPast
        }

        for event in events.sorted(by: { $0.startedAt < $1.startedAt }) {
            if !cluster.isEmpty, event.startedAt >= clusterEnd { flush() }
            if let free = columnEnds.firstIndex(where: { $0 <= event.startedAt }) {
                columnEnds[free] = event.endedAt
                cluster.append((event: event, column: free))
            } else {
                columnEnds.append(event.endedAt)
                cluster.append((event: event, column: columnEnds.count - 1))
            }
            clusterEnd = max(clusterEnd, event.endedAt)
        }
        flush()
        return result
    }

    private var dayTitle: String {
        if calendar.isDateInToday(selectedDay) { return "Today" }
        return selectedDay.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private var weekDays: [Date] {
        let weekday = calendar.component(.weekday, from: selectedDay)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let weekStart = calendar.date(byAdding: .day, value: -offset, to: selectedDay) ?? selectedDay
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var dayFocusSessions: [FocusSession] {
        model.sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: selectedDay) && $0.outcome != .abandoned }
    }

    private var dayBreakSessions: [BreakSession] {
        model.breakSessions.filter { calendar.isDate($0.startedAt, inSameDayAs: selectedDay) }
    }

    private var breakOvertimeSeconds: Int {
        dayBreakSessions.reduce(0) { $0 + $1.overtimeSeconds }
    }

    private func timelineEntries(now: Date) -> [TimelineEntry] {
        var result = dayFocusSessions.flatMap { session in
            let intervals = focusIntervals(for: session)
            return intervals.enumerated().compactMap { index, interval -> TimelineEntry? in
                guard let endedAt = interval.endedAt,
                      calendar.isDate(interval.startedAt, inSameDayAs: selectedDay) else { return nil }
                let intervalSeconds = max(1, Int(endedAt.timeIntervalSince(interval.startedAt)))
                let overtime = index == intervals.indices.last ? max(0, session.focusedSeconds - session.plannedSeconds) : 0
                return TimelineEntry(
                    id: "focus-\(session.id.uuidString)-\(index)",
                    title: session.intention.isEmpty ? session.taskName : session.intention,
                    subtitle: session.taskName,
                    startedAt: interval.startedAt,
                    endedAt: endedAt,
                    color: NonnaTheme.taskColor(for: model.data.tasks.first(where: { $0.id == session.taskID })?.colorHex ?? "BDA56F"),
                    overtimeSeconds: overtime >= 60 ? overtime : 0,
                    totalSeconds: intervalSeconds,
                    projectionProgress: nil,
                    isBreak: false,
                    isActive: false
                )
            }
        }

        result += dayBreakSessions.flatMap { session in
            let intervals = breakIntervals(for: session)
            return intervals.enumerated().compactMap { index, interval -> TimelineEntry? in
                guard let endedAt = interval.endedAt,
                      calendar.isDate(interval.startedAt, inSameDayAs: selectedDay) else { return nil }
                let intervalSeconds = max(1, Int(endedAt.timeIntervalSince(interval.startedAt)))
                return TimelineEntry(
                    id: "break-\(session.id.uuidString)-\(index)",
                    title: session.phase == .longBreak ? "Long break" : "Break",
                    subtitle: session.wasSkipped ? "Skipped early" : "Rest",
                    startedAt: interval.startedAt,
                    endedAt: endedAt,
                    color: NonnaTheme.sage,
                    overtimeSeconds: index == intervals.indices.last ? session.overtimeSeconds : 0,
                    totalSeconds: intervalSeconds,
                    projectionProgress: nil,
                    isBreak: true,
                    isActive: false
                )
            }
        }

        if model.status == .idle,
           model.awaitingNextPhase == nil,
           calendar.isDateInToday(selectedDay) {
            let start = now
            result.append(
                TimelineEntry(
                    id: "projected-timer",
                    title: model.phase == .focus ? (model.intention.isEmpty ? "Focus" : model.intention) : (model.phase == .longBreak ? "Long break" : "Break"),
                    subtitle: "Planned",
                    startedAt: start,
                    endedAt: start.addingTimeInterval(TimeInterval(model.plannedSeconds)),
                    color: NonnaTheme.accent(for: model.phase),
                    overtimeSeconds: 0,
                    totalSeconds: model.plannedSeconds,
                    projectionProgress: 0,
                    isBreak: model.phase != .focus,
                    isActive: false
                )
            )
        } else if model.status != .idle, !model.isBreathing {
            let intervals = model.activityIntervals
            // Derived from the intervals at `now`, not from the model's per-second
            // counters, so reading them does not subscribe the grid to every tick.
            let elapsed = Int(intervals.reduce(0.0) { $0 + $1.duration(through: now) })
            let remaining = max(0, model.plannedSeconds - elapsed)
            for (index, interval) in intervals.enumerated() {
                guard calendar.isDate(interval.startedAt, inSameDayAs: selectedDay) else { continue }
                let isOpen = interval.endedAt == nil
                let actualEnd = interval.endedAt ?? now
                let isPausedMarker = model.status == .paused && index == intervals.indices.last
                let displayEnd: Date
                let projectionProgress: Double?

                if isOpen && !model.isOvertime {
                    displayEnd = now.addingTimeInterval(TimeInterval(remaining))
                    let worked = max(0, now.timeIntervalSince(interval.startedAt))
                    let projected = max(1, displayEnd.timeIntervalSince(interval.startedAt))
                    projectionProgress = min(1, worked / projected)
                } else {
                    displayEnd = actualEnd
                    projectionProgress = isOpen ? 1 : nil
                }

                result.append(
                    TimelineEntry(
                        id: "active-timer-\(index)",
                        title: model.phase == .focus ? (model.intention.isEmpty ? "Focus" : model.intention) : (model.phase == .longBreak ? "Long break" : "Break"),
                        subtitle: isPausedMarker ? "Paused" : (isOpen ? "Live" : (model.phase == .focus ? "Focus" : "Rest")),
                        startedAt: interval.startedAt,
                        endedAt: displayEnd,
                        color: NonnaTheme.accent(for: model.phase),
                        overtimeSeconds: isOpen ? max(0, elapsed - model.plannedSeconds) : 0,
                        totalSeconds: max(1, Int(actualEnd.timeIntervalSince(interval.startedAt))),
                        projectionProgress: projectionProgress,
                        isBreak: model.phase != .focus,
                        isActive: isOpen || isPausedMarker
                    )
                )
            }
        }

        return result.sorted { $0.startedAt < $1.startedAt }
    }

    private func focusIntervals(for session: FocusSession) -> [ActivityInterval] {
        if let intervals = session.activeIntervals, !intervals.isEmpty { return intervals }
        let inferredEnd = min(session.endedAt, session.startedAt.addingTimeInterval(TimeInterval(session.focusedSeconds)))
        return [ActivityInterval(startedAt: session.startedAt, endedAt: inferredEnd)]
    }

    private func breakIntervals(for session: BreakSession) -> [ActivityInterval] {
        if let intervals = session.activeIntervals, !intervals.isEmpty { return intervals }
        let inferredEnd = min(session.endedAt, session.startedAt.addingTimeInterval(TimeInterval(session.restedSeconds)))
        return [ActivityInterval(startedAt: session.startedAt, endedAt: inferredEnd)]
    }

    private func visibleHourRange(for entries: [TimelineEntry]) -> Range<Int> {
        let dayStart = calendar.startOfDay(for: selectedDay)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        let eventStartHours = timedEvents.map { $0.startedAt < dayStart ? 0 : calendar.component(.hour, from: $0.startedAt) }
        let eventEndHours = timedEvents.map { $0.endedAt >= nextDay ? 24 : calendar.component(.hour, from: $0.endedAt) + 1 }
        let planned = scheduledHere.compactMap(\.scheduledAt)
        let plannedStart = planned.map { calendar.component(.hour, from: $0) }
        let plannedEnd = scheduledHere.compactMap { todo in
            todo.scheduledAt.map { calendar.component(.hour, from: $0.addingTimeInterval(TimeInterval(todo.plannedMinutes * 60))) + 1 }
        }
        let earliest = (entries.map { calendar.component(.hour, from: $0.startedAt) } + eventStartHours + plannedStart).min() ?? 9
        let latest = (entries.map { calendar.component(.hour, from: $0.endedAt) + 1 } + eventEndHours + plannedEnd).max() ?? 21
        let start = max(0, min(8, earliest))
        let end = min(24, max(22, latest))
        return start..<max(start + 1, end)
    }

    private func blockPosition(for entry: TimelineEntry, in range: Range<Int>) -> (y: CGFloat, height: CGFloat) {
        blockPosition(from: entry.startedAt, to: entry.endedAt, in: range)
    }

    private func blockPosition(from startedAt: Date, to endedAt: Date, in range: Range<Int>) -> (y: CGFloat, height: CGFloat) {
        let dayStart = calendar.startOfDay(for: selectedDay)
        let visibleStart = calendar.date(byAdding: .hour, value: range.lowerBound, to: dayStart) ?? dayStart
        let start = max(startedAt, visibleStart)
        let endOfRange = calendar.date(byAdding: .hour, value: range.upperBound, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        let end = min(max(endedAt, start.addingTimeInterval(60)), endOfRange)
        let y = CGFloat(start.timeIntervalSince(visibleStart) / 3_600) * hourHeight
        let rawHeight = CGFloat(end.timeIntervalSince(start) / 3_600) * hourHeight
        return (max(0, y), max(3, rawHeight))
    }

    private func currentTimePosition(in range: Range<Int>) -> CGFloat? {
        guard calendar.isDateInToday(selectedDay) else { return nil }
        let dayStart = calendar.startOfDay(for: selectedDay)
        let visibleStart = calendar.date(byAdding: .hour, value: range.lowerBound, to: dayStart) ?? dayStart
        let visibleEnd = calendar.date(byAdding: .hour, value: range.upperBound, to: dayStart) ?? dayStart
        let now = Date()
        guard now >= visibleStart, now <= visibleEnd else { return nil }
        return CGFloat(now.timeIntervalSince(visibleStart) / 3_600) * hourHeight
    }

    /// Focus per day for the visible week, gathered in one pass over the history.
    private var weekTotals: [Date: Int] {
        let days = weekDays
        guard let first = days.first, let last = days.last,
              let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) else { return [:] }
        let start = calendar.startOfDay(for: first)
        var totals: [Date: Int] = [:]
        for session in model.sessions where session.outcome != .abandoned {
            if session.startedAt < start { break }   // newest first, so the rest are older
            guard session.startedAt < end else { continue }
            totals[calendar.startOfDay(for: session.startedAt), default: 0] += session.focusedSeconds
        }
        return totals
    }

    private func focusSeconds(on day: Date) -> Int {
        model.sessions
            .filter { calendar.isDate($0.startedAt, inSameDayAs: day) && $0.outcome != .abandoned }
            .reduce(0) { $0 + $1.focusedSeconds }
    }

    /// Opening the timeline always starts on today.
    private func showToday() {
        knownToday = calendar.startOfDay(for: Date())
        selectedDay = knownToday
    }

    /// After midnight (or waking the Mac on a later day), move on from yesterday unless
    /// another day was picked on purpose.
    private func followNewDay() {
        let today = calendar.startOfDay(for: Date())
        guard today != knownToday else { return }
        if calendar.isDate(selectedDay, inSameDayAs: knownToday) { selectedDay = today }
        knownToday = today
    }

    // MARK: Planning

    private var scheduledHere: [TodoItem] { model.scheduledTodos(on: selectedDay) }

    /// Planning only makes sense for today and later.
    private var showsPlanTray: Bool {
        selectedDay >= calendar.startOfDay(for: Date()) && !model.planCandidates(for: selectedDay).isEmpty
    }

    /// Tasks you could do this day. Drag one onto a time, or let Plan my day fill the gaps.
    private var planTray: some View {
        let candidates = model.planCandidates(for: selectedDay)
        let dayStart = calendar.startOfDay(for: selectedDay)
        let dueCount = candidates.filter { ($0.due.map { $0 <= dayStart }) ?? false }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Drag a task onto a time")
                    .font(.system(size: 11))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                Spacer()
                if dueCount > 0 {
                    Button {
                        let busy = timedEvents.map { DayPlanner.Slot(start: $0.startedAt, end: $0.endedAt) }
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.1)) {
                            model.planDay(selectedDay, busy: busy)
                        }
                    } label: {
                        Label("Plan my day", systemImage: "calendar.badge.clock")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(NonnaTheme.terracotta)
                    .help("Fit the \(dueCount) \(dueCount == 1 ? "task" : "tasks") due by this day into its free time")
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(candidates.prefix(20)) { todo in
                        PlanChip(todo: todo, list: model.data.tasks.first { $0.id == todo.listID }, isDue: (todo.due.map { $0 <= dayStart }) ?? false)
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// The time under a point on the grid, to the nearest quarter hour.
    private func dropTime(atY y: CGFloat, in range: Range<Int>) -> Date {
        let dayStart = calendar.startOfDay(for: selectedDay)
        let minutes = Double(range.lowerBound * 60) + Double(max(0, y)) / Double(hourHeight) * 60
        let snapped = Int((minutes / 15).rounded()) * 15
        let clamped = min(max(snapped, range.lowerBound * 60), range.upperBound * 60 - 15)
        return calendar.date(byAdding: .minute, value: clamped, to: dayStart) ?? dayStart.addingTimeInterval(TimeInterval(clamped * 60))
    }

    private func moveDay(by offset: Int) {
        withAnimation(reduceMotion ? nil : NonnaMotion.selection) {
            selectedDay = calendar.date(byAdding: .day, value: offset, to: selectedDay) ?? selectedDay
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = calendar.date(from: DateComponents(hour: hour)) ?? Date()
        return date.formatted(.dateTime.hour())
    }
}

private struct PlacedCalendarEvent: Identifiable {
    let event: CalendarEvent
    let column: Int
    let columnCount: Int
    var id: String { event.id }
}

private struct CalendarEventBlock: View {
    let event: CalendarEvent
    let isSelected: Bool
    let canStartFocus: Bool
    let onSelect: () -> Void
    let onDismiss: () -> Void
    let onStartFocus: () -> Void

    var body: some View {
        Button(action: onSelect) {
            GeometryReader { proxy in
                HStack(alignment: .top, spacing: 6) {
                    Rectangle()
                        .fill(event.color.opacity(0.85))
                        .frame(width: 2.5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(NonnaTheme.ink.opacity(0.78))
                            .lineLimit(proxy.size.height < 40 ? 1 : 2)
                        if proxy.size.height >= 30 {
                            Text(timeRange)
                                .font(.system(size: 9, weight: .medium).monospacedDigit())
                                .foregroundStyle(NonnaTheme.secondaryInk)
                                .lineLimit(1)
                        }
                    }
                    .padding(.top, proxy.size.height < 20 ? 1 : 5)
                    Spacer(minLength: 0)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .background(event.color.opacity(isSelected ? 0.22 : 0.11))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(event.color.opacity(isSelected ? 0.7 : 0.3), lineWidth: 0.8)
                }
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .help("\(event.title), \(event.calendarName)")
        .popover(
            isPresented: Binding(get: { isSelected }, set: { if !$0 { onDismiss() } }),
            arrowEdge: .leading
        ) {
            detail
        }
    }

    private var timeRange: String {
        "\(event.startedAt.formatted(date: .omitted, time: .shortened))–\(event.endedAt.formatted(date: .omitted, time: .shortened))"
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(event.title)
                    .font(.system(size: 14, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(timeRange)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            HStack(spacing: 6) {
                Circle()
                    .fill(event.color)
                    .frame(width: 7, height: 7)
                Text(event.calendarName)
                    .font(.system(size: 11))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            if !event.location.isEmpty {
                Label(event.location, systemImage: "mappin.and.ellipse")
                    .font(.system(size: 11))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .lineLimit(2)
            }
            Button(action: onStartFocus) {
                Label("Start focus", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NonnaButtonStyle())
            .disabled(!canStartFocus)
            Text(canStartFocus ? "Read-only. Nothing is written to your calendar." : "Finish the current timer first.")
                .font(.system(size: 11))
                .foregroundStyle(NonnaTheme.secondaryInk)
        }
        .padding(16)
        .frame(width: 250)
        .background(NonnaTheme.cream)
        .foregroundStyle(NonnaTheme.ink)
        .environment(\.colorScheme, .dark)
    }
}

private struct TimelineEntry: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let startedAt: Date
    let endedAt: Date
    let color: Color
    let overtimeSeconds: Int
    let totalSeconds: Int
    let projectionProgress: Double?
    let isBreak: Bool
    let isActive: Bool
}

private struct TimelineEntryBlock: View {
    let entry: TimelineEntry
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(baseOpacity)

                if let progress = entry.projectionProgress {
                    VStack(spacing: 0) {
                        if progress > 0 {
                            entry.color.opacity(entry.isBreak ? 0.42 : 0.72)
                                .frame(height: proxy.size.height * progress)
                        }
                        ProjectedHatch(color: entry.color)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }

                if entry.overtimeSeconds > 0 {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        OvertimeHatch(color: entry.color)
                            .frame(height: overtimeHeight(in: proxy.size.height))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }

                if !isPreview {
                    HStack(alignment: proxy.size.height < 34 ? .center : .top) {
                        if proxy.size.height < 34 {
                            Text(entry.title)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Text(entry.subtitle)
                                .font(.system(size: 9, weight: .medium).monospacedDigit())
                                .foregroundStyle(NonnaTheme.ink.opacity(0.68))
                                .lineLimit(1)
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title)
                                    .font(.system(size: 10, weight: .semibold))
                                    .lineLimit(1)
                                Text(detail)
                                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                                    .foregroundStyle(NonnaTheme.ink.opacity(0.72))
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        if entry.isActive {
                            activeIndicator
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(maxHeight: .infinity, alignment: proxy.size.height < 34 ? .center : .top)
                    .padding(.vertical, proxy.size.height < 34 ? 0 : 6)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(entry.color.opacity(0.8), lineWidth: 0.8)
            }
            .shadow(color: entry.isActive ? entry.color.opacity(0.14) : .clear, radius: 9, y: 3)
        }
    }

    private var isPreview: Bool {
        entry.projectionProgress == 0 && !entry.isActive
    }

    private var baseOpacity: Color {
        entry.color.opacity(entry.projectionProgress == nil ? (entry.isBreak ? 0.34 : 0.72) : 0.12)
    }

    private var activeIndicator: some View {
        ZStack {
            LivePulseRing(color: NSColor(entry.color.opacity(0.52)), animates: !reduceMotion)
                .frame(width: 16, height: 16)
                .frame(width: 8, height: 8)
                .allowsHitTesting(false)
            Circle()
                .fill(NonnaTheme.ink)
                .frame(width: 5, height: 5)
        }
    }

    private var detail: String {
        let range = "\(entry.startedAt.formatted(date: .omitted, time: .shortened))–\(entry.endedAt.formatted(date: .omitted, time: .shortened))"
        if entry.overtimeSeconds > 0 {
            return "\(range), +\(entry.overtimeSeconds.timelineDuration) OT"
        }
        return "\(range), \(entry.subtitle)"
    }

    private func overtimeHeight(in totalHeight: CGFloat) -> CGFloat {
        let fraction = min(1, Double(entry.overtimeSeconds) / Double(max(1, entry.totalSeconds)))
        return max(8, totalHeight * fraction)
    }
}

private struct ProjectedHatch: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color.opacity(0.22)))
            var x = -size.height
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(path, with: .color(color.opacity(0.34)), lineWidth: 1)
                x += 7
            }
        }
    }
}

private struct OvertimeHatch: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color.opacity(0.5)))
            var x = -size.height
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(path, with: .color(NonnaTheme.ink.opacity(0.22)), lineWidth: 2)
                x += 8
            }
        }
    }
}

private struct TimelineHeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .frame(width: 32, height: 32)
            .background(configuration.isPressed ? NonnaTheme.strongLine : NonnaTheme.raisedPaper)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 8).stroke(NonnaTheme.line, lineWidth: 0.8) }
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(NonnaMotion.quick, value: configuration.isPressed)
    }
}

private extension Int {
    var timelineDuration: String {
        if self <= 0 { return "0m" }
        if self < 60 { return "<1m" }
        let minutes = self / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }
}

/// The ripple behind the live block's dot. It runs as a Core Animation layer animation,
/// which the window server composites on its own: the same 1.8 s ease-out ripple, without
/// SwiftUI re-rendering the window on every display frame for the whole session.
private struct LivePulseRing: NSViewRepresentable {
    let color: NSColor
    let animates: Bool

    private static let animationKey = "live-pulse"

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        view.wantsLayer = true
        let ring = CALayer()
        ring.bounds = CGRect(x: 0, y: 0, width: 8, height: 8)
        ring.cornerRadius = 4
        view.layer?.addSublayer(ring)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let host = view.layer, let ring = host.sublayers?.first else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.position = CGPoint(x: host.bounds.midX, y: host.bounds.midY)
        ring.backgroundColor = color.cgColor
        CATransaction.commit()

        if animates {
            guard ring.animation(forKey: Self.animationKey) == nil else { return }
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.8
            scale.toValue = 1.85
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.8
            fade.toValue = 0
            let group = CAAnimationGroup()
            group.animations = [scale, fade]
            group.duration = 1.8
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            group.repeatCount = .infinity
            group.isRemovedOnCompletion = false
            ring.add(group, forKey: Self.animationKey)
            ring.opacity = 0
        } else {
            ring.removeAnimation(forKey: Self.animationKey)
            ring.transform = CATransform3DMakeScale(0.8, 0.8, 1)
            ring.opacity = 0.8
        }
    }
}


// MARK: - Planning pieces

/// The drag payload for a task: "todo:<uuid>".
enum TodoDrag {
    static func provider(for id: UUID) -> NSItemProvider {
        NSItemProvider(object: "todo:\(id.uuidString)" as NSString)
    }

    static func payload(for id: UUID) -> String { "todo:\(id.uuidString)" }

    /// Reads "todo:<uuid>", or a bare uuid from older drags.
    static func id(from text: String) -> UUID? {
        UUID(uuidString: text.hasPrefix("todo:") ? String(text.dropFirst(5)) : text)
    }
}

/// Shows where a task would land while it's dragged over the timeline, and plans it there.
private struct TimelineDropDelegate: DropDelegate {
    let time: (CGFloat) -> Date
    @Binding var preview: Date?
    let onDrop: (UUID, Date) -> Void

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.text]) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let next = time(info.location.y)
        if preview != next { preview = next }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) { preview = nil }

    func performDrop(info: DropInfo) -> Bool {
        let start = time(info.location.y)
        preview = nil
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String, let id = TodoDrag.id(from: text) else { return }
            Task { @MainActor in onDrop(id, start) }
        }
        return true
    }
}

/// A task in the tray, ready to drag onto the timeline.
private struct PlanChip: View {
    let todo: TodoItem
    let list: FocusTask?
    let isDue: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(list.map { NonnaTheme.taskColor(for: $0.colorHex) } ?? NonnaTheme.secondaryInk)
                .frame(width: 6, height: 6)
            Text(todo.title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            Text(todo.plannedMinutes.minutesString)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(NonnaTheme.secondaryInk)
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(isDue ? NonnaTheme.raisedPaper : NonnaTheme.paper, in: Capsule())
        .overlay { Capsule().stroke(isDue ? NonnaTheme.strongLine : NonnaTheme.line, lineWidth: 0.8) }
        .contentShape(Capsule())
        .onDrag { TodoDrag.provider(for: todo.id) }
        .help(isDue ? "Due by this day. Drag it onto a time." : "Drag it onto a time.")
    }
}

/// A planned task on the timeline: dashed, in its list's colour, draggable to a new time.
private struct PlannedTaskBlock: View {
    @Environment(AppModel.self) private var model
    let todo: TodoItem
    let list: FocusTask?
    let canStart: Bool
    @State private var hovering = false

    private var tint: Color { list.map { NonnaTheme.taskColor(for: $0.colorHex) } ?? NonnaTheme.terracotta }

    var body: some View {
        let start = todo.scheduledAt ?? Date()
        let end = start.addingTimeInterval(TimeInterval(todo.plannedMinutes * 60))
        let steps = todo.steps
        HStack(alignment: .top, spacing: 8) {
            Button { model.toggleDone(todo.id) } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(tint)
            }
            .buttonStyle(.plain)
            .help(todo.isDone ? "Mark as not done" : "Mark as done")
            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                    .font(.system(size: 11, weight: .semibold))
                    .strikethrough(todo.isDone)
                    .lineLimit(1)
                Text("\(start.formatted(date: .omitted, time: .shortened)) to \(end.formatted(date: .omitted, time: .shortened))\(steps.isEmpty ? "" : ", \(steps.filter(\.isDone).count) of \(steps.count) steps")")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if canStart, !todo.isDone, hovering {
                Button { model.startFocus(on: todo.id) } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(tint.opacity(0.18), in: Circle())
                        .foregroundStyle(tint)
                }
                .buttonStyle(.plain)
                .help("Start focusing on this")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tint.opacity(todo.isDone ? 0.05 : 0.11), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(tint.opacity(hovering ? 0.9 : 0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .opacity(todo.isDone ? 0.6 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { hovering = $0 }
        .onDrag { TodoDrag.provider(for: todo.id) }
        .contextMenu {
            if canStart, !todo.isDone {
                Button("Start focusing on this") { model.startFocus(on: todo.id) }
            }
            Button(todo.isDone ? "Mark as not done" : "Mark as done") { model.toggleDone(todo.id) }
            Menu("How long") {
                ForEach(TaskLength.choices, id: \.self) { minutes in
                    Button(minutes.minutesString) { model.updateTodo(todo.id) { $0.minutes = minutes } }
                }
            }
            Divider()
            Button("Take off the timeline") { model.schedule(todo.id, at: nil) }
        }
        .help("Drag to move. Right-click for more.")
    }
}
