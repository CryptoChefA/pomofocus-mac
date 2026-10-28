import AppKit
import SwiftUI

// MARK: - Plan section

struct FocusPlanView: View {
    @Environment(AppModel.self) private var model
    @State private var showsQuestionnaire = false
    @State private var showsSources = false
    @State private var confirmsRemoval = false
    @AppStorage(SourceChip.visibilityKey) private var showsCitations = false
    @Environment(\.compactLayout) private var compact
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onStartBlock: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let plan = model.focusPlan {
                    if let change = model.planChange {
                        PlanChangeBanner(change: change) { model.planChange = nil }
                    }
                    dashboard(plan)
                } else {
                    PlanIntro(onBegin: { showsQuestionnaire = true }, onSources: { showsSources = true })
                }
            }
            .padding(36)
            .frame(maxWidth: 1080, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showsQuestionnaire) {
            PlanQuestionnaire(initial: model.focusPlan?.answers ?? FocusPlanAnswers()) { answers in
                model.startPlan(with: answers)
                showsQuestionnaire = false
            } onCancel: {
                showsQuestionnaire = false
            }
            .environment(model)
        }
        .sheet(isPresented: $showsSources) {
            SourcesSheet { showsSources = false }
        }
        .confirmationDialog("Remove your focus plan?", isPresented: $confirmsRemoval) {
            Button("Remove plan", role: .destructive) { model.removePlan() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your timer keeps its current lengths and your history stays. You can build a new plan any time.")
        }
    }

    // MARK: Dashboard

    /// What today asks of you, in a sentence, adapting to how the last few days went.
    private func todayMessage(plan: FocusPlan, done: Int, target: Int, reentry: FocusPlan.Reentry?, missedYesterday: Bool) -> String {
        if done >= target {
            return done > target ? "Past today's goal. Anything more is a bonus." : "Done for today. Go enjoy your reward."
        }
        if let reentry {
            return "\(reentry.daysAway) days away, so the next \(reentry.blocksLeft == 1 ? "block is" : "\(reentry.blocksLeft) blocks are") a \(reentry.warmupMinutes)-minute warm-up. Your \(plan.level.focusMinutes)-minute level is still yours."
        }
        if missedYesterday {
            return "Yesterday was a day off, and that's fine. One block today keeps the habit going."
        }
        return "Each block is \(plan.level.focusMinutes) minutes. Starting is the hard part."
    }

    @ViewBuilder
    private func dashboard(_ plan: FocusPlan) -> some View {
        let progress = plan.progress(sessions: model.sessions)
        let today = plan.blocksToday(sessions: model.sessions)
        let target = plan.todayTarget(sessions: model.sessions)
        let reentry = plan.reentry(sessions: model.sessions)
        let missedYesterday = plan.missedYesterday(sessions: model.sessions)
        // Warm-up blocks count toward today too.
        let doneToday = max(today, model.sessions.filter {
            Calendar.current.isDateInToday($0.startedAt) && $0.outcome != .abandoned && $0.focusedSeconds >= 10 * 60
        }.count)
        let phase = plan.phase()
        let weeks = FocusMetrics.weekOverWeek(sessions: model.sessions)

        HStack(alignment: .bottom) {
            SectionHeading(
                title: "Your focus rebuild",
                subtitle: "Level \(plan.levelIndex + 1) of \(plan.levels.count), \(plan.level.focusMinutes) min focus, \(plan.level.breakMinutes) min break, day \(plan.daysSinceStart() + 1)"
            )
            Spacer()
            if showsCitations {
                Button {
                    showsSources = true
                } label: {
                    Label("Master list", systemImage: "list.number")
                }
                .buttonStyle(NonnaButtonStyle(prominent: false))
                .help("All \(FocusScience.all.count) studies, with findings and links")
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            Button {
                withAnimation(reduceMotion ? nil : NonnaMotion.quick) { showsCitations.toggle() }
            } label: {
                Label(showsCitations ? "Hide sources" : "Sources", systemImage: showsCitations ? "books.vertical.fill" : "books.vertical")
            }
            .buttonStyle(NonnaButtonStyle(prominent: false))
            .help(showsCitations ? "Hide the citation numbers" : "Show which study backs each piece of advice")
            Menu {
                Button("Retake the questions…") { showsQuestionnaire = true }
                Divider()
                Button("Remove plan…", role: .destructive) { confirmsRemoval = true }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 38, height: 40)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Button {
                onStartBlock()
            } label: {
                Label(model.status == .idle ? "Start a block" : "Go to timer", systemImage: model.status == .idle ? "play.fill" : "timer")
            }
            .buttonStyle(NonnaButtonStyle())
        }

        PhaseStrip(current: phase)

        AdaptiveColumns(compact) {
            NonnaCard {
                HStack(spacing: 26) {
                    LevelRing(fraction: plan.isFinalLevel ? 1 : progress.fraction, minutes: plan.level.focusMinutes)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(plan.isFinalLevel ? "Target reached" : "Next level")
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundStyle(NonnaTheme.terracotta)
                            SourceChip(guidance: FocusPlan.ladderGuidance)
                        }
                        if plan.isFinalLevel {
                            Text("\(plan.level.focusMinutes)-minute blocks are yours.")
                                .font(.system(size: 20, weight: .semibold))
                            Text("Keep the rhythm. Consistency now protects what you rebuilt.")
                                .font(.system(size: 12))
                                .foregroundStyle(NonnaTheme.secondaryInk)
                        } else {
                            let next = plan.levels[plan.levelIndex + 1]
                            Text("\(next.focusMinutes) min focus, \(next.breakMinutes) min break")
                                .font(.system(size: 20, weight: .semibold))
                            requirement("Full \(plan.level.focusMinutes)-minute blocks", value: "\(min(progress.fullBlocks, FocusPlan.blocksPerLevel)) of \(FocusPlan.blocksPerLevel)",
                                        met: progress.fullBlocks >= FocusPlan.blocksPerLevel)
                            requirement("On different days", value: "\(min(progress.days, FocusPlan.daysPerLevel)) of \(FocusPlan.daysPerLevel)",
                                        met: progress.days >= FocusPlan.daysPerLevel)
                            requirement("Blocks finished", value: progress.attempts == 0 ? "–" : "\(Int((progress.completionRate * 100).rounded()))%, need \(Int(FocusPlan.levelUpCompletion * 100))%",
                                        met: progress.attempts > 0 && progress.completionRate >= FocusPlan.levelUpCompletion)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            NonnaCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(reentry != nil ? "Welcome back" : "Today")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NonnaTheme.terracotta)
                    Text("\(min(doneToday, target)) of \(target) \(target == 1 ? "block" : "blocks")")
                        .font(.system(size: 20, weight: .semibold))
                        .monospacedDigit()
                    HStack(spacing: 6) {
                        ForEach(0..<target, id: \.self) { index in
                            Capsule()
                                .fill(index < doneToday ? NonnaTheme.terracotta : NonnaTheme.strongLine)
                                .frame(width: index < doneToday ? 22 : 14, height: 5)
                        }
                    }
                    Text(todayMessage(plan: plan, done: doneToday, target: target, reentry: reentry, missedYesterday: missedYesterday))
                        .font(.system(size: 12))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: compact ? .infinity : 260, alignment: .leading)
                .frame(width: compact ? nil : 260)
            }
        }

        MetricsCard(current: weeks.current, previous: weeks.previous)

        NonnaCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    Text("The ladder")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(NonnaTheme.terracotta)
                    SourceChip(guidance: FocusPlan.breakGuidance)
                    Spacer()
                    if !plan.isFinalLevel {
                        Text("About \(plan.estimatedDaysToTarget) days to \(plan.levels.last?.focusMinutes ?? 45)-minute blocks at this pace")
                            .font(.system(size: 11))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                    }
                }
                PlanLadder(plan: plan)
                    .frame(height: 150)
            }
        }

        AdaptiveColumns(compact) {
            CollapsibleCard(title: "House rules", icon: "checkmark.seal", storageKey: "plan.rulesOpen") {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(plan.rules.enumerated()), id: \.offset) { _, rule in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(rule.title).font(.system(size: 13, weight: .semibold))
                                SourceChip(guidance: rule)
                            }
                            Text(rule.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(NonnaTheme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 18) {
                CollapsibleCard(title: "Break menu", icon: "cup.and.saucer", storageKey: "plan.breaksOpen") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Breaks that let attention recover instead of spending it.")
                            .font(.system(size: 12))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                        ForEach(Array(plan.breakMenu.enumerated()), id: \.offset) { _, idea in
                            HStack(alignment: .firstTextBaseline, spacing: 9) {
                                Circle().fill(NonnaTheme.sage).frame(width: 5, height: 5)
                                Text(idea.title).font(.system(size: 12))
                                SourceChip(guidance: idea)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                NonnaCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Label("Your reward", systemImage: "gift")
                                .font(.system(size: 15, weight: .semibold))
                            SourceChip(guidance: plan.reward)
                        }
                        RewardField(current: plan.answers.reward) { model.setPlanReward($0) }
                        Text(plan.reward.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        Button {
            showsSources = true
        } label: {
            Text("Built on \(FocusScience.all.count) peer-reviewed studies. Read the sources, and what the science doesn't say →")
                .font(.system(size: 11))
                .foregroundStyle(NonnaTheme.secondaryInk)
                .underline()
        }
        .buttonStyle(.plain)
    }

    private func requirement(_ title: String, value: String, met: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(met ? NonnaTheme.sage : NonnaTheme.secondaryInk)
            Text(title).font(.system(size: 12))
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(NonnaTheme.secondaryInk)
        }
        .frame(maxWidth: 320)
    }
}

// MARK: - Phases and metrics

private struct PhaseStrip: View {
    let current: FocusPlan.PhaseInfo

    private let order: [(FocusPlan.Phase, String)] = [(.reset, "Reset"), (.build, "Build"), (.extend, "Extend"), (.sustain, "Sustain")]

    var body: some View {
        NonnaCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    ForEach(Array(order.enumerated()), id: \.offset) { index, item in
                        let reached = (order.firstIndex { $0.0 == current.phase } ?? 0) >= index
                        let isCurrent = item.0 == current.phase
                        HStack(spacing: 6) {
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .bold).monospacedDigit())
                                .frame(width: 20, height: 20)
                                .foregroundStyle(isCurrent ? NonnaTheme.onAccent : reached ? NonnaTheme.terracotta : NonnaTheme.secondaryInk)
                                .background(isCurrent ? NonnaTheme.terracotta : NonnaTheme.sunken, in: Circle())
                                .overlay { Circle().stroke(reached ? NonnaTheme.terracotta.opacity(0.6) : NonnaTheme.line, lineWidth: 0.8) }
                            Text(item.1)
                                .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                                .foregroundStyle(isCurrent ? NonnaTheme.ink : NonnaTheme.secondaryInk)
                        }
                        if index < order.count - 1 {
                            Rectangle()
                                .fill(reached && !isCurrent ? NonnaTheme.terracotta.opacity(0.6) : NonnaTheme.line)
                                .frame(height: 1)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(current.focus)
                        .font(.system(size: 13))
                        .fixedSize(horizontal: false, vertical: true)
                    SourceChip(ids: current.sources)
                }
            }
        }
    }
}

