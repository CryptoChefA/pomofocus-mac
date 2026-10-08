import Charts
import SwiftUI

/// Deeper, range-filtered analytics shown under the lifetime cards on the Dashboard.
struct InsightsSection: View {
    @Environment(AppModel.self) private var model
    @State private var range: InsightsRange = .month

    var body: some View {
        let insights = InsightsSnapshot.calculate(
            sessions: model.data.sessions,
            breaks: model.data.breaks ?? [],
            dailyGoalMinutes: model.settings.dailyGoalMinutes,
            range: range
        )

        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("INSIGHTS")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.7)
                        .foregroundStyle(NonnaTheme.terracotta)
                    Text("Patterns in your focus")
                        .font(.system(size: 22, weight: .semibold))
                }
                Spacer()
                Picker("Range", selection: $range) {
                    ForEach(InsightsRange.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 230)
            }

            if insights.sessionCount == 0 {
                NonnaCard {
                    EmptyState(
                        icon: "chart.xyaxis.line",
                        title: "Nothing in this range yet",
                        message: "Finish a focus session, or widen the range, to see patterns here."
                    )
                }
            } else {
                TrendsCard(insights: insights, goalMinutes: model.settings.dailyGoalMinutes)
                RhythmCard(insights: insights)
                HStack(alignment: .top, spacing: 18) {
                    QualityCard(insights: insights)
                        .frame(maxWidth: .infinity)
                    BreaksCard(insights: insights)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Trends

private struct TrendsCard: View {
    let insights: InsightsSnapshot
    let goalMinutes: Int
    @State private var hoveredMonth: Date?

    var body: some View {
        NonnaCard {
            VStack(alignment: .leading, spacing: 18) {
                InsightCardTitle(eyebrow: "TRENDS", title: "How the work is moving")

                HStack(alignment: .top, spacing: 14) {
                    InsightTile(
                        label: "This week",
                        value: insights.thisWeekSeconds.focusDurationString,
                        detail: weekDetail,
                        tint: weekTint
                    )
                    InsightTile(
                        label: "Average session",
                        value: insights.averageSessionSeconds.focusDurationString,
                        detail: "\(insights.sessionCount) sessions in range"
                    )
                    InsightTile(
                        label: "Per active day",
                        value: insights.averageActiveDaySeconds.focusDurationString,
                        detail: "\(insights.activeDays) of \(insights.dayCount) days active"
                    )
                    InsightTile(
                        label: "Daily goal hit",
                        value: insights.goalHitRate.percentString,
                        detail: "\(insights.goalHitDays) days at \((goalMinutes * 60).focusDurationString) or more"
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    InsightChartLabel(text: "LAST 6 MONTHS")
                    Chart {
                        if let hovered = insights.months.first(where: { $0.month == hoveredMonth }) {
                            RuleMark(x: .value("Month", hovered.month, unit: .month))
                                .foregroundStyle(NonnaTheme.strongLine)
                        }
                        ForEach(insights.months) { item in
                            BarMark(
                                x: .value("Month", item.month, unit: .month),
                                y: .value("Hours", Double(item.seconds) / 3_600)
                            )
                            .foregroundStyle(NonnaTheme.terracotta)
                            .cornerRadius(3)
                            .opacity(hoveredMonth == nil || hoveredMonth == item.month ? 1 : 0.45)
                        }
                    }
                    .chartHover(Date.self) { date in
                        let month = date.flatMap { value in
                            insights.months.first { Calendar.current.isDate($0.month, equalTo: value, toGranularity: .month) }?.month
                        }
                        if hoveredMonth != month { hoveredMonth = month }
                    }
                    .chartHoverTooltip {
                        if let hovered = insights.months.first(where: { $0.month == hoveredMonth }) {
                            ChartTooltip(
                                title: hovered.month.formatted(.dateTime.month(.wide).year()),
                                lines: ["\(hovered.seconds.focusDurationString) focus"]
                            )
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .month)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated))
                                .foregroundStyle(NonnaTheme.secondaryInk)
                        }
                    }
                    .chartYAxis { InsightAxis.hours }
                    .frame(height: 150)
                }
            }
        }
    }

    private var weekDetail: String {
        guard let change = insights.weekChange else {
            return "Last week: \(insights.lastWeekSeconds.focusDurationString)"
        }
        let arrow = change >= 0 ? "▲" : "▼"
        return "\(arrow) \(abs(change).percentString) vs last week to date"
    }

    private var weekTint: Color {
        guard let change = insights.weekChange else { return NonnaTheme.ink }
        return change >= 0 ? NonnaTheme.sage : NonnaTheme.gold
    }
}

// MARK: - Time of day

private struct RhythmCard: View {
    let insights: InsightsSnapshot
    @State private var hoveredHour: String?
    @State private var hoveredWeekday: String?

