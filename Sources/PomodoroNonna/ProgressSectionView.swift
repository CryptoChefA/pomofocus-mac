import SwiftUI

/// Dashboard, History and the plan in one place, with only the numbers that change what
/// you do next on the front.
struct ProgressSectionView: View {
    @Environment(AppModel.self) private var model
    let onStartPlan: () -> Void

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Picker("", selection: $model.progressTab.animation(.easeInOut(duration: 0.28))) {
                Text("Overview").tag(0)
                Text("Mood").tag(4)
                Text("History").tag(1)
                Text("Your plan").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 400)
            .padding(.top, 22)
            .padding(.bottom, 4)

            ZStack {
                switch model.progressTab {
                case 1: HistoryView().transition(.opacity)
                case 2: FocusPlanView(onStartBlock: onStartPlan).transition(.opacity)
                case 4: MoodTab().transition(.opacity)
                default: ProgressOverview().transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Mood tracking: today's check-in and how it's gone over the weeks.
private struct MoodTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeading(title: "Mood")
                MoodCard()
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 26)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ProgressOverview: View {
    @Environment(AppModel.self) private var model
    @State private var showsMore = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeading(title: "Progress", subtitle: "What's worth knowing, without a grade.")

                HStack(alignment: .top, spacing: 16) {
                    weekTile
                    planTile
                }

                PeakHoursCard()

                moodCard

                VStack(alignment: .leading, spacing: 10) {
                    Text("Recaps")
                        .font(.system(size: 15, weight: .semibold))
                    WeekDashboardRow()
                    YearDashboardRow()
                }
                RunawayTimersBanner()

                // Everything else, one click away.
                Button {
                    withAnimation(.easeInOut(duration: 0.35)) { showsMore.toggle() }
                } label: {
                    Label(showsMore ? "Show less" : "See more", systemImage: showsMore ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(NonnaButtonStyle(prominent: false))
                .frame(maxWidth: .infinity)
                .padding(.top, 6)

                if showsMore {
                    DashboardView(embedded: true)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 26)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
    }

    private var weekTile: some View {
        let seconds = WeeklyTotals.calculate(sessions: model.sessions).thisWeek?.seconds ?? 0
        return tile(icon: "calendar", title: "This week") {
            Text(seconds.focusDurationString)
                .font(.system(size: 34, weight: .semibold).monospacedDigit())
            Text("of focus since Monday")
                .font(.system(size: 12))
                .foregroundStyle(NonnaTheme.secondaryInk)
        }
    }

    private var planTile: some View {
        tile(icon: "figure.stairs", title: "Your plan") {
            if let plan = model.focusPlan {
                Text("\(plan.level.focusMinutes)-minute blocks")
                    .font(.system(size: 26, weight: .semibold))
                Text("Level \(plan.levelIndex + 1) of \(plan.levels.count), aiming for \(plan.levels.last?.focusMinutes ?? plan.level.focusMinutes)")
                    .font(.system(size: 12))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            } else {
                Text("\(model.settings.focusMinutes)-minute blocks")
                    .font(.system(size: 26, weight: .semibold))
                Button("Build a plan that grows with you") { model.progressTab = 2 }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NonnaTheme.terracotta)
            }
        }
    }

    private var moodCard: some View {
        HStack(spacing: 14) {
            MoodButton()
            VStack(alignment: .leading, spacing: 3) {
                Text("How are you feeling today?")
                    .font(.system(size: 14, weight: .semibold))
                Text(model.todaysCheckIn == nil
                     ? "A ten-second check-in. It shows up in your weekly recap."
                     : "Checked in today. Click the flower to change it.")
                    .font(.system(size: 12))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            Spacer()
            Button(model.todaysCheckIn == nil ? "Check in" : "Update") { model.showsMoodCheckIn = true }
                .buttonStyle(NonnaButtonStyle(prominent: false))
        }
        .padding(16)
        .background(NonnaTheme.raisedPaper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }
    }

    private func tile<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NonnaTheme.secondaryInk)
            content()
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .padding(18)
        .background(NonnaTheme.raisedPaper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }
    }
}
