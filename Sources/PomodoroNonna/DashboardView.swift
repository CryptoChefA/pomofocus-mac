import Charts
import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.compactLayout) private var compact
    @State private var hoveredDay: Date?
    @State private var selectedMetric: DashboardMetric?
    @State private var chartWidth: CGFloat = 600

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
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeading(
                    title: "Dashboard"
                )

                FocusScoreCard()
                RunawayTimersBanner()

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
                        trends: trends[.focus] ?? [],
                        icon: "hourglass",
                        label: "Focused in total",
                        value: analytics.totalFocusSeconds.focusDurationString,
                        help: "Every minute you've spent focusing, across all your lists, since you started using Pomofocus. Paused time isn't counted.",
                        detail: "Across every list",
                        tint: NonnaTheme.terracotta
                    ),
                    DashboardStat(
                        metric: .breakTime,
                        trends: trends[.breakTime] ?? [],
                        icon: "cup.and.saucer.fill",
                        label: "Break time",
                        value: totalBreakSeconds.focusDurationString,
                        help: "All the time you've spent on breaks between focus blocks.",
                        detail: "Recorded rest periods",
                        tint: NonnaTheme.sage
                    ),
                    DashboardStat(
                        metric: .breakOvertime,
                        trends: trends[.breakOvertime] ?? [],
                        icon: "clock.badge.exclamationmark",
                        label: "Break overtime",
                        value: breakOvertimeSeconds.focusDurationString,
                        help: "Time your breaks ran past their planned length. A little is normal; a lot means breaks are turning into long stops.",
                        detail: "Beyond planned breaks",
                        tint: NonnaTheme.gold
                    ),
                    DashboardStat(
                        metric: .daysUsed,
                        trends: trends[.daysUsed] ?? [],
                        icon: "calendar.badge.checkmark",
                        label: "Days used",
                        value: "\(analytics.usedDays)",
                        help: "How many different days you've focused on, for any amount of time.",
                        detail: "Days with focused time",
                        tint: NonnaTheme.gold
                    ),
                    DashboardStat(
                        metric: .rhythm,
                        trends: trends[.rhythm] ?? [],
                        icon: "flame.fill",
                        label: "Current rhythm",
                        value: "\(analytics.currentStreak) \(analytics.currentStreak == 1 ? "day" : "days")",
                        help: "How many days in a row you've focused, up to today. \"Best\" is your longest run so far.",
                        detail: "Best: \(analytics.longestStreak) \(analytics.longestStreak == 1 ? "day" : "days")",
                        tint: NonnaTheme.sage
                    ),
                    DashboardStat(
                        metric: .completed,
                        trends: trends[.completed] ?? [],
                        icon: "checkmark.seal.fill",
                        label: "Completed sessions",
                        value: "\(analytics.completedSessions)",
                        help: "Focus blocks you ran all the way to their planned length, instead of ending early.",
                        detail: "Full planned intervals",
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

                consistencyCard

                InsightsSection()
            }
            .padding(30)
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
                        Text("Focus rhythm")
                            .font(.system(size: 18, weight: .semibold))
                        InfoButton(title: "Focus rhythm", text: "How long you focused on each of the last 14 days. The large number is the total; the badge beside it compares that with the 14 days before. Hover a bar to see that day.")
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
                        message: "Complete a focus session to populate this chart."
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
                    .frame(height: 235)
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
                        InfoButton(title: "Time by list", text: "Where your focus time has gone, by list, since you started. Each bar is in that list's colour; change a colour from the dot on the list in Tasks.")
                    }
                }

                if analytics.taskTotals.isEmpty {
                    EmptyState(
                        icon: "list.bullet.rectangle",
                        title: "No task totals yet",
                        message: "Your lifetime task hours will appear here."
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
                    InfoButton(title: "Consistency", text: "Each square is one day; each column is a week, oldest on the left. Darker squares mean more focus: under 25m, 25m–1h, 1–2h, and 2h or more. Hover a day to see it, or click to keep it shown.")
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
                Text("Hover a day to see it. Darker squares mean more focus.")
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