    var body: some View {
        NonnaCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    InsightCardTitle(eyebrow: "TIME OF DAY", title: "When you focus best")
                    Spacer()
                    Text(peakSummary)
                        .font(.system(size: 11))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }

                HStack(alignment: .top, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        InsightChartLabel(text: "BY HOUR")
                        hourChart
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 10) {
                        InsightChartLabel(text: "BY WEEKDAY")
                        weekdayChart
                    }
                    .frame(width: 300)
                }
            }
        }
    }

    private var hourChart: some View {
        Chart {
            if let hovered = insights.hours.first(where: { $0.hour.hourLabel == hoveredHour }) {
                RuleMark(x: .value("Hour", hovered.hour.hourLabel))
                    .foregroundStyle(NonnaTheme.strongLine)
            }
            ForEach(insights.hours) { item in
                BarMark(
                    x: .value("Hour", item.hour.hourLabel),
                    y: .value("Minutes", Double(item.seconds) / 60)
                )
                .foregroundStyle(item.hour == insights.peakHour ? NonnaTheme.darkTerracotta : NonnaTheme.terracotta.opacity(0.7))
                .cornerRadius(2)
                .opacity(hoveredHour == nil || hoveredHour == item.hour.hourLabel ? 1 : 0.45)
            }
        }
        .chartHover(String.self) { label in
            if hoveredHour != label { hoveredHour = label }
        }
        .chartHoverTooltip {
            if let hovered = insights.hours.first(where: { $0.hour.hourLabel == hoveredHour }) {
                ChartTooltip(title: hovered.hour.hourSpanLabel, lines: hourLines(for: hovered))
            }
        }
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18].map(\.hourLabel)) { _ in
                AxisValueLabel()
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
        }
        .chartYAxis { InsightAxis.minutes }
        .frame(height: 170)
    }

    private var weekdayChart: some View {
        Chart {
            if let hovered = insights.weekdays.first(where: { $0.label == hoveredWeekday }) {
                RuleMark(x: .value("Weekday", hovered.label))
                    .foregroundStyle(NonnaTheme.strongLine)
            }
            ForEach(insights.weekdays) { item in
                BarMark(
                    x: .value("Weekday", item.label),
                    y: .value("Minutes", Double(item.seconds) / 60)
                )
                .foregroundStyle(item.label == insights.peakWeekdayLabel ? NonnaTheme.sage : NonnaTheme.sage.opacity(0.55))
                .cornerRadius(2)
                .opacity(hoveredWeekday == nil || hoveredWeekday == item.label ? 1 : 0.45)
            }
        }
        .chartHover(String.self) { label in
            if hoveredWeekday != label { hoveredWeekday = label }
        }
        .chartHoverTooltip {
            if let hovered = insights.weekdays.first(where: { $0.label == hoveredWeekday }) {
                ChartTooltip(title: hovered.label, lines: weekdayLines(for: hovered))
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
        }
        .chartYAxis { InsightAxis.minutes }
        .frame(height: 170)
    }

    private func hourLines(for item: HourTotal) -> [String] {
        var lines = ["\(item.seconds.focusDurationString) focus", "\(share(of: item.seconds)) of this range"]
        if let rating = item.averageRating {
            lines.append(String(format: "%.1f average rating", rating))
        }
        return lines
    }

    private func weekdayLines(for item: WeekdayTotal) -> [String] {
        ["\(item.seconds.focusDurationString) focus", "\(share(of: item.seconds)) of this range"]
    }

    private func share(of seconds: Int) -> String {
        guard insights.focusSeconds > 0 else { return "0%" }
        return (Double(seconds) / Double(insights.focusSeconds)).percentString
    }

    private var peakSummary: String {
        var parts: [String] = []
        if let hour = insights.peakHour { parts.append("Peak hour \(hour.hourLabel)") }
        if let weekday = insights.peakWeekdayLabel { parts.append("best day \(weekday)") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Focus quality

private struct QualityCard: View {
    let insights: InsightsSnapshot
    @State private var hoveredRatingHour: String?

    private var ratedHours: [HourTotal] { insights.hours.filter { $0.averageRating != nil } }

    var body: some View {
        NonnaCard {
            VStack(alignment: .leading, spacing: 18) {
                InsightCardTitle(eyebrow: "FOCUS QUALITY", title: "How the sessions felt")

                HStack(alignment: .top, spacing: 14) {
                    InsightTile(
                        label: "Average rating",
                        value: insights.averageRating.map { String(format: "%.1f", $0) } ?? "–",
                        detail: insights.ratedCount == 0 ? "No rated sessions" : "\(insights.ratedCount) rated, out of 5"
                    )
                    InsightTile(
                        label: "Completion",
                        value: insights.completionRate?.percentString ?? "–",
                        detail: "Ran the full interval"
                    )
                    InsightTile(
                        label: "Paused",
                        value: insights.averagePausedSeconds.focusDurationString,
                        detail: "Average per session"
                    )
                }

                if insights.taskRatings.isEmpty {
                    Text("Rate a session in the reflection sheet and ratings by task and hour show up here.")
                        .font(.system(size: 11))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 9) {
                        InsightChartLabel(text: "RATING BY TASK")
                        ForEach(insights.taskRatings.prefix(5)) { item in
                            RatingRow(item: item)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        InsightChartLabel(text: "RATING BY START HOUR")
                        Chart {
                            if let hovered = ratedHours.first(where: { $0.hour.hourLabel == hoveredRatingHour }) {
                                RuleMark(x: .value("Hour", hovered.hour.hourLabel))
                                    .foregroundStyle(NonnaTheme.strongLine)
                            }
                            ForEach(ratedHours) { item in
                                BarMark(
                                    x: .value("Hour", item.hour.hourLabel),
                                    y: .value("Rating", item.averageRating ?? 0)
                                )
                                .foregroundStyle(NonnaTheme.gold)
                                .cornerRadius(2)
                                .opacity(hoveredRatingHour == nil || hoveredRatingHour == item.hour.hourLabel ? 1 : 0.45)
                            }
                        }
                        .chartHover(String.self) { label in
                            if hoveredRatingHour != label { hoveredRatingHour = label }
                        }
                        .chartHoverTooltip {
                            if let hovered = ratedHours.first(where: { $0.hour.hourLabel == hoveredRatingHour }) {
                                ChartTooltip(
                                    title: "Started \(hovered.hour.hourSpanLabel)",
                                    lines: [
                                        String(format: "%.1f of 5 average", hovered.averageRating ?? 0),
                                        "\(hovered.seconds.focusDurationString) focus in this hour"
                                    ]
                                )
                            }
                        }
                        .chartYScale(domain: 0...5)
                        .chartXAxis {
                            AxisMarks { _ in
                                AxisValueLabel()
                                    .foregroundStyle(NonnaTheme.secondaryInk)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading, values: [0, 1, 2, 3, 4, 5]) { _ in
                                AxisGridLine().foregroundStyle(NonnaTheme.line.opacity(0.55))
                                AxisValueLabel()
                                    .foregroundStyle(NonnaTheme.secondaryInk)
                            }
                        }
                        .frame(height: 130)
                    }
                }
            }
        }
    }
}

private struct RatingRow: View {
    let item: TaskRating

    var body: some View {
        HStack(spacing: 10) {
            Text(item.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Spacer()
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { index in
                    Circle()
                        .fill(Double(index) + 0.5 <= item.averageRating ? NonnaTheme.terracotta : NonnaTheme.line)
                        .frame(width: 6, height: 6)
                }
            }
            Text(String(format: "%.1f", item.averageRating))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(NonnaTheme.secondaryInk)
                .frame(width: 26, alignment: .trailing)
            Text("\(item.ratedCount)×")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(NonnaTheme.secondaryInk.opacity(0.7))
                .frame(width: 26, alignment: .trailing)
        }
    }
}

// MARK: - Breaks and overtime

private struct OvertimeBar: Identifiable {
    let date: Date
    let kind: String
    let minutes: Double
    var id: String { "\(kind)-\(date.timeIntervalSince1970)" }
}

private struct BreaksCard: View {
    let insights: InsightsSnapshot
    @State private var hoveredOvertime: Date?

    private var bars: [OvertimeBar] {
        insights.overtimeTrend.flatMap { point -> [OvertimeBar] in
            [
                OvertimeBar(date: point.date, kind: "Focus", minutes: Double(point.focusSeconds) / 60),
                OvertimeBar(date: point.date, kind: "Break", minutes: Double(point.breakSeconds) / 60)
            ]
        }
    }

    var body: some View {
        NonnaCard {
            VStack(alignment: .leading, spacing: 18) {
                InsightCardTitle(eyebrow: "BREAKS & OVERTIME", title: "Rest and run-over")

                HStack(alignment: .top, spacing: 14) {
                    InsightTile(
                        label: "Focus to break",
                        value: insights.focusToBreakRatio.map { String(format: "%.1f : 1", $0) } ?? "–",
                        detail: "\(insights.breakSeconds.focusDurationString) rested"
                    )
                    InsightTile(
                        label: "Skipped breaks",
                        value: "\(insights.skippedBreakCount)",
                        detail: skippedDetail
                    )
                }
                HStack(alignment: .top, spacing: 14) {
                    InsightTile(
                        label: "Break overtime",
                        value: insights.averageBreakOvertimeSeconds.focusDurationString,
                        detail: "Average per finished break",
                        tint: NonnaTheme.sage
                    )
                    InsightTile(
                        label: "Focus overtime",
                        value: insights.averageFocusOvertimeSeconds.focusDurationString,
                        detail: "Average per completed session",
                        tint: NonnaTheme.terracotta
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    InsightChartLabel(text: insights.overtimeTrendIsWeekly ? "OVERTIME BY WEEK" : "OVERTIME BY DAY")
                    if bars.isEmpty {
                        Text("No overtime in this range.")
                            .font(.system(size: 11))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                    } else {
                        overtimeChart
                    }
                }
            }
        }
    }

    private var overtimeChart: some View {
        let unit: Calendar.Component = insights.overtimeTrendIsWeekly ? .weekOfYear : .day
        return Chart {
            if let hovered = insights.overtimeTrend.first(where: { $0.date == hoveredOvertime }) {
                RuleMark(x: .value("Date", hovered.date, unit: unit))
                    .foregroundStyle(NonnaTheme.strongLine)
            }
            ForEach(bars) { bar in
                BarMark(
                    x: .value("Date", bar.date, unit: unit),
                    y: .value("Minutes", bar.minutes)
                )
                .foregroundStyle(by: .value("Type", bar.kind))
                .cornerRadius(2)
                .opacity(hoveredOvertime == nil || hoveredOvertime == bar.date ? 1 : 0.45)
            }
        }
        .chartHover(Date.self) { date in
            let match = date.flatMap { value in
                insights.overtimeTrend.first { Calendar.current.isDate($0.date, equalTo: value, toGranularity: unit) }?.date
            }
            if hoveredOvertime != match { hoveredOvertime = match }
        }
        .chartHoverTooltip {
            if let hovered = insights.overtimeTrend.first(where: { $0.date == hoveredOvertime }) {
                ChartTooltip(
                    title: (insights.overtimeTrendIsWeekly ? "Week of " : "")
                        + hovered.date.formatted(.dateTime.month(.abbreviated).day()),
                    lines: [
                        "\(hovered.focusSeconds.focusDurationString) focus overtime",
                        "\(hovered.breakSeconds.focusDurationString) break overtime"
                    ]
                )
            }
        }
        .chartForegroundStyleScale([
            "Focus": NonnaTheme.terracotta,
            "Break": NonnaTheme.sage
        ])
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
        }
        .chartYAxis { InsightAxis.minutes }
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 130)
    }

    private var skippedDetail: String {
        guard insights.breakCount > 0 else { return "No breaks recorded" }
        let rate = Double(insights.skippedBreakCount) / Double(insights.breakCount)
        return "\(rate.percentString) of \(insights.breakCount) breaks cut short"
    }
}

// MARK: - Shared pieces

private struct InsightCardTitle: View {
    let eyebrow: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.7)
                .foregroundStyle(NonnaTheme.secondaryInk)
            Text(title)
                .font(.system(size: 18, weight: .semibold))
        }
    }
}