private struct MetricsCard: View {
    let current: FocusMetrics
    let previous: FocusMetrics

    var body: some View {
        NonnaCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Text("Your focus, measured")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(NonnaTheme.terracotta)
                    SourceChip(ids: [.progressMonitoring])
                    Spacer()
                    Text("Last 7 days vs the 7 before")
                        .font(.system(size: 11))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
                HStack(alignment: .top, spacing: 0) {
                    metric("Blocks finished", percent(current.completionRate), delta(current.completionRate, previous.completionRate, scale: 100, unit: " pts", higherIsBetter: true),
                           "Share of blocks you finished at full length.", [.selfEfficacy, .goalSetting])
                    divider
                    metric("Longest unbroken", minutes(current.unbrokenMinutes), delta(current.unbrokenMinutes, previous.unbrokenMinutes, scale: 1, unit: " min", higherIsBetter: true),
                           "Median longest stretch per block without a pause. This is the attention span you're rebuilding.", [.vigilanceWork, .interruptionCost])
                    divider
                    metric("Pauses per block", decimal(current.pausesPerBlock), delta(current.pausesPerBlock, previous.pausesPerBlock, scale: 1, unit: "", higherIsBetter: false),
                           "Fewer pauses means fewer interruptions and less attention residue.", [.attentionResidue, .interruptionCost])
                    divider
                    metric("Start time spread", current.startSpreadMinutes.map { "±\(Int($0.rounded())) min" } ?? "–",
                           delta(current.startSpreadMinutes, previous.startSpreadMinutes, scale: 1, unit: " min", higherIsBetter: false),
                           "How close to the same time your first block starts. A steadier start builds the habit.", [.implementationIntentions, .habitFormation])
                    divider
                    metric("Active days", "\(current.activeDays) of 7", delta(Double(current.activeDays), Double(previous.activeDays), scale: 1, unit: "", higherIsBetter: true),
                           "Days with at least one block.", [.habitFormation])
                }
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(NonnaTheme.line).frame(width: 1, height: 70)
    }

