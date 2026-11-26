import Charts
import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.compactLayout) private var compact
    @State private var hoveredDay: Date?
    @State private var selectedMetric: DashboardMetric?
    @State private var chartWidth: CGFloat = 600
    /// Shown under Progress → See more, inside Overview's scroll, without what Overview
    /// already shows.
    var embedded = false
    /// Shows only this card, for a Progress widget.
    var part: DashboardPart?

    enum DashboardPart {
        case focusScore, dailyFocus, timeByList, hoursByWeek, consistency
    }

    @ViewBuilder
    private func partView(_ part: DashboardPart) -> some View {
        switch part {
        case .focusScore: FocusScoreCard()
        case .dailyFocus: recentActivityCard
        case .timeByList: taskTotalsCard
        case .hoursByWeek: WeeklyHoursCard()
        case .consistency: consistencyCard
        }
    }

    private var analytics: AnalyticsSnapshot { model.analytics }

    /// Focused time in the last 14 days (today included) and in the 14 days before that.
    private var fortnightChange: (current: Int, previous: Int) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -13, to: today),
              let previousStart = calendar.date(byAdding: .day, value: -14, to: start) else { return (0, 0) }
        var current = 0
        var previous = 0
        for session in model.sessions where session.outcome != .abandoned && session.focusedSeconds > 0 {
            if session.startedAt >= start {
                current += session.focusedSeconds
            } else if session.startedAt >= previousStart {
                previous += session.focusedSeconds
            }
        }
        return (current, previous)
    }

    private func dayTooltipLines(for total: DayTotal) -> [String] {
        let calendar = Calendar.current
        let count = model.sessions.filter {
            calendar.isDate($0.startedAt, inSameDayAs: total.day) && $0.outcome != .abandoned && $0.focusedSeconds > 0
        }.count
        return ["\(total.seconds.focusDurationString) focus", "\(count) \(count == 1 ? "session" : "sessions")"]
    }

    var body: some View {
        Group {
        if let part {
            partView(part)
        } else {
        OptionalScroll(enabled: !embedded) {
            VStack(alignment: .leading, spacing: 22) {
                if !embedded {
                    SectionHeading(title: "Dashboard")
                }

                FocusScoreCard()
                if !embedded {
                    PeakHoursCard()
                    WeekDashboardRow()
                    YearDashboardRow()
                    RunawayTimersBanner()
                }

                let totalBreakSeconds = model.breakSessions.reduce(0) { $0 + $1.restedSeconds }
                let trends = MetricTrends.compute(
                    sessions: model.sessions,
                    breaks: model.breakSessions,
                    streak: analytics.currentStreak,
                    bestStreak: analytics.longestStreak
                )
                let breakOvertimeSeconds = model.breakSessions.reduce(0) { $0 + $1.overtimeSeconds }

                DashboardStatGrid(columns: compact ? 2 : 3, stats: [
                    DashboardStat(
                        metric: .focus,
                        // Why this is more than completed sessions times their length.
                        trends: (trends[.focus] ?? []) + (analytics.overtimeSeconds >= 60
                            ? [.note("\(analytics.overtimeSeconds.focusDurationString) of it past the bell")] : []),
                        icon: "hourglass",
                        label: "Focused in total",
                        value: analytics.totalFocusSeconds.focusDurationString,
                        help: "All your focus time across every list, including time past the bell and blocks you ended early. Paused time isn't counted.",
                        detail: analytics.overtimeSeconds >= 60
                            ? "Includes \(analytics.overtimeSeconds.focusDurationString) past the bell"
                            : "Across every list",
                        tint: NonnaTheme.terracotta
                    ),
                    DashboardStat(
                        metric: .breakTime,
                        trends: trends[.breakTime] ?? [],
                        icon: "cup.and.saucer.fill",
                        label: "Break time",
                        value: totalBreakSeconds.focusDurationString,
                        help: "Total time on breaks.",
                        detail: "All recorded breaks",
                        tint: NonnaTheme.sage
                    ),
                    DashboardStat(
                        metric: .breakOvertime,
                        trends: trends[.breakOvertime] ?? [],
                        icon: "clock.badge.exclamationmark",
                        label: "Break overtime",
                        value: breakOvertimeSeconds.focusDurationString,
                        help: "Time your breaks ran past their planned length.",
                        detail: "Past planned length",
                        tint: NonnaTheme.gold
                    ),
                    DashboardStat(
                        metric: .daysUsed,
                        trends: trends[.daysUsed] ?? [],
                        icon: "calendar.badge.checkmark",
                        label: "Days used",
                        value: "\(analytics.usedDays)",
                        help: "Days you focused, for any amount of time.",
                        detail: "Days with any focus",
                        tint: NonnaTheme.gold
                    ),
                    DashboardStat(
                        metric: .rhythm,
                        trends: trends[.rhythm] ?? [],
                        icon: "flame.fill",
                        label: "Current streak",
                        value: "\(analytics.currentStreak) \(analytics.currentStreak == 1 ? "day" : "days")",
                        help: "Days in a row you've focused, up to today. Best is your longest run.",
                        detail: "Best: \(analytics.longestStreak) \(analytics.longestStreak == 1 ? "day" : "days")",
                        tint: NonnaTheme.sage
                    ),
                    DashboardStat(
                        metric: .completed,
                        trends: (trends[.completed] ?? []) + (analytics.endedEarlySessions > 0
                            ? [.note("Plus \(analytics.endedEarlySessions) ended early")] : []),
                        icon: "checkmark.seal.fill",
                        label: "Completed sessions",
                        value: "\(analytics.completedSessions)",
                        help: "Focus blocks you ran to their planned length. Blocks ended early don't count here, but their minutes count toward focus time. A block that switched lists counts once.",
                        detail: analytics.endedEarlySessions > 0
                            ? "Plus \(analytics.endedEarlySessions) ended early"
                            : "Full planned intervals",
                        tint: NonnaTheme.secondaryInk
                    ),
                ]) { selectedMetric = $0 }

                AdaptiveColumns(compact) {
                    recentActivityCard
                        .frame(maxWidth: .infinity)
                    taskTotalsCard
                        .frame(maxWidth: compact ? .infinity : 330)
                        .frame(width: compact ? nil : 330)
                }

                WeeklyHoursCard()

                if !embedded {
                    MoodCard()
                }

                consistencyCard

                InsightsSection()
            }
            .padding(embedded ? 0 : 30)
        }
        }
        }
        .sheet(item: $selectedMetric) { metric in
            MetricDeepDiveView(
                metric: metric,
                sessions: model.sessions,
                breaks: model.breakSessions,
                tasks: model.data.tasks,
                dailyGoalMinutes: model.settings.dailyGoalMinutes
            )
            .closesOnClickOutside { selectedMetric = nil }
        }
    }

    private var recentActivityCard: some View {
        // Capture one immutable snapshot for the chart and its hover handler. Reading the
        // computed `analytics` property from every pointer-move callback recalculates the
        // entire history dozens of times per second on larger local databases.
        let snapshot = analytics
        let total = snapshot.recentDays.reduce(0) { $0 + $1.seconds }
        let change = fortnightChange
        return NonnaCard {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        Text("Daily focus")
                            .font(.system(size: 18, weight: .semibold))
                        InfoButton(title: "Daily focus", text: "Focus time on each of the last 14 days. The big number is the total; the badge compares it with the 14 days before.")
                    }
                    HStack(alignment: .center, spacing: 10) {
                        Text(total.focusDurationString)
                            .font(.system(size: 26, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(NonnaTheme.ink)
                            .contentTransition(.numericText())
                        DeltaPill(current: change.current, previous: change.previous)
                        Text("Last 14 days")
                            .font(.system(size: 12))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                    }
                }

                if snapshot.recentDays.allSatisfy({ $0.seconds == 0 }) {
                    EmptyState(
                        icon: "chart.bar",
                        title: "No focus data",
                        message: "Finish a focus session to fill this in."
                    )
                } else {
                    let days = snapshot.recentDays
                    let firstDay = days.first?.day ?? Date()
                    let lastDay = days.last?.day ?? Date()
                    let domainEnd = Calendar.current.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
                    // Bars take ~60% of each day's slot, but never more than 20 pt.
                    let barWidth = min(20, max(4, (chartWidth - 44) / CGFloat(max(1, days.count)) * 0.6))
                    Chart {
                        if let hovered = days.first(where: { $0.day == hoveredDay }) {
                            RectangleMark(x: .value("Day", hovered.day, unit: .day))
                                .foregroundStyle(NonnaTheme.terracotta.opacity(0.12))
                                .cornerRadius(4)
                        }
                        ForEach(days) { item in
                            BarMark(
                                x: .value("Day", item.day, unit: .day),
                                y: .value("Minutes", Double(item.seconds) / 60),
                                width: .fixed(barWidth)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [NonnaTheme.darkTerracotta, NonnaTheme.terracotta],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .cornerRadius(3)
                        }
                    }
                    .chartXScale(domain: firstDay...domainEnd)                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { chartWidth = $0 }
                    .chartHover(Date.self) { date in
                        let day = date
                            .map { Calendar.current.startOfDay(for: $0) }
                            .flatMap { candidate in snapshot.recentDays.contains { $0.day == candidate } ? candidate : nil }
                        if hoveredDay != day { hoveredDay = day }
                    }
                    .chartHoverTooltip {
                        if let hovered = snapshot.recentDays.first(where: { $0.day == hoveredDay }) {
                            ChartTooltip(
                                title: hovered.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                                lines: dayTooltipLines(for: hovered)
                            )
                        }
                    }
                    .chartXAxis {
                        // Only the two ends are labelled, flush with the plot's edges.
                        AxisMarks(values: [firstDay]) { _ in
                            AxisValueLabel(anchor: .topLeading, collisionResolution: .disabled) {
                                Text(firstDay.formatted(.dateTime.month(.abbreviated).day()))
                            }
                            .foregroundStyle(NonnaTheme.secondaryInk)
                        }
                        AxisMarks(values: [domainEnd]) { _ in
                            AxisValueLabel(anchor: .topTrailing, collisionResolution: .disabled) {
                                Text(lastDay.formatted(.dateTime.month(.abbreviated).day()))
                            }
                            .foregroundStyle(NonnaTheme.secondaryInk)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                                .foregroundStyle(NonnaTheme.line)
                            AxisValueLabel {
                                if let minutes = value.as(Double.self) {
                                    Text(Int(minutes.rounded()).minutesString)
                                }
                            }
                            .foregroundStyle(NonnaTheme.secondaryInk)
                        }
                    }
                    .frame(minHeight: 90, idealHeight: 235, maxHeight: 235)
                }
            }
        }
    }

    private var taskTotalsCard: some View {
        NonnaCard {
            VStack(alignment: .leading, spacing: 17) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Lifetime")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(NonnaTheme.secondaryInk)
                    HStack(spacing: 7) {
                        Text("Time by list")
                            .font(.system(size: 18, weight: .semibold))
                        InfoButton(title: "Time by list", text: "Focus time by list since you started. To change a list's colour, use the dot next to it in Tasks.")
                    }
                }

                if analytics.taskTotals.isEmpty {
                    EmptyState(
                        icon: "list.bullet.rectangle",
                        title: "No task totals yet",
                        message: "Finish a focus session to see hours by list."
                    )
                } else {
                    let maximum = max(1, analytics.taskTotals.first?.seconds ?? 1)
                    ForEach(analytics.taskTotals.prefix(6)) { total in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Circle()
                                    .fill(NonnaTheme.taskColor(for: total.colorHex))
                                    .frame(width: 8, height: 8)
                                Text(total.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                Spacer()
                                Text(total.seconds.focusDurationString)
                                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                                    .foregroundStyle(NonnaTheme.secondaryInk)
                            }
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(NonnaTheme.line.opacity(0.55))
                                    Capsule()
                                        .fill(NonnaTheme.taskColor(for: total.colorHex))
                                        .frame(width: proxy.size.width * Double(total.seconds) / Double(maximum))
                                }
                            }
                            .frame(height: 7)
                        }
                        .help("\(total.name): \(total.seconds.focusDurationString) across \(total.sessionCount) \(total.sessionCount == 1 ? "session" : "sessions")")
                    }
                }
            }
        }
    }

    private var consistencyCard: some View {
        NonnaCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Consistency")
                        .font(.system(size: 18, weight: .semibold))
                    Text("last 12 weeks")
                        .font(.system(size: 12))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                    InfoButton(title: "Consistency", text: "Each square is a day and each column a week, oldest on the left. Darker means more focus: under 25m, 25m–1h, 1–2h, 2h or more. Click a day to keep it shown.")
                }
                UsageHeatmap(sessions: model.sessions)
            }
        }
    }
}