private struct InsightChartLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .tracking(1.4)
            .foregroundStyle(NonnaTheme.secondaryInk)
    }
}

private struct InsightTile: View {
    let label: String
    let value: String
    let detail: String
    var tint: Color = NonnaTheme.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(NonnaTheme.secondaryInk)
            Text(value)
                .font(.system(size: 22, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(NonnaTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NonnaTheme.raisedPaper.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(NonnaTheme.line, lineWidth: 0.8)
        }
    }
}

@MainActor
private enum InsightAxis {
    static var minutes: some AxisContent {
        AxisMarks(position: .leading) { value in
            AxisGridLine().foregroundStyle(NonnaTheme.line.opacity(0.55))
            AxisValueLabel {
                if let minutes = value.as(Double.self) {
                    Text(minutes >= 60 ? String(format: "%.0fh", minutes / 60) : "\(Int(minutes))m")
                }
            }
            .foregroundStyle(NonnaTheme.secondaryInk)
        }
    }

    static var hours: some AxisContent {
        AxisMarks(position: .leading) { value in
            AxisGridLine().foregroundStyle(NonnaTheme.line.opacity(0.55))
            AxisValueLabel {
                if let hours = value.as(Double.self) {
                    Text(hours < 1 && hours > 0 ? String(format: "%.1fh", hours) : "\(Int(hours))h")
                }
            }
            .foregroundStyle(NonnaTheme.secondaryInk)
        }
    }
}

private extension Int {
    /// 0 → "12a", 9 → "9a", 12 → "12p", 18 → "6p"
    var hourLabel: String {
        let hour = ((self % 24) + 24) % 24
        let suffix = hour < 12 ? "a" : "p"
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return "\(twelve)\(suffix)"
    }

    /// 9 → "9a–10a"
    var hourSpanLabel: String { "\(hourLabel)–\((self + 1).hourLabel)" }
}

private extension Double {
    var percentString: String { "\(Int((self * 100).rounded()))%" }
}