    private func metric(_ label: String, _ value: String, _ change: (String, Color)?, _ explanation: String, _ sources: [Citation.ID]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 8.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .lineLimit(1)
                SourceChip(guidance: PlanGuidance(title: label, detail: explanation, sources: sources))
            }
            Text(value)
                .font(.system(size: 22, weight: .medium))
                .monospacedDigit()
            if let change {
                Text(change.0)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(change.1)
            } else {
                Text("no data last week")
                    .font(.system(size: 10))
                    .foregroundStyle(NonnaTheme.secondaryInk.opacity(0.8))
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func percent(_ value: Double?) -> String { value.map { "\(Int(($0 * 100).rounded()))%" } ?? "–" }
    private func minutes(_ value: Double?) -> String { value.map { "\(Int($0.rounded())) min" } ?? "–" }
    private func decimal(_ value: Double?) -> String { value.map { String(format: "%.1f", $0) } ?? "–" }

    private func delta(_ now: Double?, _ before: Double?, scale: Double, unit: String, higherIsBetter: Bool) -> (String, Color)? {
        guard let now, let before else { return nil }
        let change = (now - before) * scale
        if abs(change) < 0.05 { return ("→ steady", NonnaTheme.secondaryInk) }
        let better = higherIsBetter ? change > 0 : change < 0
        let text = (change > 0 ? "↑ " : "↓ ") + (abs(change) >= 10 || unit == " pts" ? "\(Int(abs(change).rounded()))" : String(format: "%.1f", abs(change))) + unit
        return (text, better ? NonnaTheme.sage : NonnaTheme.alert.opacity(0.85))
    }
}

// MARK: - Sources

/// A small citation marker, like a footnote number. Click it to see the study.
struct SourceChip: View {
    static let visibilityKey = "pomofocus.showCitations"

