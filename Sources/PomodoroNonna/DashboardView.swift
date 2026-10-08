import Charts
import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var hoveredDay: Date?
    @State private var selectedMetric: DashboardMetric?

    private var analytics: AnalyticsSnapshot { model.analytics }

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
                    eyebrow: "Performance",
                    title: "Dashboard",
                    subtitle: "Private, local analytics"
                )

                let totalBreakSeconds = model.breakSessions.reduce(0) { $0 + $1.restedSeconds }
                let breakOvertimeSeconds = model.breakSessions.reduce(0) { $0 + $1.overtimeSeconds }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                    DashboardMetricButton(
                        metric: .focus,
                        icon: "hourglass",
                        label: "Focused in total",
                        value: analytics.totalFocusSeconds.focusDurationString,
                        detail: "Across every task",
                        tint: NonnaTheme.terracotta,
                        action: { selectedMetric = .focus }
                    )
                    DashboardMetricButton(
                        metric: .breakTime,
                        icon: "cup.and.saucer.fill",
                        label: "Break time",
                        value: totalBreakSeconds.focusDurationString,
                        detail: "Recorded rest periods",
                        tint: NonnaTheme.sage,
                        action: { selectedMetric = .breakTime }
                    )
                    DashboardMetricButton(
                        metric: .breakOvertime,
                        icon: "clock.badge.exclamationmark",
                        label: "Break overtime",
                        value: breakOvertimeSeconds.focusDurationString,
                        detail: "Beyond planned breaks",
                        tint: NonnaTheme.gold,
                        action: { selectedMetric = .breakOvertime }
                    )
                    DashboardMetricButton(
                        metric: .daysUsed,
                        icon: "calendar.badge.checkmark",
                        label: "Days used",
                        value: "\(analytics.usedDays)",
                        detail: "Days with focused time",
                        tint: NonnaTheme.gold,
                        action: { selectedMetric = .daysUsed }
                    )
                    DashboardMetricButton(
                        metric: .rhythm,
                        icon: "flame.fill",
                        label: "Current rhythm",
                        value: "\(analytics.currentStreak) \(analytics.currentStreak == 1 ? "day" : "days")",
                        detail: "Best: \(analytics.longestStreak) \(analytics.longestStreak == 1 ? "day" : "days")",
                        tint: NonnaTheme.sage,
                        action: { selectedMetric = .rhythm }
                    )
                    DashboardMetricButton(
                        metric: .completed,
                        icon: "checkmark.seal.fill",
                        label: "Completed sessions",
                        value: "\(analytics.completedSessions)",
                        detail: "Full planned intervals",
                        tint: NonnaTheme.secondaryInk,
                        action: { selectedMetric = .completed }
                    )
                }

                HStack(alignment: .top, spacing: 18) {
                    recentActivityCard
                        .frame(maxWidth: .infinity)
                    taskTotalsCard
                        .frame(width: 330)
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
        }
    }

    private var recentActivityCard: some View {
        // Capture one immutable snapshot for the chart and its hover handler. Reading the
        // computed `analytics` property from every pointer-move callback recalculates the
        // entire history dozens of times per second on larger local databases.
        let snapshot = analytics
        return NonnaCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("LAST 14 DAYS")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(1.7)
                            .foregroundStyle(NonnaTheme.secondaryInk)
                        Text("Focus rhythm")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    Spacer()
                    let total = snapshot.recentDays.reduce(0) { $0 + $1.seconds }
                    Text(total.focusDurationString)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(NonnaTheme.terracotta)
                }

                if snapshot.recentDays.allSatisfy({ $0.seconds == 0 }) {
                    EmptyState(
                        icon: "chart.bar",
                        title: "No focus data",
                        message: "Complete a focus session to populate this chart."
                    )
                } else {
                    Chart {
                        if let hovered = snapshot.recentDays.first(where: { $0.day == hoveredDay }) {
                            RuleMark(x: .value("Day", hovered.day, unit: .day))
                                .foregroundStyle(NonnaTheme.strongLine)
                        }
                        ForEach(snapshot.recentDays) { item in
                            BarMark(
                                x: .value("Day", item.day, unit: .day),
                                y: .value("Minutes", Double(item.seconds) / 60)
                            )
                            .foregroundStyle(NonnaTheme.terracotta)
                            .cornerRadius(2)
                            .opacity(hoveredDay == nil || hoveredDay == item.day ? 1 : 0.45)
                        }
                    }
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
                        AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.narrow))
                                .foregroundStyle(NonnaTheme.secondaryInk)
                            AxisGridLine().foregroundStyle(.clear)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(NonnaTheme.line.opacity(0.55))
                            AxisValueLabel {
                                if let minutes = value.as(Double.self) {
                                    Text(minutes >= 60 ? "\(Int(minutes / 60))h" : "\(Int(minutes))m")
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
                    Text("LIFETIME")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.7)
                        .foregroundStyle(NonnaTheme.secondaryInk)
                    Text("Time by task")
                        .font(.system(size: 18, weight: .semibold))
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
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
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
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("CONSISTENCY")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(1.7)
                            .foregroundStyle(NonnaTheme.secondaryInk)
                        Text("12 weeks")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    Spacer()
                    Text("A day counts when you focus for any amount of time.")
                        .font(.system(size: 11, design: .default))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
                UsageHeatmap(sessions: model.sessions)
            }
        }
    }
}

