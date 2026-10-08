import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case focus = "Focus"
    case dashboard = "Dashboard"
    case history = "History"
    case tasks = "Tasks"
    case settings = "Settings"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .focus: "timer"
        case .dashboard: "chart.bar.xaxis"
        case .history: "clock.arrow.circlepath"
        case .tasks: "checklist"
        case .settings: "slider.horizontal.3"
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: AppSection = .focus

    var body: some View {
        ZStack {
            NonnaBackground()
            HStack(spacing: 0) {
                Sidebar(selection: $selection)
                    .frame(width: 82)
                Divider().overlay(NonnaTheme.line)
                ZStack {
                    Group {
                        switch selection {
                        case .focus: FocusView()
                        case .dashboard: DashboardView()
                        case .history: HistoryView()
                        case .tasks: TasksView()
                        case .settings: SettingsView()
                        }
                    }
                    .id(selection)
                    .transition(.opacity.combined(with: .scale(scale: 0.995)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(reduceMotion ? nil : NonnaMotion.page, value: selection)
            }
        }
        .foregroundStyle(NonnaTheme.ink)
        .tint(NonnaTheme.terracotta)
        .sheet(item: Bindable(model).reflectionSession) { session in
            ReflectionView(session: session)
                .environment(model)
        }
        .alert("Local storage", isPresented: Binding(
            get: { model.storageError != nil },
            set: { if !$0 { model.storageError = nil } }
        )) {
            Button("OK") { model.storageError = nil }
        } message: {
            Text(model.storageError ?? "Unknown error")
        }
    }
}

private struct Sidebar: View {
    @Binding var selection: AppSection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionMotion

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(NonnaTheme.ink)
                Text("P")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(NonnaTheme.cream)
            }
            .frame(width: 36, height: 36)
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 0.8)
            }
            .padding(.bottom, 25)

            ForEach(AppSection.allCases) { item in
                Button {
                    withAnimation(reduceMotion ? nil : NonnaMotion.selection) { selection = item }
                } label: {
                    ZStack(alignment: .leading) {
                        if selection == item {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(NonnaTheme.raisedPaper)
                                .frame(width: 40, height: 40)
                                .matchedGeometryEffect(id: "sidebar-surface", in: selectionMotion)
                            Capsule()
                                .fill(NonnaTheme.terracotta)
                                .frame(width: 2, height: 18)
                                .offset(x: -11)
                                .matchedGeometryEffect(id: "sidebar-indicator", in: selectionMotion)
                        }
                        Image(systemName: item.icon)
                            .font(.system(size: 15, weight: selection == item ? .semibold : .regular))
                            .frame(width: 40, height: 40)
                    }
                    .frame(width: 40, height: 40)
                    .foregroundStyle(selection == item ? NonnaTheme.ink : NonnaTheme.secondaryInk)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(SidebarButtonStyle(isSelected: selection == item))
                .help(item.rawValue)
                .accessibilityLabel(item.rawValue)
            }

            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(NonnaTheme.sage)
                .frame(width: 32, height: 32)
                .background(NonnaTheme.raisedPaper.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .help("Local-first · no cloud")
        }
        .padding(.top, 24)
        .padding(.horizontal, 15)
        .padding(.bottom, 18)
        .background(Color(hex: "090B0D").opacity(0.94))
    }
}

private struct SidebarButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        SidebarButtonBody(configuration: configuration, isSelected: isSelected)
    }
}

private struct SidebarButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : (isHovering ? 1.06 : 1))
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovering && !isSelected ? NonnaTheme.raisedPaper.opacity(0.62) : .clear)
            }
            .animation(reduceMotion ? nil : NonnaMotion.quick, value: configuration.isPressed)
            .animation(reduceMotion ? nil : NonnaMotion.quick, value: isHovering)
            .onHover { isHovering = $0 }
    }
}