    let ids: [Citation.ID]
    var title: String?
    var detail: String?
    @State private var showing = false
    @AppStorage(SourceChip.visibilityKey) private var visible = false

    init(ids: [Citation.ID]) { self.ids = ids }
    init(guidance: PlanGuidance) {
        ids = guidance.sources
        title = guidance.title
        detail = guidance.detail
    }

    private var numbers: String {
        ids.compactMap { id in FocusScience.all.firstIndex { $0.id == id }.map { String($0 + 1) } }.joined(separator: ",")
    }

    /// What hovering a number shows: each study's short label and finding.
    private var hoverText: String {
        FocusScience.citations(ids).map { citation in
            let number = (FocusScience.all.firstIndex { $0.id == citation.id } ?? 0) + 1
            return "\(number). \(citation.shortLabel): \(citation.finding)"
        }.joined(separator: "\n\n") + "\n\nClick for the full reference."
    }

    var body: some View {
        if visible { chip.transition(.opacity.combined(with: .scale(scale: 0.8))) }
    }

    private var chip: some View {
        Button {
            showing.toggle()
        } label: {
            Text(numbers)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(NonnaTheme.terracotta)
                .padding(.horizontal, 5)
                .frame(height: 16)
                .background(NonnaTheme.terracotta.opacity(0.1), in: Capsule())
                .overlay { Capsule().stroke(NonnaTheme.terracotta.opacity(0.35), lineWidth: 0.6) }
        }
        .buttonStyle(.plain)
        .help(hoverText)
        .accessibilityLabel("Sources \(numbers)")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                if let title {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.system(size: 13, weight: .semibold))
                        if let detail {
                            Text(detail)
                                .font(.system(size: 11))
                                .foregroundStyle(NonnaTheme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Divider().overlay(NonnaTheme.line)
                }
                ForEach(FocusScience.citations(ids)) { citation in
                    CitationRow(citation: citation, compact: true)
                }
            }
            .padding(18)
            .frame(width: 380)
            .background(NonnaTheme.cream)
            .foregroundStyle(NonnaTheme.ink)
            .environment(\.colorScheme, NonnaTheme.colorScheme)
        }
    }
}

private struct CitationRow: View {
    let citation: Citation
    var compact = false

    private var number: Int { (FocusScience.all.firstIndex { $0.id == citation.id } ?? 0) + 1 }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(NonnaTheme.terracotta)
                .frame(width: 20, alignment: .trailing)
            VStack(alignment: .leading, spacing: 5) {
                Text(citation.finding)
                    .font(.system(size: compact ? 12 : 13))
                    .fixedSize(horizontal: false, vertical: true)
                Text(citation.reference)
                    .font(.system(size: 10.5, design: .serif))
                    .italic()
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if let url = citation.scholarURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Find the paper", systemImage: "arrow.up.right.square")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(NonnaTheme.terracotta)
                    .help("Opens a Google Scholar search for this paper in your browser")
                }
            }
        }
    }
}

