import Charts
import SwiftUI

enum DashboardMetric: String, Identifiable, CaseIterable {
    case focus
    case breakTime
    case breakOvertime
    case daysUsed
    case rhythm
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: "Focus time"
        case .breakTime: "Break time"
        case .breakOvertime: "Break overtime"
        case .daysUsed: "Days used"
        case .rhythm: "Streaks"
        case .completed: "Completed sessions"
        }
    }

    var eyebrow: String {
        switch self {
        case .focus: "Deep work"
        case .breakTime: "Recovery"
        case .breakOvertime: "Overrun"
        case .daysUsed: "Activity"
        case .rhythm: "Rhythm"
        case .completed: "Execution"
        }
    }

    var subtitle: String {
        switch self {
        case .focus: "Totals, peak hours and time by task."
        case .breakTime: "How long your breaks are and how they end."
        case .breakOvertime: "How often breaks run past plan, and by how much."
        case .daysUsed: "How many days you focused and how many hit your goal."
        case .rhythm: "Your streaks and how steady your focus is."
        case .completed: "How blocks ended, how often you paused, and your ratings."
        }
    }

    var icon: String {
        switch self {
        case .focus: "hourglass"
        case .breakTime: "cup.and.saucer.fill"
        case .breakOvertime: "clock.badge.exclamationmark"
        case .daysUsed: "calendar.badge.checkmark"
        case .rhythm: "flame.fill"
        case .completed: "checkmark.seal.fill"
        }
    }

    var tint: Color {
        switch self {
        case .focus: NonnaTheme.terracotta
        case .breakTime: NonnaTheme.sage
        case .breakOvertime: NonnaTheme.gold
        case .daysUsed: NonnaTheme.gold
        case .rhythm: NonnaTheme.sage
        case .completed: NonnaTheme.secondaryInk
        }
    }
}

struct MetricDeepDiveView: View {
    let metric: DashboardMetric
    let sessions: [FocusSession]
    let breaks: [BreakSession]
    let tasks: [FocusTask]
    let dailyGoalMinutes: Int

    @Environment(\.dismiss) private var dismiss
    @State private var range: InsightsRange = .month
    @State private var snapshot: DeepDiveSnapshot
    @State private var hoveredDay: Date?

    private let ranges: [InsightsRange] = [.week, .month, .quarter]
    private let calendar = Calendar.current

    init(
        metric: DashboardMetric,
        sessions: [FocusSession],
        breaks: [BreakSession],
        tasks: [FocusTask],
        dailyGoalMinutes: Int
    ) {
        self.metric = metric
        self.sessions = sessions
        self.breaks = breaks
        self.tasks = tasks
        self.dailyGoalMinutes = dailyGoalMinutes
        _snapshot = State(initialValue: DeepDiveSnapshot.calculate(
            sessions: sessions,
            breaks: breaks,
            tasks: tasks,
            dailyGoalMinutes: dailyGoalMinutes,
            range: .month
        ))
    }