private struct DashboardMetricButton: View {
    let metric: DashboardMetric
    let icon: String
    let label: String
    let value: String
    let detail: String
    let tint: Color
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                MetricCard(icon: icon, label: label, value: value, detail: detail, tint: tint)
                    .frame(maxWidth: .infinity)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isHovering ? tint : NonnaTheme.secondaryInk)
                    .frame(width: 25, height: 25)
                    .background(NonnaTheme.raisedPaper.opacity(isHovering ? 1 : 0.7))
                    .clipShape(Circle())
                    .overlay { Circle().stroke(isHovering ? tint.opacity(0.4) : NonnaTheme.line, lineWidth: 0.8) }
                    .padding(16)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isHovering ? tint.opacity(0.42) : .clear, lineWidth: 1)
            }
            .shadow(color: isHovering ? tint.opacity(0.1) : .clear, radius: 18, y: 8)
            .scaleEffect(isHovering ? 1.008 : 1)
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : NonnaMotion.quick, value: isHovering)
        .onHover { isHovering = $0 }
        .help("Open \(metric.title)")
        .accessibilityLabel("\(label), \(value). Open detailed analytics")
    }
}

private struct UsageHeatmap: View {
    let sessions: [FocusSession]
    private let calendar = Calendar.current

    private var days: [(Date, Int)] {
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -83, to: today) ?? today
        let grouped = Dictionary(grouping: sessions.filter { $0.outcome != .abandoned }) {
            calendar.startOfDay(for: $0.startedAt)
        }
        return (0..<84).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return (day, grouped[day, default: []].reduce(0) { $0 + $1.focusedSeconds })
        }
    }

    var body: some View {
        let rows = Array(repeating: GridItem(.fixed(15), spacing: 5), count: 7)
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: rows, spacing: 5) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, item in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color(for: item.1))
                        .frame(width: 15, height: 15)
                        .help("\(item.0.formatted(date: .abbreviated, time: .omitted)): \(item.1.focusDurationString)")
                }
            }
        }
        .frame(height: 135)
    }

    private func color(for seconds: Int) -> Color {
        switch seconds {
        case 0: NonnaTheme.line.opacity(0.55)
        case 1..<1500: NonnaTheme.sage.opacity(0.28)
        case 1500..<3600: NonnaTheme.sage.opacity(0.5)
        case 3600..<7200: NonnaTheme.sage.opacity(0.72)
        default: NonnaTheme.sage
        }
    }
}