struct SourcesSheet: View {
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("The science")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(NonnaTheme.terracotta)
                    Text("Sources")
                        .font(.system(size: 30, weight: .regular, design: .serif))
                    Text("Every rule, break idea, phase and measurement in your plan traces back to these studies. The numbers next to each piece of advice point here.")
                        .font(.system(size: 12))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Done", action: onDone)
                    .buttonStyle(NonnaButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(30)
            Divider().overlay(NonnaTheme.line)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(FocusScience.all) { citation in
                        CitationRow(citation: citation)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Label("What the science doesn't say", systemImage: "exclamationmark.bubble")
                            .font(.system(size: 15, weight: .semibold))
                        ForEach(FocusScience.limits, id: \.self) { limit in
                            HStack(alignment: .firstTextBaseline, spacing: 9) {
                                Circle().fill(NonnaTheme.secondaryInk).frame(width: 4, height: 4)
                                Text(limit)
                                    .font(.system(size: 12))
                                    .foregroundStyle(NonnaTheme.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(18)
                    .background(NonnaTheme.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }
                }
                .padding(30)
            }
        }
        .frame(width: 720, height: 680)
        .background(NonnaTheme.cream)
        .foregroundStyle(NonnaTheme.ink)
        .preferredColorScheme(NonnaTheme.colorScheme)
    }
}

// MARK: - Pieces

private struct LevelRing: View {
    let fraction: Double
    let minutes: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack {
            Circle().stroke(NonnaTheme.line, lineWidth: 6)
            Circle()
                .trim(from: 0, to: shown ? max(0.001, fraction) : 0.001)
                .stroke(NonnaTheme.terracotta, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: NonnaTheme.terracotta.opacity(0.4), radius: 6)
            VStack(spacing: 0) {
                Text("\(minutes)")
                    .font(.system(size: 34, weight: .light))
                    .monospacedDigit()
                Text("Min")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
        }
        .frame(width: 112, height: 112)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(duration: 1.1, bounce: 0.15).delay(0.15)) { shown = true }
        }
    }
}

private struct PlanLadder: View {
    let plan: FocusPlan
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        let maxMinutes = Double(plan.levels.last?.focusMinutes ?? 45)
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(plan.levels.enumerated()), id: \.offset) { index, level in
                let done = index < plan.levelIndex
                let current = index == plan.levelIndex
                VStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(done ? AnyShapeStyle(NonnaTheme.terracotta.opacity(0.85))
                              : current ? AnyShapeStyle(LinearGradient(colors: [NonnaTheme.darkTerracotta, NonnaTheme.terracotta], startPoint: .top, endPoint: .bottom))
                              : AnyShapeStyle(NonnaTheme.raisedPaper))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(current ? NonnaTheme.darkTerracotta : NonnaTheme.line, lineWidth: current ? 1.2 : 0.8)
                        }
                        .shadow(color: current ? NonnaTheme.terracotta.opacity(0.5) : .clear, radius: 10)
                        .phaseAnimator(current && !reduceMotion ? [false, true] : [false]) { bar, glowing in
                            // A slow breath on the rung you're on: you are here.
                            bar
                                .shadow(color: NonnaTheme.terracotta.opacity(glowing ? 0.55 : 0), radius: glowing ? 18 : 6)
                                .brightness(glowing ? 0.06 : 0)
                        } animation: { _ in .easeInOut(duration: 1.6) }
                        .frame(height: shown ? max(14, 112 * Double(level.focusMinutes) / maxMinutes) : 8)
                        .animation(reduceMotion ? nil : .spring(duration: 0.8, bounce: 0.2).delay(0.1 + Double(index) * 0.06), value: shown)
                    Text("\(level.focusMinutes)")
                        .font(.system(size: 11, weight: current ? .bold : .medium).monospacedDigit())
                        .foregroundStyle(current ? NonnaTheme.ink : NonnaTheme.secondaryInk)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { shown = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ladder from \(plan.levels.first?.focusMinutes ?? 0) to \(plan.levels.last?.focusMinutes ?? 0) minutes, currently at \(plan.level.focusMinutes)")
    }
}

struct PlanChangeBanner: View {
    let change: AppModel.PlanChange
    let onDismiss: () -> Void