/// A small capsule comparing one period with the one before: green when focus grew,
/// red when it shrank. Hidden when there's nothing earlier to compare with.
private struct DeltaPill: View {
    let current: Int
    let previous: Int

    var body: some View {
        if previous > 0 {
            let percent = Int((Double(current - previous) / Double(previous) * 100).rounded())
            let color = percent > 0 ? TrendColors.good : (percent < 0 ? TrendColors.bad : NonnaTheme.secondaryInk)
            HStack(spacing: 3) {
                if percent != 0 {
                    Image(systemName: percent > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.system(size: 7, weight: .bold))
                }
                Text(percent == 0 ? "Level" : "\(abs(percent))%")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(color.opacity(0.2), in: Capsule())
            .help("Compared with the 14 days before")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(percent == 0
                ? "Level with the previous 14 days"
                : "\(percent > 0 ? "Up" : "Down") \(abs(percent)) percent on the previous 14 days")
        }
    }
}

/// What one cell of the stat grid shows.
private struct DashboardStat: Identifiable {
    let metric: DashboardMetric
    let trends: [MetricTrend]
    let icon: String
    let label: String
    let value: String
    let help: String
    let detail: String
    let tint: Color

    var id: DashboardMetric { metric }
}

/// The six headline numbers as one surface, split into cells by hairlines that fade out
/// at their ends. A Grid gives every cell in a row the same height, so they line up.
private struct DashboardStatGrid: View {
    let columns: Int
    let stats: [DashboardStat]
    let open: (DashboardMetric) -> Void

