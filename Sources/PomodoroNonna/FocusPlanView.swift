import SwiftUI

// MARK: - Plan section

struct FocusPlanView: View {
    @Environment(AppModel.self) private var model
    @State private var showsQuestionnaire = false
    @State private var confirmsRemoval = false
    var onStartBlock: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let plan = model.focusPlan {
                    if let level = model.planLevelUp {
                        LevelUpBanner(level: level, isFinal: plan.isFinalLevel) { model.planLevelUp = nil }
                    }
                    dashboard(plan)
                } else {
                    PlanIntro { showsQuestionnaire = true }
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
        .confirmationDialog("Remove your focus plan?", isPresented: $confirmsRemoval) {
            Button("Remove plan", role: .destructive) { model.removePlan() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your timer keeps its current lengths and your history stays. You can build a new plan any time.")
        }
    }

    // MARK: Dashboard

    @ViewBuilder
    private func dashboard(_ plan: FocusPlan) -> some View {
        let progress = plan.progress(sessions: model.sessions)
        let today = plan.blocksToday(sessions: model.sessions)

        HStack(alignment: .bottom) {
            SectionHeading(
                eyebrow: "Dopamine focus plan",
                title: "Your focus rebuild",
                subtitle: "Level \(plan.levelIndex + 1) of \(plan.levels.count) · \(plan.level.focusMinutes) min focus, \(plan.level.breakMinutes) min break"
            )
            Spacer()
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

        HStack(alignment: .top, spacing: 18) {
            NonnaCard {
                HStack(spacing: 26) {
                    LevelRing(fraction: plan.isFinalLevel ? 1 : progress.fraction, minutes: plan.level.focusMinutes)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(plan.isFinalLevel ? "TARGET REACHED" : "NEXT LEVEL")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(1.8)
                            .foregroundStyle(NonnaTheme.terracotta)
                        if plan.isFinalLevel {
                            Text("\(plan.level.focusMinutes)-minute blocks are yours.")
                                .font(.system(size: 20, weight: .semibold))
                            Text("Keep the rhythm. Consistency now protects what you rebuilt.")
                                .font(.system(size: 12))
                                .foregroundStyle(NonnaTheme.secondaryInk)
                        } else {
                            let next = plan.levels[plan.levelIndex + 1]
                            Text("\(next.focusMinutes) min focus · \(next.breakMinutes) min break")
                                .font(.system(size: 20, weight: .semibold))
                            requirement("Full \(plan.level.focusMinutes)-minute blocks", done: progress.fullBlocks, of: FocusPlan.blocksPerLevel)
                            requirement("Different days", done: progress.days, of: FocusPlan.daysPerLevel)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            NonnaCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("TODAY")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.8)
                        .foregroundStyle(NonnaTheme.terracotta)
                    Text("\(min(today, plan.dailyBlocks)) of \(plan.dailyBlocks) blocks")
                        .font(.system(size: 20, weight: .semibold))
                        .monospacedDigit()
                    HStack(spacing: 6) {
                        ForEach(0..<plan.dailyBlocks, id: \.self) { index in
                            Capsule()
                                .fill(index < today ? NonnaTheme.terracotta : NonnaTheme.strongLine)
                                .frame(width: index < today ? 22 : 14, height: 5)
                        }
                    }
                    Text(today >= plan.dailyBlocks ? "Done for today. Go enjoy your reward." : "Each block is \(plan.level.focusMinutes) minutes. Starting is the hard part.")
                        .font(.system(size: 12))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
                .frame(width: 260, alignment: .leading)
            }
        }

        NonnaCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("THE LADDER")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.8)
                        .foregroundStyle(NonnaTheme.terracotta)
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

        HStack(alignment: .top, spacing: 18) {
            NonnaCard {
                VStack(alignment: .leading, spacing: 14) {
                    Label("House rules", systemImage: "checkmark.seal")
                        .font(.system(size: 15, weight: .semibold))
                    ForEach(Array(plan.rules.enumerated()), id: \.offset) { _, rule in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(rule.title).font(.system(size: 13, weight: .semibold))
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
                NonnaCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Break menu", systemImage: "cup.and.saucer")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Breaks that rest you without a spike that makes the work feel dull.")
                            .font(.system(size: 12))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                        ForEach(plan.breakMenu, id: \.self) { idea in
                            HStack(alignment: .firstTextBaseline, spacing: 9) {
                                Circle().fill(NonnaTheme.sage).frame(width: 5, height: 5)
                                Text(idea).font(.system(size: 12))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                NonnaCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Your reward", systemImage: "gift")
                            .font(.system(size: 15, weight: .semibold))
                        Text(plan.rewardLine)
                            .font(.system(size: 17, design: .serif))
                            .italic()
                        Text("Only after the day's last block. Wanting it is what pulls you through the middle.")
                            .font(.system(size: 12))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        Text("Built on simple habit science: start small, earn each step, keep breaks low-stimulation. It isn't medical advice.")
            .font(.system(size: 10))
            .foregroundStyle(NonnaTheme.secondaryInk.opacity(0.8))
    }

    private func requirement(_ title: String, done: Int, of total: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done >= total ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done >= total ? NonnaTheme.sage : NonnaTheme.secondaryInk)
            Text(title).font(.system(size: 12))
            Spacer(minLength: 8)
            Text("\(min(done, total)) of \(total)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(NonnaTheme.secondaryInk)
        }
        .frame(maxWidth: 300)
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
                Text("MIN")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
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
                        .frame(height: shown ? max(14, 112 * Double(level.focusMinutes) / maxMinutes) : 8)
                        .animation(reduceMotion ? nil : .spring(duration: 0.8, bounce: 0.2).delay(0.1 + Double(index) * 0.06), value: shown)
                    Text("\(level.focusMinutes)")
                        .font(.system(size: 11, weight: current ? .bold : .medium, design: .monospaced))
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

struct LevelUpBanner: View {
    let level: FocusPlan.Level
    let isFinal: Bool
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: isFinal ? "trophy.fill" : "arrow.up.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(NonnaTheme.terracotta)
            VStack(alignment: .leading, spacing: 2) {
                Text(isFinal ? "Target reached" : "Level up")
                    .font(.system(size: 14, weight: .semibold))
                Text(isFinal
                     ? "\(level.focusMinutes)-minute blocks are yours now."
                     : "You've earned \(level.focusMinutes)-minute blocks with \(level.breakMinutes)-minute breaks. Your next block uses them.")
                    .font(.system(size: 12))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            Spacer()
            Button("Nice", action: onDismiss)
                .buttonStyle(NonnaButtonStyle(prominent: false))
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(NonnaTheme.terracotta.opacity(0.1))
                .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NonnaTheme.terracotta.opacity(0.45), lineWidth: 0.8) }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

private struct PlanIntro: View {
    let onBegin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            VStack(alignment: .leading, spacing: 14) {
                Text("DOPAMINE FOCUS PLAN")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2.4)
                    .foregroundStyle(NonnaTheme.terracotta)
                Text("Rebuild your focus,\none block at a time.")
                    .font(.system(size: 46, weight: .regular, design: .serif))
                    .tracking(-0.8)
                Text("Answer eight quick questions. Pomofocus builds a plan that starts where your attention is today and climbs, five minutes at a time, to 45-minute blocks with 15-minute breaks, or whatever you're aiming for.")
                    .font(.system(size: 15))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .frame(maxWidth: 620, alignment: .leading)
            }

            HStack(alignment: .top, spacing: 16) {
                principle("1", "Start where you are", "If ten minutes is your honest limit today, the plan starts at ten. Early wins build the habit.")
                principle("2", "Earn every minute", "Four full blocks across two days unlock the next length. Progress you can trust.")
                principle("3", "Rest without the spike", "Breaks stay low-stimulation, and the feeds wait until your reward.")
            }

            Button(action: onBegin) {
                Label("Build my plan", systemImage: "sparkles")
            }
            .buttonStyle(NonnaButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 30)
    }

    private func principle(_ number: String, _ title: String, _ detail: String) -> some View {
        NonnaCard(padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text(number)
                    .font(.system(size: 30, weight: .light, design: .serif))
                    .foregroundStyle(NonnaTheme.terracotta)
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
                Text(step < questionCount ? "QUESTION \(step + 1) OF \(questionCount)" : "YOUR PLAN")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(2)
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
        .preferredColorScheme(.dark)
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
                    .foregroundStyle(isSelected ? NonnaTheme.cream : NonnaTheme.terracotta)
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
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(NonnaTheme.secondaryInk)
            Text(value).font(.system(size: 15, weight: .semibold))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NonnaTheme.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NonnaTheme.line) }
    }
}