    var body: some View {
        let up = change.adjustment == .levelUp
        HStack(spacing: 14) {
            Image(systemName: up ? (change.isFinal ? "trophy.fill" : "arrow.up.circle.fill") : "arrow.uturn.backward.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(up ? NonnaTheme.terracotta : NonnaTheme.sage)
            VStack(alignment: .leading, spacing: 2) {
                Text(up ? (change.isFinal ? "Target reached" : "Level up") : "Consolidating")
                    .font(.system(size: 14, weight: .semibold))
                Text(up
                     ? (change.isFinal ? "\(change.level.focusMinutes)-minute blocks are yours now."
                        : "You've earned \(change.level.focusMinutes)-minute blocks with \(change.level.breakMinutes)-minute breaks. Your next block uses them.")
                     : "The last level was a stretch. A few wins at \(change.level.focusMinutes)-minute blocks rebuild confidence, then you'll climb again.")
                    .font(.system(size: 12))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            SourceChip(ids: up ? [.proximalGoals] : [.selfEfficacy])
            Spacer()
            Button("Got it", action: onDismiss)
                .buttonStyle(NonnaButtonStyle(prominent: false))
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill((up ? NonnaTheme.terracotta : NonnaTheme.sage).opacity(0.1))
                .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke((up ? NonnaTheme.terracotta : NonnaTheme.sage).opacity(0.45), lineWidth: 0.8) }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

private struct PlanIntro: View {
    let onBegin: () -> Void
    let onSources: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Focus rebuild plan")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(NonnaTheme.terracotta)
                Text("Rebuild your focus,\none block at a time.")
                    .font(.system(size: 46, weight: .regular, design: .serif))
                    .tracking(-0.8)
                Text("Answer eight quick questions. Pomofocus builds a research-based plan that starts where your attention is today, measures how it responds, and climbs, five minutes at a time, to 45-minute blocks with 15-minute breaks, or whatever you're aiming for.")
                    .font(.system(size: 15))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .frame(maxWidth: 640, alignment: .leading)
            }

            HStack(alignment: .top, spacing: 16) {
                principle("1", "Start where you are", "The plan begins just under your real limit. Early wins build the belief that drives the next block.", [.selfEfficacy, .proximalGoals])
                principle("2", "Earn every minute", "Five-minute steps, unlocked by your own numbers: full blocks, on different days, finished at a good rate.", [.goalSetting, .progressMonitoring])
                principle("3", "Rest that restores", "Breaks away from screens and feeds, outside or moving, so attention recovers instead of being spent.", [.natureAttention, .shortFormVideo])
            }

            HStack(spacing: 14) {
                Button(action: onBegin) {
                    Label("Build my plan", systemImage: "sparkles")
                }
                .buttonStyle(NonnaButtonStyle())
                .keyboardShortcut(.defaultAction)
                Button(action: onSources) {
                    Label("Read the science", systemImage: "books.vertical")
                }
                .buttonStyle(NonnaButtonStyle(prominent: false))
            }
        }
        .padding(.top, 30)
    }

    private func principle(_ number: String, _ title: String, _ detail: String, _ sources: [Citation.ID]) -> some View {
        NonnaCard(padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(number)
                        .font(.system(size: 30, weight: .light, design: .serif))
                        .foregroundStyle(NonnaTheme.terracotta)
                    Spacer()
                    SourceChip(guidance: PlanGuidance(title: title, detail: detail, sources: sources))
                }
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Questionnaire

private struct PlanQuestionnaire: View {
    @State private var answers: FocusPlanAnswers
    @State private var step = 0
    @State private var forward = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onFinish: (FocusPlanAnswers) -> Void
    let onCancel: () -> Void

    init(initial: FocusPlanAnswers, onFinish: @escaping (FocusPlanAnswers) -> Void, onCancel: @escaping () -> Void) {
        _answers = State(initialValue: initial)
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    private let questionCount = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(step < questionCount ? "Question \(step + 1) of \(questionCount)" : "Your plan")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(NonnaTheme.terracotta)
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 5) {
                ForEach(0...questionCount, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? NonnaTheme.terracotta : NonnaTheme.line)
                        .frame(height: 3)
                }
            }
            .padding(.top, 12)
            .animation(reduceMotion ? nil : NonnaMotion.selection, value: step)

            ZStack(alignment: .topLeading) {
                page
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(x: forward ? 40 : -40)),
                        removal: .opacity.combined(with: .offset(x: forward ? -40 : 40))
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, 30)
            .clipped()

            HStack {
                if step > 0 {
                    Button {
                        go(-1)
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(NonnaButtonStyle(prominent: false))
                }
                Spacer()
                if step < questionCount {
                    Button {
                        go(1)
                    } label: {
                        Label(step == questionCount - 1 ? "See my plan" : "Next", systemImage: "chevron.right")
                    }
                    .buttonStyle(NonnaButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(step == 2 && answers.distractions.isEmpty)
                } else {
                    Button {
                        onFinish(answers)
                    } label: {
                        Label("Begin my plan", systemImage: "play.fill")
                    }
                    .buttonStyle(NonnaButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(34)
        .frame(width: 680, height: 640)
        .background(NonnaTheme.cream)
        .foregroundStyle(NonnaTheme.ink)
        .preferredColorScheme(NonnaTheme.colorScheme)
    }

    private func go(_ delta: Int) {
        forward = delta > 0
        withAnimation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.1)) {
            step = min(questionCount, max(0, step + delta))
        }
    }

    @ViewBuilder
    private var page: some View {
        switch step {
        case 0:
            question("What are you rebuilding focus for?", "Pick the work you most want to get back to.") {
                choices(FocusPlanAnswers.Purpose.allCases, selected: [answers.purpose]) { answers.purpose = $0 } label: {
                    switch $0 {
                    case .study: ("Studying", "Classes, exams, problem sets", "book.closed")
                    case .work: ("Deep work", "Projects, code, writing", "laptopcomputer")
                    case .creative: ("Creative work", "Design, music, art, video", "paintpalette")
                    case .reading: ("Reading", "Books and long articles", "text.book.closed")
                    }
                }
            }
        case 1:
            question("Be honest: how long can you focus right now?", "Before your hand drifts to your phone or another tab. There's no wrong answer; the plan starts here.") {
                choices(FocusPlanAnswers.Capacity.allCases, selected: [answers.capacity]) { answers.capacity = $0 } label: {
                    switch $0 {
                    case .underTen: ("Under 10 minutes", "It's been rough lately", "tortoise")
                    case .tenToTwenty: ("10 to 20 minutes", "I get going, then drift", "figure.walk")
                    case .twentyToThirty: ("20 to 30 minutes", "Decent, but not deep", "figure.run")
                    case .overThirty: ("Over 30 minutes", "I just want it steadier", "hare")
                    }
                }
            }
        case 2:
            question("What pulls you away most?", "Choose everything that applies. Your house rules come from these.") {
                choices(FocusPlanAnswers.Distraction.allCases, selected: answers.distractions, multiple: true) { item in
                    if let index = answers.distractions.firstIndex(of: item) { answers.distractions.remove(at: index) }
                    else { answers.distractions.append(item) }
                } label: {
                    switch $0 {
                    case .phone: ("My phone", "Just checking, constantly", "iphone")
                    case .socialMedia: ("Social media", "Feeds and stories", "bubble.left.and.bubble.right")
                    case .video: ("Videos", "YouTube, shorts, streams", "play.rectangle")
                    case .games: ("Games", "One more round", "gamecontroller")
                    case .messages: ("Messages", "Chats and notifications", "bell.badge")
                    case .restlessThoughts: ("My own thoughts", "Restless, wandering mind", "cloud")
                    }
                }
            }
        case 3:
            question("What do your breaks usually look like?", "Breaks decide whether the next block feels possible.") {
                choices(FocusPlanAnswers.BreakHabit.allCases, selected: [answers.breakHabit]) { answers.breakHabit = $0 } label: {
                    switch $0 {
                    case .scroll: ("Scrolling my phone", "Then I lose track of time", "iphone.gen3")
                    case .snack: ("Snacks", "Something to eat or drink", "fork.knife")
                    case .move: ("Moving around", "Walking, stretching", "figure.walk")
                    case .mix: ("A bit of everything", "It depends on the day", "shuffle")
                    }
                }
            }
        case 4:
            question("When is your energy best?", "Your first block of the day should land here.") {
                choices(FocusPlanAnswers.Energy.allCases, selected: [answers.energy]) { answers.energy = $0 } label: {
                    switch $0 {
                    case .morning: ("Morning", "Before noon", "sunrise")
                    case .afternoon: ("Afternoon", "Noon to five", "sun.max")
                    case .evening: ("Evening", "Five to ten", "sunset")
                    case .lateNight: ("Late night", "After ten", "moon.stars")
                    }
                }
            }
        case 5:
            question("How much time can you give this on a normal day?", "Realistic beats ambitious. You can always do more.") {
                choices([30, 60, 120, 180], selected: [answers.dailyMinutes]) { answers.dailyMinutes = $0 } label: {
                    switch $0 {
                    case 30: ("30 minutes", "A small, daily start", "1.circle")
                    case 60: ("1 hour", "A solid habit", "2.circle")
                    case 120: ("2 hours", "Serious progress", "3.circle")
                    default: ("3 hours or more", "Exam season mode", "4.circle")
                    }
                }
            }
        case 6:
            question("How long do you want your blocks to be?", "Your target. The plan climbs there five minutes at a time.") {
                choices([25, 45, 60, 90], selected: [answers.targetMinutes]) { answers.targetMinutes = $0 } label: {
                    switch $0 {
                    case 25: ("25 minutes", "Classic Pomodoro, 8-minute breaks", "timer")
                    case 45: ("45 minutes", "With 15-minute breaks. Recommended", "star")
                    case 60: ("60 minutes", "With 20-minute breaks", "hourglass")
                    default: ("90 minutes", "Deep sessions, 30-minute breaks", "mountain.2")
                    }
                }
            }
        case 7:
            question("What will you reward yourself with?", "Something you'll look forward to, saved for after the day's last block. Leave it blank if you'd rather not say.") {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("e.g. An episode of my show, a game, a walk with friends", text: $answers.reward)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                        .background(NonnaTheme.raisedPaper)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NonnaTheme.line) }
                    HStack(spacing: 8) {
                        ForEach(["A favourite show", "Gaming", "A treat", "Time with friends"], id: \.self) { idea in
                            Button(idea) { answers.reward = idea }
                                .buttonStyle(.plain)
                                .font(.system(size: 12))
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .background(NonnaTheme.raisedPaper, in: Capsule())
                                .overlay { Capsule().stroke(NonnaTheme.line) }
                        }
                    }
                }
            }
        default:
            PlanPreview(plan: FocusPlan.build(from: answers))
        }
    }

