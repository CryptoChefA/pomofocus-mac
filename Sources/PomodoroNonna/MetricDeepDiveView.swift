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
        case .focus: "Focus intelligence"
        case .breakTime: "Recovery intelligence"
        case .breakOvertime: "Break discipline"
        case .daysUsed: "Activity intelligence"
        case .rhythm: "Consistency intelligence"
        case .completed: "Session quality"
        }
    }

    var eyebrow: String {
        switch self {
        case .focus: "DEEP WORK"
        case .breakTime: "RECOVERY"
        case .breakOvertime: "OVERRUN"
        case .daysUsed: "ACTIVITY"
        case .rhythm: "RHYTHM"
        case .completed: "EXECUTION"
        }
    }

    var subtitle: String {
        switch self {
        case .focus: "Volume, momentum, work shape, peak windows and task concentration."
        case .breakTime: "How deliberately you recover between demanding blocks."
        case .breakOvertime: "Where planned rest turns into drift—and how often it happens."
        case .daysUsed: "Your active-day density, goal attainment and long-term adherence."
        case .rhythm: "A measured view of consistency, momentum and repeatable working patterns."
        case .completed: "Completion, interruption, pause cost and perceived session quality."
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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
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
        .foregroundStyle(NonnaTheme.ink)
        .tint(metric.tint)
        .frame(minWidth: 1040, idealWidth: 1160, minHeight: 720, idealHeight: 820)
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
                Text(metric.eyebrow)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(metric.tint)
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
                        Text(rangeDescription.uppercased())
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .tracking(1.5)
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
            DetailLegend(items: [("Daily", NonnaTheme.darkTerracotta), ("7-day rhythm", NonnaTheme.sage)])
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
                DetailSectionTitle(eyebrow: "TIME SIGNATURE", title: "Where your focus lands")
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
                                Text(minutes >= 60 ? "\(Int(minutes / 60))h" : "\(Int(minutes))m")
                            }
                        }
                        .foregroundStyle(NonnaTheme.secondaryInk)
                    }
                }
                .frame(height: 170)
                HStack {
                    Label(snapshot.peakHour.map { "Peak \(hourSpanLabel($0.hour))" } ?? "No peak yet", systemImage: "clock")
                    Spacer()
                    Text(snapshot.peakWeekday.map { "Best weekday · \($0.label)" } ?? "")
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
                DetailSectionTitle(eyebrow: "ALLOCATION", title: "What received your attention")
                if snapshot.tasks.isEmpty {
                    DetailEmpty(message: "Task distribution will appear after your first focused block in this range.")
                } else {
                    let maximum = max(1, snapshot.tasks.first?.seconds ?? 1)
                    ForEach(snapshot.tasks.prefix(6)) { task in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Circle().fill(NonnaTheme.taskColor(for: task.colorHex)).frame(width: 7, height: 7)
                                Text(task.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                Spacer()
                                Text(task.seconds.focusDurationString)
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
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
                    Text("Top task holds \(percent(snapshot.topTaskShare)) of focus time.")
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
                DetailSectionTitle(eyebrow: "BREAK OUTCOMES", title: "How rest periods ended")
                if snapshot.breakCount == 0 {
                    DetailEmpty(message: "Break behavior will appear after you record rest periods.")
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
                                    Text("\(item.value)").font(.system(size: 10, weight: .semibold, design: .monospaced))
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
                DetailSectionTitle(eyebrow: "OUTCOMES", title: "How focus blocks ended")
                if snapshot.recordedSessionCount == 0 {
                    DetailEmpty(message: "Session outcomes will appear after your first focus block.")
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
                                    Text("\(item.value)").font(.system(size: 10, weight: .semibold, design: .monospaced))
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
                DetailSectionTitle(eyebrow: "METHODOLOGY", title: "Metrics you can trust")
                    .frame(width: 180, alignment: .leading)
                MethodNote(title: "Rhythm score", text: "62% active-day frequency + 38% consistency of volume on active days.")
                MethodNote(title: "Deep-work share", text: "The share of finished focus blocks lasting at least 50 minutes.")
                MethodNote(title: "Pause cost", text: "Paused time divided by focus time plus paused time.")
                MethodNote(title: "Goal rate", text: "Days reaching your configured daily focus goal, including inactive days.")
            }
        }
    }

    private var detailStats: [DetailStat] {
        switch metric {
        case .focus:
            [
                DetailStat(label: "Focused", value: snapshot.totalFocusSeconds.focusDurationString, detail: "Across \(snapshot.sessionCount) finished blocks"),
                DetailStat(label: "Active-day average", value: snapshot.averageActiveDaySeconds.focusDurationString, detail: "Only days with focused time"),
                DetailStat(label: "Median block", value: snapshot.medianSessionSeconds.focusDurationString, detail: "Less distorted by long sessions"),
                DetailStat(label: "Goal attainment", value: percent(snapshot.goalHitRate), detail: "\(snapshot.goalHitDays) of \(snapshot.dayCount) days")
            ]
        case .breakTime:
            [
                DetailStat(label: "Recovery time", value: snapshot.totalBreakSeconds.focusDurationString, detail: "\(snapshot.breakCount) recorded breaks"),
                DetailStat(label: "Focus : break", value: ratioText, detail: "Focused hours per recovery hour"),
                DetailStat(label: "Average break", value: snapshot.averageBreakSeconds.focusDurationString, detail: "Across this range"),
                DetailStat(label: "Skipped", value: "\(snapshot.skippedBreakCount)", detail: percent(breakSkipRate) + " of break outcomes")
            ]
        case .breakOvertime:
            [
                DetailStat(label: "Break overtime", value: snapshot.totalBreakOvertimeSeconds.focusDurationString, detail: "Beyond planned recovery"),
                DetailStat(label: "Average overrun", value: snapshot.averageBreakOvertimeSeconds.focusDurationString, detail: "Per overtime break"),
                DetailStat(label: "Overtime share", value: percent(snapshot.breakOvertimeRate), detail: "Of all break time"),
                DetailStat(label: "Largest day", value: snapshot.largestBreakOvertimeSeconds.focusDurationString, detail: "Combined break overtime")
            ]
        case .daysUsed:
            [
                DetailStat(label: "Active days", value: "\(snapshot.activeDays)", detail: "Of \(snapshot.dayCount) days in range"),
                DetailStat(label: "Activity rate", value: percent(snapshot.activeRate), detail: "Days containing focused work"),
                DetailStat(label: "Goal days", value: "\(snapshot.goalHitDays)", detail: "At least \(dailyGoalMinutes)m focused"),
                DetailStat(label: "Lifetime days", value: "\(snapshot.lifetimeUsedDays)", detail: "Since your first recorded block")
            ]
        case .rhythm:
            [
                DetailStat(label: "Current streak", value: "\(snapshot.currentStreak)d", detail: "Today or yesterday anchored"),
                DetailStat(label: "Best streak", value: "\(snapshot.longestStreak)d", detail: "Lifetime consecutive days"),
                DetailStat(label: "Rhythm score", value: "\(snapshot.consistencyScore)", detail: "Frequency + volume regularity"),
                DetailStat(label: "7-day momentum", value: momentumValue, detail: momentumDetail)
            ]
        case .completed:
            [
                DetailStat(label: "Completed", value: "\(snapshot.completedCount)", detail: "Full planned intervals"),
                DetailStat(label: "Completion rate", value: percent(snapshot.completionRate), detail: "Across every recorded outcome"),
                DetailStat(label: "Pause cost", value: percent(snapshot.pauseRatio), detail: snapshot.totalPausedSeconds.focusDurationString + " paused"),
                DetailStat(label: "Focus quality", value: snapshot.averageRating.map { String(format: "%.1f / 5", $0) } ?? "–", detail: "\(snapshot.ratedCount) rated sessions")
            ]
        }
    }

    private var narratives: [NarrativeInsight] {
        let bestDay = snapshot.bestDay.map {
            "\($0.date.formatted(.dateTime.weekday(.wide))) led with \($0.focusSeconds.focusDurationString)."
        } ?? "More sessions are needed before a strongest day emerges."
        let peak = snapshot.peakHour.map { "Your strongest window is \(hourSpanLabel($0.hour)), with \($0.seconds.focusDurationString) recorded." }
            ?? "A prime focus window will emerge as you record more sessions."
        switch metric {
        case .focus:
            return [
                NarrativeInsight(icon: "chart.line.uptrend.xyaxis", title: "Momentum", text: momentumSentence),
                NarrativeInsight(icon: "clock", title: "Prime window", text: peak),
                NarrativeInsight(icon: "rectangle.compress.vertical", title: "Work shape", text: "Median block: \(snapshot.medianSessionSeconds.focusDurationString). \(percent(snapshot.deepWorkShare)) qualify as 50+ minute deep-work blocks.")
            ]
        case .breakTime:
            return [
                NarrativeInsight(icon: "scalemass", title: "Recovery balance", text: snapshot.focusToBreakRatio.map { String(format: "You focus %.1f hours for every recovery hour.", $0) } ?? "Record breaks to establish your focus-to-recovery balance."),
                NarrativeInsight(icon: "forward.end", title: "Break completion", text: "\(snapshot.skippedBreakCount) skipped and \(snapshot.breakEarlyCount) ended early in this range."),
                NarrativeInsight(icon: "clock.arrow.2.circlepath", title: "Average reset", text: "A typical recorded break lasts \(snapshot.averageBreakSeconds.focusDurationString).")
            ]
        case .breakOvertime:
            return [
                NarrativeInsight(icon: "exclamationmark.arrow.triangle.2.circlepath", title: "Drift rate", text: "\(percent(snapshot.breakOvertimeRate)) of all recovery time happened beyond the plan."),
                NarrativeInsight(icon: "calendar", title: "Largest overrun", text: "Your heaviest single-day break overrun was \(snapshot.largestBreakOvertimeSeconds.focusDurationString)."),
                NarrativeInsight(icon: "timer", title: "Typical overrun", text: "An overtime break runs \(snapshot.averageBreakOvertimeSeconds.focusDurationString) beyond plan on average.")
            ]
        case .daysUsed:
            return [
                NarrativeInsight(icon: "calendar.badge.checkmark", title: "Adherence", text: "You were active on \(snapshot.activeDays) of \(snapshot.dayCount) days—\(percent(snapshot.activeRate))."),
                NarrativeInsight(icon: "target", title: "Goal conversion", text: "\(snapshot.goalHitDays) days reached the \(dailyGoalMinutes)-minute target."),
                NarrativeInsight(icon: "crown", title: "Strongest day", text: bestDay)
            ]
        case .rhythm:
            return [
                NarrativeInsight(icon: "waveform.path.ecg", title: "Rhythm score", text: "\(snapshot.consistencyScore) / 100, blending active-day frequency with steadiness of daily volume."),
                NarrativeInsight(icon: "flame", title: "Streak", text: "Current: \(snapshot.currentStreak) days. Lifetime best: \(snapshot.longestStreak) days."),
                NarrativeInsight(icon: "chart.line.uptrend.xyaxis", title: "Direction", text: momentumSentence)
            ]
        case .completed:
            return [
                NarrativeInsight(icon: "checkmark.seal", title: "Execution", text: "\(percent(snapshot.completionRate)) of recorded focus blocks reached their planned finish."),
                NarrativeInsight(icon: "pause.circle", title: "Interruption cost", text: "Paused time consumed \(percent(snapshot.pauseRatio)) of focus-plus-pause time."),
                NarrativeInsight(icon: "star", title: "Perceived quality", text: snapshot.averageRating.map { String(format: "Your average rating is %.1f / 5 across %d rated blocks.", $0, snapshot.ratedCount) } ?? "Rate sessions after completion to connect time spent with perceived quality.")
            ]
        }
    }

    private func tooltipLines(for day: DeepDiveDay) -> [String] {
        switch metric {
        case .focus:
            return ["\(day.focusSeconds.focusDurationString) focus", "\(day.rollingFocusSeconds.focusDurationString) 7-day average", "\(day.sessionCount) recorded blocks"]
        case .breakTime:
            return ["\(day.breakSeconds.focusDurationString) recovery", "\(day.breakOvertimeSeconds.focusDurationString) overtime"]
        case .breakOvertime:
            return ["\(day.breakOvertimeSeconds.focusDurationString) break overtime", "\(day.focusOvertimeSeconds.focusDurationString) focus overtime"]
        case .daysUsed:
            return [day.focusSeconds > 0 ? "Active day" : "Inactive day", "\(day.focusSeconds.focusDurationString) focus"]
        case .rhythm:
            return ["\(day.focusSeconds.focusDurationString) focus", "\(day.rollingFocusSeconds.focusDurationString) rolling rhythm"]
        case .completed:
            return ["\(day.completedCount) completed", "\(day.earlyCount) early · \(day.abandonedCount) abandoned"]
        }
    }

    private var primaryChartTitle: String {
        switch metric {
        case .focus: "Daily focus and rolling momentum"
        case .breakTime: "Planned recovery versus overtime"
        case .breakOvertime: "Where time runs beyond plan"
        case .daysUsed: "Active days and goal attainment"
        case .rhythm: "Your seven-day working rhythm"
        case .completed: "Daily session outcomes"
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
        snapshot.weekChange == nil ? "Needs a prior seven-day baseline" : "Latest 7 days vs previous 7"
    }

    private var momentumSentence: String {
        guard let change = snapshot.weekChange else { return "A second full week will establish a meaningful momentum baseline." }
        if abs(change) < 0.05 { return "Your last seven days are essentially level with the previous seven." }
        return "Focus volume is \(percent(abs(change))) \(change > 0 ? "higher" : "lower") than the previous seven days."
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
            Text(stat.label.uppercased())
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.25)
                .foregroundStyle(NonnaTheme.secondaryInk)
            Text(stat.value)
                .font(.system(size: 25, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(stat.detail)
                .font(.system(size: 9))
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
    let eyebrow: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(eyebrow)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(NonnaTheme.secondaryInk)
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
        .font(.system(size: 9, weight: .medium))
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
                .font(.system(size: 9))
                .foregroundStyle(NonnaTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
