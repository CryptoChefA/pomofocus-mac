import SwiftUI

/// Your dashboards of widgets, your mood, History and your plan in one place.
struct ProgressSectionView: View {
    @Environment(AppModel.self) private var model
    let onStartPlan: () -> Void

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Picker("", selection: $model.progressTab.animation(.easeInOut(duration: 0.28))) {
                Text("Dashboard").tag(0)
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
                default: DashboardBoard().transition(.opacity)
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