    private func question<Content: View>(_ title: String, _ subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 30, weight: .regular, design: .serif))
                    .tracking(-0.4)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
    }

    private func choices<Item: Hashable>(
        _ items: [Item],
        selected: [Item],
        multiple: Bool = false,
        onPick: @escaping (Item) -> Void,
        label: @escaping (Item) -> (String, String, String)
    ) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(items, id: \.self) { item in
                let (title, detail, icon) = label(item)
                ChoiceCard(title: title, detail: detail, icon: icon, isSelected: selected.contains(item), multiple: multiple) {
                    withAnimation(reduceMotion ? nil : NonnaMotion.quick) { onPick(item) }
                }
            }
        }
    }
}

private struct ChoiceCard: View {
    let title: String
    let detail: String
    let icon: String
    let isSelected: Bool
    let multiple: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .frame(width: 38, height: 38)
                    .foregroundStyle(isSelected ? NonnaTheme.onAccent : NonnaTheme.terracotta)
                    .background(isSelected ? NonnaTheme.terracotta : NonnaTheme.sunken, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? (multiple ? "checkmark.square.fill" : "checkmark.circle.fill") : (multiple ? "square" : "circle"))
                    .foregroundStyle(isSelected ? NonnaTheme.terracotta : NonnaTheme.strongLine)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? NonnaTheme.terracotta.opacity(0.12) : (hovering ? NonnaTheme.raisedPaper : NonnaTheme.paper))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? NonnaTheme.terracotta.opacity(0.7) : NonnaTheme.line, lineWidth: isSelected ? 1.2 : 0.8)
            }
            .scaleEffect(hovering ? 1.01 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(NonnaMotion.quick, value: hovering)
    }
}