    private var rows: [[DashboardStat]] {
        stride(from: 0, to: stats.count, by: columns).map { Array(stats[$0..<min($0 + columns, stats.count)]) }
    }

    var body: some View {
        let rows = self.rows
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(rows.indices, id: \.self) { row in
                GridRow {
                    ForEach(rows[row]) { stat in
                        let column = rows[row].firstIndex { $0.metric == stat.metric } ?? 0
                        DashboardMetricButton(stat: stat) { open(stat.metric) }
                            .overlay(alignment: .trailing) {
                                if column < columns - 1 { FadingHairline(axis: .vertical) }
                            }
                            .overlay(alignment: .bottom) {
                                if row < rows.count - 1 { FadingHairline(axis: .horizontal) }
                            }
                    }
                }
            }
        }
        .background(NonnaTheme.paper.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(NonnaTheme.line, lineWidth: 0.8)
        }
        .shadow(color: NonnaTheme.shadow.opacity(0.7), radius: 16, y: 8)
    }
}

private struct DashboardMetricButton: View {
    let stat: DashboardStat
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private static let padding: CGFloat = 20

    var body: some View {
        Button(action: action) {
            MetricCard(
                icon: stat.icon,
                label: stat.label,
                value: stat.value,
                detail: stat.detail,
                tint: stat.tint,
                trends: stat.trends,
                trailingInset: 48
            )
            .padding(Self.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(NonnaTheme.ink.opacity(isHovering ? 0.035 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(stat.detail)
        .accessibilityLabel("\(stat.label), \(stat.value). Open detailed analytics")
        .accessibilityHint(stat.detail)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                InfoButton(title: stat.label, text: stat.help)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .opacity(isHovering ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            // Centred on the 34 pt icon chip.
            .padding(.top, Self.padding + 9)
            .padding(.trailing, Self.padding)
        }
        .animation(reduceMotion ? nil : NonnaMotion.quick, value: isHovering)
        .onHover { isHovering = $0 }
    }
}

/// Twelve weeks of focus, one square per day: rows are weekdays, columns are weeks.
/// Hover a day to see it, click to keep it selected.
private struct UsageHeatmap: View {
    let sessions: [FocusSession]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: Date?
    @State private var selected: Date?
    private let calendar = Calendar.current
    private static let weeks = 12
    /// Month row, then seven rows of at most 30 pt with 5 pt gaps.
    private static let gridHeight: CGFloat = 278

    private struct Day {
        let date: Date
        let seconds: Int
        let blocks: Int
        let lists: [String]
    }

    /// Weeks oldest first, each Monday→Sunday (or the locale's first weekday), future days nil.
    private var columns: [[Day?]] {
        let today = calendar.startOfDay(for: Date())
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start,
              let first = calendar.date(byAdding: .weekOfYear, value: -(Self.weeks - 1), to: thisWeek) else { return [] }
        let counted = sessions.filter { $0.outcome != .abandoned }
        let grouped = Dictionary(grouping: counted) { calendar.startOfDay(for: $0.startedAt) }
        return (0..<Self.weeks).map { week in
            (0..<7).map { offset -> Day? in
                guard let date = calendar.date(byAdding: .day, value: week * 7 + offset, to: first), date <= today else { return nil }
                let items = grouped[date, default: []]
                var lists: [String] = []
                for item in items where !lists.contains(item.taskName) { lists.append(item.taskName) }
                return Day(date: date, seconds: items.reduce(0) { $0 + $1.focusedSeconds }, blocks: items.count, lists: lists)
            }
        }
    }

    var body: some View {
        let columns = self.columns
        let focusDay = find(hovered ?? selected, in: columns)
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { proxy in
                grid(columns, width: proxy.size.width)
            }
            .frame(height: Self.gridHeight)

            detail(focusDay)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: focusDay?.date)
        }
    }

    private func find(_ date: Date?, in columns: [[Day?]]) -> Day? {
        guard let date else { return nil }
        for week in columns {
            for day in week where day?.date == date { return day }
        }
        return nil
    }

    private func grid(_ columns: [[Day?]], width: CGFloat) -> some View {
        let labelWidth: CGFloat = 30
        let spacing: CGFloat = 5
        let fit = (width - labelWidth - spacing * CGFloat(Self.weeks - 1)) / CGFloat(Self.weeks)
        let cell = max(12, min(30, fit))
        return VStack(alignment: .leading, spacing: 6) {
            // Month names over the first week that starts in a new month.
            HStack(spacing: spacing) {
                Color.clear.frame(width: labelWidth, height: 12)
                ForEach(columns.indices, id: \.self) { index in
                    Text(monthLabel(columns, index) ?? "")
                        .font(.system(size: 10))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                        .fixedSize()
                        .frame(width: cell, alignment: .leading)
                }
            }
            HStack(alignment: .top, spacing: spacing) {
                VStack(alignment: .leading, spacing: spacing) {
                    ForEach(0..<7, id: \.self) { row in
                        Text(row % 2 == 0 ? weekdayName(columns, row) : "")
                            .font(.system(size: 10))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                            .frame(width: labelWidth, height: cell, alignment: .leading)
                    }
                }
                ForEach(columns.indices, id: \.self) { week in
                    VStack(spacing: spacing) {
                        ForEach(0..<7, id: \.self) { row in
                            square(columns[week][row], size: cell)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func square(_ day: Day?, size: CGFloat) -> some View {
        if let day {
            let isFocus = day.date == hovered || day.date == selected
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Self.color(for: day.seconds))
                .frame(width: size, height: size)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .stroke(isFocus ? NonnaTheme.ink : (calendar.isDateInToday(day.date) ? NonnaTheme.strongLine : .clear), lineWidth: isFocus ? 1.5 : 1)
                }
                .scaleEffect(day.date == hovered && !reduceMotion ? 1.12 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { hovered = day.date } else if hovered == day.date { hovered = nil }
                }
                .onTapGesture { selected = selected == day.date ? nil : day.date }
                .accessibilityLabel("\(day.date.formatted(date: .complete, time: .omitted)), \(day.seconds.focusDurationString)")
                .accessibilityAddTraits(.isButton)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }

    /// The day under the pointer (or the one clicked), in words.
    @ViewBuilder
    private func detail(_ day: Day?) -> some View {
        HStack(spacing: 10) {
            if let day {
                RoundedRectangle(cornerRadius: 3).fill(Self.color(for: day.seconds)).frame(width: 11, height: 11)
                Text(day.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.system(size: 12, weight: .semibold))
                Text(summary(day))
                    .font(.system(size: 12))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .lineLimit(1)
            } else {
                Text("Hover a day to see it.")
                    .font(.system(size: 12))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            Spacer()
            HStack(spacing: 4) {
                Text("Less")
                ForEach([0, 600, 1800, 4000, 8000], id: \.self) { seconds in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Self.color(for: seconds))
                        .frame(width: 11, height: 11)
                }
                Text("More")
            }
            .font(.system(size: 10))
            .foregroundStyle(NonnaTheme.secondaryInk)
        }
        .frame(height: 18)
    }

    private func summary(_ day: Day) -> String {
        guard day.seconds > 0 else { return "No focus" }
        let blocks = "\(day.blocks) \(day.blocks == 1 ? "block" : "blocks")"
        let lists = day.lists.prefix(3).joined(separator: ", ")
        return "\(day.seconds.focusDurationString) in \(blocks)\(lists.isEmpty ? "" : ", on \(lists)")"
    }

    private func weekdayName(_ columns: [[Day?]], _ row: Int) -> String {
        guard let date = columns.first?[row]?.date ?? columns.last.flatMap({ _ in
            calendar.date(byAdding: .day, value: row, to: calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date())
        }) else { return "" }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    private func monthLabel(_ columns: [[Day?]], _ index: Int) -> String? {
        guard let start = columns[index].compactMap({ $0 }).first?.date else { return nil }
        if index == 0 { return start.formatted(.dateTime.month(.abbreviated)) }
        guard let previous = columns[index - 1].compactMap({ $0 }).first?.date,
              calendar.component(.month, from: previous) != calendar.component(.month, from: start) else { return nil }
        return start.formatted(.dateTime.month(.abbreviated))
    }

    static func color(for seconds: Int) -> Color {
        switch seconds {
        case 0: NonnaTheme.line.opacity(0.55)
        case 1..<1500: NonnaTheme.sage.opacity(0.28)
        case 1500..<3600: NonnaTheme.sage.opacity(0.5)
        case 3600..<7200: NonnaTheme.sage.opacity(0.72)
        default: NonnaTheme.sage
        }
    }
}

/// Hours focused in each of the last twelve weeks, with this week's total up top.
private struct WeeklyHoursCard: View {
    @Environment(AppModel.self) private var model
    @State private var hoveredWeek: Date?

    var body: some View {
        // One snapshot for the chart and its hover handler, so moving the pointer doesn't
        // recount the history.
        let totals = WeeklyTotals.calculate(sessions: model.sessions)
        let thisWeek = totals.thisWeek
        let average = totals.averageSeconds
        return NonnaCard {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        Text("Hours by week")
                            .font(.system(size: 18, weight: .semibold))
                        InfoButton(title: "Hours by week", text: "Focus time in each of the last 12 weeks, including time past the bell and blocks you ended early. The badge compares this week so far with last week at the same point. The dashed line is your average across weeks you focused.")
                    }
                    HStack(alignment: .center, spacing: 10) {
                        Text((thisWeek?.seconds ?? 0).focusDurationString)
                            .font(.system(size: 26, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(NonnaTheme.ink)
                            .contentTransition(.numericText())
                        DeltaPill(current: thisWeek?.seconds ?? 0, previous: totals.lastWeekToDateSeconds)
                        Text("This week so far")
                            .font(.system(size: 12))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                        Spacer(minLength: 8)
                        if let average {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(average.focusDurationString)
                                    .font(.system(size: 14, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(NonnaTheme.ink)
                                Text("Weekly average")
                                    .font(.system(size: 11))
                                    .foregroundStyle(NonnaTheme.secondaryInk)
                            }
                        }
                    }
                }

                if !totals.hasFocus {
                    EmptyState(
                        icon: "chart.bar",
                        title: "No focus yet",
                        message: "Finish a focus session to see weekly hours."
                    )
                } else {
                    chart(totals, average: average)
                }
            }
        }
    }

    private func chart(_ totals: WeeklyTotals, average: Int?) -> some View {
        let weeks = totals.weeks
        let calendar = Calendar.current
        let first = weeks.first?.start ?? Date()
        let last = weeks.last?.start ?? Date()
        let end = calendar.date(byAdding: .weekOfYear, value: 1, to: last) ?? last
        return Chart {
            if let hovered = weeks.first(where: { $0.start == hoveredWeek }) {
                RectangleMark(x: .value("Week", hovered.start, unit: .weekOfYear))
                    .foregroundStyle(NonnaTheme.terracotta.opacity(0.12))
                    .cornerRadius(4)
            }
            ForEach(weeks) { week in
                BarMark(
                    x: .value("Week", week.start, unit: .weekOfYear),
                    y: .value("Hours", Double(week.seconds) / 3600),
                    width: .ratio(0.55)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [NonnaTheme.darkTerracotta, NonnaTheme.terracotta],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                // The week in progress is lighter until it's done.
                .opacity(week.start == last ? 0.55 : 1)
                .cornerRadius(3)
                .accessibilityLabel("Week of \(week.start.formatted(.dateTime.month(.abbreviated).day()))")
                .accessibilityValue(week.seconds.focusDurationString)
            }
            if let average {
                RuleMark(y: .value("Weekly average", Double(average) / 3600))
                    .foregroundStyle(NonnaTheme.secondaryInk.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .trailing, spacing: 3) {
                        Text("Average")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                    }
            }
        }
        .chartXScale(domain: first...end)
        .chartHover(Date.self) { date in
            let week = date
                .flatMap { calendar.dateInterval(of: .weekOfYear, for: $0)?.start }
                .flatMap { start in weeks.contains { $0.start == start } ? start : nil }
            if hoveredWeek != week { hoveredWeek = week }
        }
        .chartHoverTooltip {
            if let hovered = weeks.first(where: { $0.start == hoveredWeek }) {
                ChartTooltip(title: title(for: hovered, isCurrent: hovered.start == last), lines: lines(for: hovered))
            }
        }
        .chartXAxis {
            AxisMarks(values: weeks.map(\.start)) { value in
                if let date = value.as(Date.self), shouldLabel(date, in: weeks) {
                    AxisValueLabel(anchor: .top, collisionResolution: .disabled) {
                        Text(date == last ? "This week" : date.formatted(.dateTime.month(.abbreviated).day()))
                    }
                    .foregroundStyle(NonnaTheme.secondaryInk)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .foregroundStyle(NonnaTheme.line)
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text(Int((hours * 60).rounded()).minutesString)
                    }
                }
                .foregroundStyle(NonnaTheme.secondaryInk)
            }
        }
        .frame(minHeight: 90, idealHeight: 220, maxHeight: 220)
    }

    /// Every third week, counting back from this one, so the labels never crowd.
    private func shouldLabel(_ date: Date, in weeks: [WeeklyTotals.Week]) -> Bool {
        guard let index = weeks.firstIndex(where: { $0.start == date }) else { return false }
        return (weeks.count - 1 - index) % 3 == 0
    }

    private func title(for week: WeeklyTotals.Week, isCurrent: Bool) -> String {
        isCurrent ? "This week" : "Week of \(week.start.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func lines(for week: WeeklyTotals.Week) -> [String] {
        var lines = ["\(week.seconds.focusDurationString) focus"]
        lines.append("\(week.completed) completed \(week.completed == 1 ? "session" : "sessions")")
        if week.endedEarly > 0 { lines.append("\(week.endedEarly) ended early") }
        return lines
    }
}

/// When you focus best: each hour judged by how its blocks went (finished, and how they
/// felt), with the best two-hour stretch named in plain words.
struct PeakHoursCard: View {
    @Environment(AppModel.self) private var model
    @State private var hoveredHour: Int?
    @State private var chartWidth: CGFloat = 600

    private static let feelings = ["Scattered", "Restless", "Steady", "Focused", "Flow"]

    private func feeling(_ rating: Double?) -> String? {
        guard let rating else { return nil }
        return Self.feelings[min(4, max(0, Int(rating.rounded()) - 1))]
    }

    private func range(_ window: PeakHours.Window) -> String {
        "\(window.start.clockHourLabel) to \(window.end.clockHourLabel)"
    }

    var body: some View {
        let peak = PeakHours.calculate(sessions: model.sessions)
        return NonnaCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 7) {
                    Text("Your peak hours")
                        .font(.system(size: 18, weight: .semibold))
                    InfoButton(title: "Your peak hours", text: "Based on the last 60 days. Each hour is scored by how often you finished its blocks and how you rated them, not by minutes. The highlighted stretch is your best two hours.")
                }
                if peak.hasEnoughData, let best = peak.best {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("You focus best from \(range(best))")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(NonnaTheme.ink)
                        Text(summary(best: best, hardest: peak.hardest))
                            .font(.system(size: 12))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    chart(peak, best: best)
                } else {
                    EmptyState(
                        icon: "clock",
                        title: "Not enough blocks yet",
                        message: "This needs \(PeakHours.minimumBlocks) blocks at different times. You have \(peak.blockCount) so far."
                    )
                }
            }
        }
    }

    private func summary(best: PeakHours.Window, hardest: PeakHours.Window?) -> String {
        var text = "You finish \(Int((best.finishRate * 100).rounded()))% of blocks you start then"
        if let feel = feeling(best.averageRating) { text += " and usually rate them \(feel)" }
        text += ". Do your hardest work there."
        if let hardest {
            text += " Your weakest stretch is \(range(hardest)); keep lighter work for that."
        }
        return text
    }

    private func chart(_ peak: PeakHours, best: PeakHours.Window) -> some View {
        let active = peak.hours.filter { $0.blocks > 0 }.map(\.hour)
        let first = min(active.min() ?? 8, best.start)
        let last = max(active.max() ?? 22, (best.end + 23) % 24)
        let shown = peak.hours.filter { $0.hour >= first && $0.hour <= last }
        let bestHours: Set<Int> = [best.start, (best.start + 1) % 24]
        // Bars take about 60% of each hour's slot.
        let barWidth = max(4, min(26, (chartWidth - 40) / CGFloat(max(1, last - first + 1)) * 0.6))
        return Chart {
            ForEach(shown) { hour in
                BarMark(
                    x: .value("Hour", Double(hour.hour)),
                    y: .value("Minutes", hour.minutes),
                    width: .fixed(barWidth)
                )
                .foregroundStyle(bestHours.contains(hour.hour)
                                 ? NonnaTheme.terracotta
                                 : NonnaTheme.terracotta.opacity(hour.blocks == 0 ? 0 : 0.18 + 0.4 * hour.quality))
                .cornerRadius(3)
            }
        }
        .chartXScale(domain: (Double(first) - 0.5)...(Double(last) + 0.5))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { chartWidth = $0 }
        .chartHover(Double.self) { hour in
            let h = hour.map { min(last, max(first, Int($0.rounded()))) }
            if hoveredHour != h { hoveredHour = h }
        }
        .chartHoverTooltip {
            if let h = hoveredHour, let hour = peak.hours.first(where: { $0.hour == h }), hour.blocks > 0 {
                ChartTooltip(title: "\(h.clockHourLabel) to \((h + 1).clockHourLabel)", lines: lines(hour))
            }
        }
        .chartXAxis {
            AxisMarks(values: Array(stride(from: first, through: last, by: 3)).map(Double.init)) { value in
                AxisValueLabel {
                    if let h = value.as(Double.self) { Text(Int(h).clockHourLabel) }
                }
                .foregroundStyle(NonnaTheme.secondaryInk)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .foregroundStyle(NonnaTheme.line)
                AxisValueLabel {
                    if let minutes = value.as(Int.self) { Text(minutes.minutesString) }
                }
                .foregroundStyle(NonnaTheme.secondaryInk)
            }
        }
        .frame(minHeight: 80, idealHeight: 170, maxHeight: 170)
        .accessibilityLabel("Focus minutes by hour. Best from \(range(best)).")
    }

    private func lines(_ hour: PeakHours.Hour) -> [String] {
        var lines = ["\(hour.minutes.minutesString) focused", "\(hour.finished) of \(hour.blocks) blocks finished"]
        if let feel = feeling(hour.averageRating) { lines.append("Usually rated \(feel)") }
        return lines
    }
}

/// A scroll view, or just the content when something outside already scrolls.
struct OptionalScroll<Content: View>: View {
    let enabled: Bool
    @ViewBuilder let content: Content

    var body: some View {
        if enabled {
            ScrollView { content }
        } else {
            content
        }
    }
}