    var body: some View {
        ZStack {
            NonnaBackground()
            VStack(spacing: 0) {
            // The header (with Close) stays put while the details scroll.
            header
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
                .background(NonnaTheme.cream.opacity(0.92))
                .overlay(alignment: .bottom) { Rectangle().fill(NonnaTheme.line).frame(height: 0.8) }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statGrid
                    primaryChartCard
                    intelligenceStrip
                    HStack(alignment: .top, spacing: 18) {
                        timePatternCard
                            .frame(maxWidth: .infinity)
                        distributionCard
                            .frame(maxWidth: .infinity)
                    }
                    methodologyCard
                }
                .padding(28)
            }
            }
        }
        .foregroundStyle(NonnaTheme.ink)
        .tint(metric.tint)
        .frame(minWidth: 760, idealWidth: 980, maxWidth: 1160, minHeight: 520, idealHeight: 720, maxHeight: 900)
        .onChange(of: range) { _, newRange in
            hoveredDay = nil
            snapshot = DeepDiveSnapshot.calculate(
                sessions: sessions,
                breaks: breaks,
                tasks: tasks,
                dailyGoalMinutes: dailyGoalMinutes,
                range: newRange
            )
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(metric.tint.opacity(0.13))
                Image(systemName: metric.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(metric.tint)
            }
            .frame(width: 50, height: 50)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(metric.tint.opacity(0.24), lineWidth: 0.8)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(metric.title)
                    .font(.system(size: 28, weight: .semibold))
                Text(metric.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }

            Spacer()

            Picker("Range", selection: $range) {
                ForEach(ranges) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 210)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(NonnaTheme.raisedPaper)
                    .clipShape(Circle())
                    .overlay { Circle().stroke(NonnaTheme.line, lineWidth: 0.8) }
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close")
        }
    }

    private var statGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            ForEach(detailStats) { stat in
                DetailStatTile(stat: stat, tint: metric.tint)
            }
        }
    }

    private var primaryChartCard: some View {
        NonnaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(rangeDescription)
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(NonnaTheme.secondaryInk)
                        Text(primaryChartTitle)
                            .font(.system(size: 18, weight: .semibold))
                    }
                    Spacer()
                    primaryLegend
                }

                Chart {
                    if let hoveredDay {
                        RuleMark(x: .value("Selected", hoveredDay, unit: .day))
                            .foregroundStyle(NonnaTheme.strongLine)
                    }

                    switch metric {
                    case .focus:
                        ForEach(snapshot.days) { day in
                            BarMark(
                                x: .value("Day", day.date, unit: .day),
                                y: .value("Focus minutes", Double(day.focusSeconds) / 60)
                            )
                            .foregroundStyle(NonnaTheme.terracotta.opacity(0.62))
                            .cornerRadius(2)
                            LineMark(
                                x: .value("Day", day.date, unit: .day),
                                y: .value("7-day average", Double(day.rollingFocusSeconds) / 60)
                            )
                            .foregroundStyle(NonnaTheme.darkTerracotta)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        }
                        RuleMark(y: .value("Daily goal", dailyGoalMinutes))
                            .foregroundStyle(NonnaTheme.gold.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    case .breakTime:
                        ForEach(snapshot.days) { day in
                            BarMark(
                                x: .value("Day", day.date, unit: .day),
                                yStart: .value("Start", 0),
                                yEnd: .value("Planned rest", Double(day.plannedBreakSeconds) / 60)
                            )
                            .foregroundStyle(NonnaTheme.sage)
                            .cornerRadius(2)
                            BarMark(
                                x: .value("Day", day.date, unit: .day),
                                yStart: .value("Planned", Double(day.plannedBreakSeconds) / 60),
                                yEnd: .value("Total", Double(day.breakSeconds) / 60)
                            )
                            .foregroundStyle(NonnaTheme.gold)
                            .cornerRadius(2)
                        }

                    case .breakOvertime:
                        ForEach(snapshot.days) { day in
                            BarMark(
                                x: .value("Day", day.date, unit: .day),
                                yStart: .value("Start", 0),
                                yEnd: .value("Break overtime", Double(day.breakOvertimeSeconds) / 60)
                            )
                            .foregroundStyle(NonnaTheme.gold)
                            .cornerRadius(2)
                            BarMark(
                                x: .value("Day", day.date, unit: .day),
                                yStart: .value("Break", Double(day.breakOvertimeSeconds) / 60),
                                yEnd: .value("All overtime", Double(day.breakOvertimeSeconds + day.focusOvertimeSeconds) / 60)
                            )
                            .foregroundStyle(NonnaTheme.terracotta.opacity(0.72))
                            .cornerRadius(2)
                        }

                    case .daysUsed:
                        ForEach(snapshot.days) { day in
                            BarMark(
                                x: .value("Day", day.date, unit: .day),
                                y: .value("Focus minutes", Double(day.focusSeconds) / 60)
                            )
                            .foregroundStyle(day.focusSeconds >= dailyGoalMinutes * 60 ? NonnaTheme.gold : NonnaTheme.gold.opacity(day.focusSeconds > 0 ? 0.5 : 0.12))
                            .cornerRadius(2)
                        }
                        RuleMark(y: .value("Daily goal", dailyGoalMinutes))
                            .foregroundStyle(NonnaTheme.gold.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    case .rhythm:
                        ForEach(snapshot.days) { day in
                            AreaMark(
                                x: .value("Day", day.date, unit: .day),
                                y: .value("7-day average", Double(day.rollingFocusSeconds) / 60)
                            )
                            .foregroundStyle(LinearGradient(
                                colors: [NonnaTheme.sage.opacity(0.38), NonnaTheme.sage.opacity(0.03)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            LineMark(
                                x: .value("Day", day.date, unit: .day),
                                y: .value("7-day average", Double(day.rollingFocusSeconds) / 60)
                            )
                            .foregroundStyle(NonnaTheme.sage)
                            .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                            PointMark(
                                x: .value("Day", day.date, unit: .day),
                                y: .value("Daily focus", Double(day.focusSeconds) / 60)
                            )
                            .foregroundStyle(day.focusSeconds > 0 ? NonnaTheme.darkTerracotta : NonnaTheme.line)
                            .symbolSize(day.focusSeconds > 0 ? 24 : 9)
                        }

                    case .completed:
                        ForEach(snapshot.days) { day in
                            BarMark(
                                x: .value("Day", day.date, unit: .day),
                                yStart: .value("Start", 0),
                                yEnd: .value("Completed", day.completedCount)
                            )
                            .foregroundStyle(NonnaTheme.sage)
                            .cornerRadius(2)
                            BarMark(
                                x: .value("Day", day.date, unit: .day),
                                yStart: .value("Completed", day.completedCount),
                                yEnd: .value("Completed + early", day.completedCount + day.earlyCount)
                            )
                            .foregroundStyle(NonnaTheme.gold)
                            BarMark(
                                x: .value("Day", day.date, unit: .day),
                                yStart: .value("Finished", day.completedCount + day.earlyCount),
                                yEnd: .value("Recorded", day.sessionCount)
                            )
                            .foregroundStyle(NonnaTheme.alert.opacity(0.7))
                        }
                    }
                }
                .chartHover(Date.self) { date in
                    let match = date.flatMap { value in
                        snapshot.days.first { calendar.isDate($0.date, inSameDayAs: value) }?.date
                    }
                    if hoveredDay != match { hoveredDay = match }
                }
                .chartHoverTooltip {
                    if let selected = snapshot.days.first(where: { $0.date == hoveredDay }) {
                        ChartTooltip(
                            title: selected.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
                            lines: tooltipLines(for: selected)
                        )
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: xAxisStride)) { _ in
                        AxisGridLine().foregroundStyle(.clear)
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .foregroundStyle(NonnaTheme.secondaryInk)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(NonnaTheme.line.opacity(0.55))
                        AxisValueLabel {
                            if metric == .completed, let count = value.as(Int.self) {
                                Text("\(count)")
                            } else if let minutes = value.as(Double.self) {
                                Text(minutes >= 60 ? String(format: "%.0fh", minutes / 60) : "\(Int(minutes))m")
                            }
                        }
                        .foregroundStyle(NonnaTheme.secondaryInk)
                    }
                }
                .frame(height: 285)
            }
        }
    }

    @ViewBuilder
    private var primaryLegend: some View {
        switch metric {
        case .focus:
            DetailLegend(items: [("Daily focus", NonnaTheme.terracotta), ("7-day average", NonnaTheme.darkTerracotta)])
        case .breakTime:
            DetailLegend(items: [("Planned", NonnaTheme.sage), ("Overtime", NonnaTheme.gold)])
        case .breakOvertime:
            DetailLegend(items: [("Break", NonnaTheme.gold), ("Focus", NonnaTheme.terracotta)])
        case .daysUsed:
            DetailLegend(items: [("Active", NonnaTheme.gold), ("Goal line", NonnaTheme.secondaryInk)])
        case .rhythm:
            DetailLegend(items: [("Daily", NonnaTheme.darkTerracotta), ("7-day average", NonnaTheme.sage)])
        case .completed:
            DetailLegend(items: [("Completed", NonnaTheme.sage), ("Early", NonnaTheme.gold), ("Abandoned", NonnaTheme.alert)])
        }
    }

    private var intelligenceStrip: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(narratives) { insight in
                IntelligenceCallout(insight: insight, tint: metric.tint)
            }
        }
    }

    private var timePatternCard: some View {
        NonnaCard {
            VStack(alignment: .leading, spacing: 14) {
                DetailSectionTitle(title: "By hour")
                Chart(snapshot.hours) { item in
                    BarMark(
                        x: .value("Hour", hourLabel(item.hour)),
                        y: .value("Minutes", Double(item.seconds) / 60)
                    )
                    .foregroundStyle(item.id == snapshot.peakHour?.id ? metric.tint : metric.tint.opacity(0.42))
                    .cornerRadius(2)
                }
                .chartXAxis {
                    AxisMarks(values: [0, 6, 12, 18].map(hourLabel)) { _ in
                        AxisValueLabel().foregroundStyle(NonnaTheme.secondaryInk)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(NonnaTheme.line.opacity(0.5))
                        AxisValueLabel {
                            if let minutes = value.as(Double.self) {
                                Text(Int(minutes.rounded()).minutesString)
                            }
                        }
                        .foregroundStyle(NonnaTheme.secondaryInk)
                    }
                }
                .frame(height: 170)
                HStack {
                    Label(snapshot.peakHour.map { "Peak \(hourSpanLabel($0.hour))" } ?? "No peak yet", systemImage: "clock")
                    Spacer()
                    Text(snapshot.peakWeekday.map { "Best day: \($0.label)" } ?? "")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(NonnaTheme.secondaryInk)
            }
        }
    }

    @ViewBuilder
    private var distributionCard: some View {
        switch metric {
        case .breakTime, .breakOvertime:
            breakBehaviorCard
        case .completed:
            outcomeCard
        default:
            taskAllocationCard
        }
    }

    private var taskAllocationCard: some View {
        NonnaCard {
            VStack(alignment: .leading, spacing: 14) {
                DetailSectionTitle(title: "By task")
                if snapshot.tasks.isEmpty {
                    DetailEmpty(message: "No focus in this range yet.")
                } else {
                    let maximum = max(1, snapshot.tasks.first?.seconds ?? 1)
                    ForEach(snapshot.tasks.prefix(6)) { task in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Circle().fill(NonnaTheme.taskColor(for: task.colorHex)).frame(width: 7, height: 7)
                                Text(task.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                Spacer()
                                Text(task.seconds.focusDurationString)
                                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                                    .foregroundStyle(NonnaTheme.secondaryInk)
                            }
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(NonnaTheme.line.opacity(0.6))
                                    Capsule()
                                        .fill(NonnaTheme.taskColor(for: task.colorHex))
                                        .frame(width: proxy.size.width * Double(task.seconds) / Double(maximum))
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                    Spacer(minLength: 0)
                    Text("Your top task has \(percent(snapshot.topTaskShare)) of focus time.")
                        .font(.system(size: 10))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
            }
            .frame(minHeight: 225, alignment: .top)
        }
    }

    private var breakBehaviorCard: some View {
        let values = [
            DistributionSlice(name: "On plan", value: snapshot.breakOnPlanCount, color: NonnaTheme.sage),
            DistributionSlice(name: "Ended early", value: snapshot.breakEarlyCount, color: NonnaTheme.secondaryInk),
            DistributionSlice(name: "Overtime", value: snapshot.breakOvertimeCount, color: NonnaTheme.gold),
            DistributionSlice(name: "Skipped", value: snapshot.skippedBreakCount, color: NonnaTheme.alert)
        ]
        return NonnaCard {
            VStack(alignment: .leading, spacing: 14) {
                DetailSectionTitle(title: "How breaks ended")
                if snapshot.breakCount == 0 {
                    DetailEmpty(message: "No breaks in this range yet.")
                } else {
                    HStack(spacing: 20) {
                        Chart(values) { item in
                            SectorMark(
                                angle: .value("Breaks", item.value),
                                innerRadius: .ratio(0.64),
                                angularInset: 1.5
                            )
                            .cornerRadius(3)
                            .foregroundStyle(item.color)
                        }
                        .frame(width: 155, height: 155)
                        VStack(alignment: .leading, spacing: 11) {
                            ForEach(values) { item in
                                HStack {
                                    Circle().fill(item.color).frame(width: 7, height: 7)
                                    Text(item.name).font(.system(size: 10, weight: .medium))
                                    Spacer()
                                    Text("\(item.value)").font(.system(size: 10, weight: .semibold).monospacedDigit())
                                }
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 225, alignment: .top)
        }
    }

    private var outcomeCard: some View {
        let values = [
            DistributionSlice(name: "Completed", value: snapshot.completedCount, color: NonnaTheme.sage),
            DistributionSlice(name: "Finished early", value: snapshot.earlyCount, color: NonnaTheme.gold),
            DistributionSlice(name: "Abandoned", value: snapshot.abandonedCount, color: NonnaTheme.alert)
        ]
        return NonnaCard {
            VStack(alignment: .leading, spacing: 14) {
                DetailSectionTitle(title: "How focus blocks ended")
                if snapshot.recordedSessionCount == 0 {
                    DetailEmpty(message: "No focus blocks in this range yet.")
                } else {
                    HStack(spacing: 20) {
                        Chart(values) { item in
                            SectorMark(
                                angle: .value("Sessions", item.value),
                                innerRadius: .ratio(0.64),
                                angularInset: 1.5
                            )
                            .cornerRadius(3)
                            .foregroundStyle(item.color)
                        }
                        .frame(width: 155, height: 155)
                        VStack(alignment: .leading, spacing: 11) {
                            ForEach(values) { item in
                                HStack {
                                    Circle().fill(item.color).frame(width: 7, height: 7)
                                    Text(item.name).font(.system(size: 10, weight: .medium))
                                    Spacer()
                                    Text("\(item.value)").font(.system(size: 10, weight: .semibold).monospacedDigit())
                                }
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 225, alignment: .top)
        }
    }

    private var methodologyCard: some View {
        NonnaCard(padding: 17) {
            HStack(alignment: .top, spacing: 22) {
                DetailSectionTitle(title: "How these are calculated")
                    .frame(width: 180, alignment: .leading)
                MethodNote(title: "Consistency score", text: "62% how often you focus + 38% how even your totals are on days you focus.")
                MethodNote(title: "Deep-work share", text: "Share of finished focus blocks lasting at least 50 minutes.")
                MethodNote(title: "Pause cost", text: "Paused time divided by focus time plus paused time.")
                MethodNote(title: "Goal rate", text: "Share of days that reached your daily goal, counting days you didn't focus.")
            }
        }
    }

    private var detailStats: [DetailStat] {
        switch metric {
        case .focus:
            [
                DetailStat(label: "Focused", value: snapshot.totalFocusSeconds.focusDurationString, detail: "Across \(snapshot.sessionCount) finished blocks"),
                DetailStat(label: "Active-day average", value: snapshot.averageActiveDaySeconds.focusDurationString, detail: "Days you focused"),
                DetailStat(label: "Median block", value: snapshot.medianSessionSeconds.focusDurationString, detail: "Less skewed by long blocks"),
                DetailStat(label: "Goal rate", value: percent(snapshot.goalHitRate), detail: "\(snapshot.goalHitDays) of \(snapshot.dayCount) days")
            ]
        case .breakTime:
            [
                DetailStat(label: "Break time", value: snapshot.totalBreakSeconds.focusDurationString, detail: "\(snapshot.breakCount) breaks"),
                DetailStat(label: "Focus : break", value: ratioText, detail: "Hours of focus per hour of break"),
                DetailStat(label: "Average break", value: snapshot.averageBreakSeconds.focusDurationString, detail: "In this range"),
                DetailStat(label: "Skipped", value: "\(snapshot.skippedBreakCount)", detail: percent(breakSkipRate) + " of breaks")
            ]
        case .breakOvertime:
            [
                DetailStat(label: "Break overtime", value: snapshot.totalBreakOvertimeSeconds.focusDurationString, detail: "Past planned length"),
                DetailStat(label: "Average overrun", value: snapshot.averageBreakOvertimeSeconds.focusDurationString, detail: "Per break that ran over"),
                DetailStat(label: "Overtime share", value: percent(snapshot.breakOvertimeRate), detail: "Of all break time"),
                DetailStat(label: "Largest day", value: snapshot.largestBreakOvertimeSeconds.focusDurationString, detail: "Break overtime in one day")
            ]
        case .daysUsed:
            [
                DetailStat(label: "Active days", value: "\(snapshot.activeDays)", detail: "Of \(snapshot.dayCount) days in range"),
                DetailStat(label: "Activity rate", value: percent(snapshot.activeRate), detail: "Share of days you focused"),
                DetailStat(label: "Goal days", value: "\(snapshot.goalHitDays)", detail: "At least \(dailyGoalMinutes)m focused"),
                DetailStat(label: "Lifetime days", value: "\(snapshot.lifetimeUsedDays)", detail: "Since your first block")
            ]
        case .rhythm:
            [
                DetailStat(label: "Current streak", value: "\(snapshot.currentStreak)d", detail: "Ending today or yesterday"),
                DetailStat(label: "Best streak", value: "\(snapshot.longestStreak)d", detail: "Longest run of days"),
                DetailStat(label: "Consistency score", value: "\(snapshot.consistencyScore)", detail: "How often and how evenly you focus"),
                DetailStat(label: "7-day change", value: momentumValue, detail: momentumDetail)
            ]
        case .completed:
            [
                DetailStat(label: "Completed", value: "\(snapshot.completedCount)", detail: "Full planned intervals"),
                DetailStat(label: "Completion rate", value: percent(snapshot.completionRate), detail: "Of all recorded blocks"),
                DetailStat(label: "Pause cost", value: percent(snapshot.pauseRatio), detail: snapshot.totalPausedSeconds.focusDurationString + " paused"),
                DetailStat(label: "Average rating", value: snapshot.averageRating.map { String(format: "%.1f / 5", $0) } ?? "–", detail: "\(snapshot.ratedCount) rated sessions")
            ]
        }
    }

    private var narratives: [NarrativeInsight] {
        let bestDay = snapshot.bestDay.map {
            "\($0.date.formatted(.dateTime.weekday(.wide))), with \($0.focusSeconds.focusDurationString)."
        } ?? "Not enough sessions yet."
        let peak = snapshot.peakHour.map { "\(hourSpanLabel($0.hour)), with \($0.seconds.focusDurationString) of focus." }
            ?? "Not enough sessions yet."
        switch metric {
        case .focus:
            return [
                NarrativeInsight(icon: "chart.line.uptrend.xyaxis", title: "This week vs last", text: momentumSentence),
                NarrativeInsight(icon: "clock", title: "Peak hour", text: peak),
                NarrativeInsight(icon: "rectangle.compress.vertical", title: "Block length", text: "Median block: \(snapshot.medianSessionSeconds.focusDurationString). \(percent(snapshot.deepWorkShare)) of finished blocks ran 50 minutes or more.")
            ]
        case .breakTime:
            return [
                NarrativeInsight(icon: "scalemass", title: "Focus to break", text: snapshot.focusToBreakRatio.map { String(format: "%.1f hours of focus for every hour of break.", $0) } ?? "Take a break to see this."),
                NarrativeInsight(icon: "forward.end", title: "Skipped breaks", text: "\(snapshot.skippedBreakCount) skipped and \(snapshot.breakEarlyCount) ended early in this range."),
                NarrativeInsight(icon: "clock.arrow.2.circlepath", title: "Average break", text: "Your average break is \(snapshot.averageBreakSeconds.focusDurationString).")
            ]
        case .breakOvertime:
            return [
                NarrativeInsight(icon: "exclamationmark.arrow.triangle.2.circlepath", title: "Overtime share", text: "\(percent(snapshot.breakOvertimeRate)) of break time ran past plan."),
                NarrativeInsight(icon: "calendar", title: "Most in a day", text: "Most break overtime in one day: \(snapshot.largestBreakOvertimeSeconds.focusDurationString)."),
                NarrativeInsight(icon: "timer", title: "Average overrun", text: "Breaks that run over go \(snapshot.averageBreakOvertimeSeconds.focusDurationString) past plan on average.")
            ]
        case .daysUsed:
            return [
                NarrativeInsight(icon: "calendar.badge.checkmark", title: "Active days", text: "You focused on \(snapshot.activeDays) of \(snapshot.dayCount) days (\(percent(snapshot.activeRate)))."),
                NarrativeInsight(icon: "target", title: "Goal days", text: "\(snapshot.goalHitDays) days hit your \(dailyGoalMinutes)-minute goal."),
                NarrativeInsight(icon: "crown", title: "Best day", text: bestDay)
            ]
        case .rhythm:
            return [
                NarrativeInsight(icon: "waveform.path.ecg", title: "Consistency score", text: "\(snapshot.consistencyScore) / 100, based on how often you focus and how even your daily totals are."),
                NarrativeInsight(icon: "flame", title: "Streak", text: "Current: \(snapshot.currentStreak) days. Best: \(snapshot.longestStreak) days."),
                NarrativeInsight(icon: "chart.line.uptrend.xyaxis", title: "This week vs last", text: momentumSentence)
            ]
        case .completed:
            return [
                NarrativeInsight(icon: "checkmark.seal", title: "Completion", text: "\(percent(snapshot.completionRate)) of focus blocks ran to their planned length."),
                NarrativeInsight(icon: "pause.circle", title: "Pause cost", text: "Pauses took up \(percent(snapshot.pauseRatio)) of focus plus pause time."),
                NarrativeInsight(icon: "star", title: "Ratings", text: snapshot.averageRating.map { String(format: "Average %.1f / 5 across %d rated blocks.", $0, snapshot.ratedCount) } ?? "Rate your sessions to see this.")
            ]
        }
    }

    private func tooltipLines(for day: DeepDiveDay) -> [String] {
        switch metric {
        case .focus:
            return ["\(day.focusSeconds.focusDurationString) focus", "\(day.rollingFocusSeconds.focusDurationString) 7-day average", "\(day.sessionCount) blocks"]
        case .breakTime:
            return ["\(day.breakSeconds.focusDurationString) break", "\(day.breakOvertimeSeconds.focusDurationString) overtime"]
        case .breakOvertime:
            return ["\(day.breakOvertimeSeconds.focusDurationString) break overtime", "\(day.focusOvertimeSeconds.focusDurationString) focus overtime"]
        case .daysUsed:
            return [day.focusSeconds > 0 ? "Active day" : "Inactive day", "\(day.focusSeconds.focusDurationString) focus"]
        case .rhythm:
            return ["\(day.focusSeconds.focusDurationString) focus", "\(day.rollingFocusSeconds.focusDurationString) 7-day average"]
        case .completed:
            return ["\(day.completedCount) completed", "\(day.earlyCount) early, \(day.abandonedCount) abandoned"]
        }
    }

    private var primaryChartTitle: String {
        switch metric {
        case .focus: "Daily focus and 7-day average"
        case .breakTime: "Planned break time and overtime"
        case .breakOvertime: "Overtime by day"
        case .daysUsed: "Daily focus against your goal"
        case .rhythm: "7-day average"
        case .completed: "How blocks ended each day"
        }
    }

    private var rangeDescription: String {
        switch range {
        case .week: "Last 7 days"
        case .month: "Last 30 days"
        case .quarter: "Last 90 days"
        case .all: "Lifetime"
        }
    }

    private var xAxisStride: Int {
        switch range {
        case .week: 1
        case .month: 5
        case .quarter: 14
        case .all: 30
        }
    }

    private var ratioText: String {
        snapshot.focusToBreakRatio.map { String(format: "%.1f : 1", $0) } ?? "–"
    }

    private var breakSkipRate: Double {
        snapshot.breakCount == 0 ? 0 : Double(snapshot.skippedBreakCount) / Double(snapshot.breakCount)
    }

    private var momentumValue: String {
        snapshot.weekChange.map { ($0 >= 0 ? "+" : "") + percent($0) } ?? "–"
    }

    private var momentumDetail: String {
        snapshot.weekChange == nil ? "Needs focus in the 7 days before" : "Last 7 days vs the 7 before"
    }

    private var momentumSentence: String {
        guard let change = snapshot.weekChange else { return "No focus in the 7 days before to compare with." }
        if abs(change) < 0.05 { return "About the same as the 7 days before." }
        return "\(change > 0 ? "Up" : "Down") \(percent(abs(change))) on the 7 days before."
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    private func hourLabel(_ hour: Int) -> String {
        let normalized = ((hour % 24) + 24) % 24
        let suffix = normalized < 12 ? "a" : "p"
        let twelve = normalized % 12 == 0 ? 12 : normalized % 12
        return "\(twelve)\(suffix)"
    }

    private func hourSpanLabel(_ hour: Int) -> String { "\(hourLabel(hour))–\(hourLabel(hour + 1))" }
}

private struct DetailStat: Identifiable {
    let label: String
    let value: String
    let detail: String
    var id: String { label }
}

private struct DetailStatTile: View {
    let stat: DetailStat
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(stat.label)
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(NonnaTheme.secondaryInk)
            Text(stat.value)
                .font(.system(size: 25, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(stat.detail)
                .font(.system(size: 11))
                .foregroundStyle(NonnaTheme.secondaryInk)
                .lineLimit(2)
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)
        .background(NonnaTheme.paper.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(LinearGradient(colors: [tint.opacity(0.22), NonnaTheme.line], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
        }
    }
}

private struct NarrativeInsight: Identifiable {
    let icon: String
    let title: String
    let text: String
    var id: String { title }
}

private struct IntelligenceCallout: View {
    let insight: NarrativeInsight
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: insight.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.11))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(.system(size: 11, weight: .semibold))
                Text(insight.text)
                    .font(.system(size: 10))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
        .background(NonnaTheme.raisedPaper.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }
    }
}

private struct DetailSectionTitle: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
        }
    }
}

private struct DetailLegend: View {
    let items: [(String, Color)]

    var body: some View {
        HStack(spacing: 13) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 5) {
                    Circle().fill(item.1).frame(width: 6, height: 6)
                    Text(item.0)
                }
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(NonnaTheme.secondaryInk)
    }
}

private struct DistributionSlice: Identifiable {
    let name: String
    let value: Int
    let color: Color
    var id: String { name }
}

private struct DetailEmpty: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(NonnaTheme.secondaryInk)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
            .multilineTextAlignment(.center)
    }
}

private struct MethodNote: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(NonnaTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