private struct PlanPreview: View {
    let plan: FocusPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Here's your plan.")
                    .font(.system(size: 34, weight: .regular, design: .serif))
                Text("You start at \(plan.level.focusMinutes)-minute blocks with \(plan.level.breakMinutes)-minute breaks, \(plan.dailyBlocks) \(plan.dailyBlocks == 1 ? "block" : "blocks") a day. Every \(FocusPlan.blocksPerLevel) full blocks across \(FocusPlan.daysPerLevel) days unlocks five more minutes, up to \(plan.levels.last?.focusMinutes ?? 45).")
                    .font(.system(size: 13))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            NonnaCard(padding: 18) {
                PlanLadder(plan: plan).frame(height: 140)
            }
            HStack(alignment: .top, spacing: 12) {
                fact("Today's goal", "\(plan.dailyBlocks) × \(plan.level.focusMinutes) min")
                fact("Long break", "\(plan.longBreakMinutes) min every \(plan.longBreakEvery)")
                fact("Target", plan.estimatedDaysToTarget == 0 ? "Already there" : "~\(plan.estimatedDaysToTarget) days away")
            }
            Text("Your timer switches to these lengths, and the breathing ritual stays on for a calm, identical start every time.")
                .font(.system(size: 11))
                .foregroundStyle(NonnaTheme.secondaryInk)
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(NonnaTheme.secondaryInk)
            Text(value).font(.system(size: 15, weight: .semibold))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NonnaTheme.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NonnaTheme.line) }
    }
}


/// A card whose body folds away under its title; the open/closed state is remembered.
private struct CollapsibleCard<Content: View>: View {
    let title: String
    let icon: String
    @AppStorage private var open: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder let content: Content

    init(title: String, icon: String, storageKey: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        _open = AppStorage(wrappedValue: true, storageKey)
        self.content = content()
    }

    var body: some View {
        NonnaCard {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.05)) { open.toggle() }
                } label: {
                    HStack {
                        Label(title, systemImage: icon)
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                            .rotationEffect(.degrees(open ? 0 : -90))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(open ? "Collapse" : "Expand")

                if open {
                    content
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
    }
}

/// The reward, shown large and editable in place: click to change it, Return to save.
private struct RewardField: View {
    let current: String
    let onSave: (String) -> Void
    @State private var text = ""
    @FocusState private var editing: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("Something you enjoy", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 17, design: .serif))
                .italic()
                .focused($editing)
                .onSubmit { save() }
                .onExitCommand {
                    text = current
                    editing = false
                }
                .onChange(of: editing) { _, isEditing in if !isEditing { save() } }
            Image(systemName: "pencil")
                .font(.system(size: 11))
                .foregroundStyle(NonnaTheme.secondaryInk)
                .opacity(editing ? 0 : 1)
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(editing ? NonnaTheme.terracotta : .clear).frame(height: 1)
        }
        .onAppear { text = current }
        .onChange(of: current) { _, value in if !editing { text = value } }
        .help("Click to change your reward")
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != current else { return }
        onSave(trimmed)
    }
}
