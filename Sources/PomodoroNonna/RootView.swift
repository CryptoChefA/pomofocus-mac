import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case focus = "Focus"
    case plan = "Plan"
    case dashboard = "Dashboard"
    case history = "History"
    case tasks = "Tasks"
    case settings = "Settings"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .focus: "timer"
        case .plan: "figure.stairs"
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
                    .frame(maxHeight: .infinity)
                    // The whole column, edge to edge and under the title bar, so no theme
                    // scenery shows through beside the icons.
                    .background(NonnaTheme.sunken.ignoresSafeArea())
                Divider().overlay(NonnaTheme.line)
                GeometryReader { proxy in
                ZStack {
                    Group {
                        switch selection {
                        case .focus: FocusView()
                        case .plan: FocusPlanView {
                            withAnimation(reduceMotion ? nil : NonnaMotion.page) { selection = .focus }
                            if model.status == .idle, !model.isBreathing, model.awaitingNextPhase == nil { model.startFocus() }
                        }
                        case .dashboard: DashboardView()
                        case .history: HistoryView()
                        case .tasks: TasksView()
                        case .settings: SettingsView()
                        }
                    }
                    .id(selection)
                    .transition(.opacity.combined(with: .scale(scale: 0.995)))
                }
                .environment(\.compactLayout, proxy.size.width < 980)
                .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(reduceMotion ? nil : NonnaMotion.page, value: selection)
            }
        }
        .foregroundStyle(NonnaTheme.ink)
        .tint(NonnaTheme.terracotta)
        .onOpenURL { url in
            // pomofocus://focus, from a click on the desktop widget.
            if url.host == "focus" { selection = .focus }
            NSApp.activate()
        }
        .sheet(isPresented: Binding(get: { model.needsOnboarding }, set: { _ in })) {
            WelcomeView {
                withAnimation(reduceMotion ? nil : NonnaMotion.page) { selection = .plan }
            }
            .environment(model)
        }
        .overlay {
            if !model.needsOnboarding { LaunchGreeting() }
        }
        .background {
            // Esc in Settings goes back to the timer.
            if selection == .settings {
                Button("Back to the timer") {
                    withAnimation(reduceMotion ? nil : NonnaMotion.page) { selection = .focus }
                }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
        }
        .sheet(isPresented: Bindable(Updater.shared).showsSheet) {
            UpdateSheet()
        }
        .sheet(isPresented: Bindable(model).showsWrapUp) {
            WrapUpSheet { model.showsWrapUp = false }
                .environment(model)
        }
        .sheet(isPresented: Bindable(Updater.shared).showsWhatsNew) {
            WhatsNewSheet { Updater.shared.showsWhatsNew = false }
        }
        .task {
            Updater.shared.prepareToQuit = { [model] in await model.flushForQuit() }
            // Decide about onboarding vs What's new only once the data has loaded.
            while !model.hasLoaded, model.storageError == nil {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard model.hasLoaded else { return }
            let defaults = UserDefaults.standard
            let current = Updater.shared.currentVersion
            if model.needsOnboarding {
                // A fresh install has nothing "new" to announce.
                defaults.set(current, forKey: WhatsNew.lastSeenKey)
            } else if defaults.string(forKey: WhatsNew.lastSeenKey) != current {
                defaults.set(current, forKey: WhatsNew.lastSeenKey)
                // After the welcome greeting has had its moment.
                try? await Task.sleep(for: .seconds(2.6))
                Updater.shared.showsWhatsNew = true
                return
            }
            await Updater.shared.checkAutomaticallyIfDue()
        }
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
    /// The user's order for the top icons, by raw value. Settings always sits at the bottom.
    @AppStorage("sidebarOrder") private var storedOrder = ""
    @State private var dragging: AppSection?

    /// Focus is the home tile at the top and Settings sits at the bottom; the rest can move.
    private static let defaultOrder = AppSection.allCases.filter { $0 != .settings && $0 != .focus }

    private var order: [AppSection] {
        let saved = storedOrder.split(separator: ",").compactMap { AppSection(rawValue: String($0)) }.filter { Self.defaultOrder.contains($0) }
        // Keep anything new or missing at the end, in its usual place.
        return saved + Self.defaultOrder.filter { !saved.contains($0) }
    }

    var body: some View {
        VStack(spacing: 10) {
            // The timer is home, so it sits where an app's logo would.
            Button {
                dragging = nil
                withAnimation(reduceMotion ? nil : NonnaMotion.selection) { selection = .focus }
            } label: {
                Image(systemName: AppSection.focus.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(selection == .focus ? NonnaTheme.onAccent : NonnaTheme.cream)
                    .frame(width: 40, height: 40)
                    .background(selection == .focus ? NonnaTheme.terracotta : NonnaTheme.ink,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.white.opacity(0.22), lineWidth: 0.8)
                    }
                    .shadow(color: selection == .focus ? NonnaTheme.terracotta.opacity(0.35) : .clear, radius: 8)
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Focus")
            .accessibilityLabel("Focus")
            .padding(.bottom, 21)

            ForEach(order) { item in
                button(for: item)
                    .opacity(dragging == item ? 0.4 : 1)
                    .onDrag {
                        dragging = item
                        return NSItemProvider(object: item.rawValue as NSString)
                    }
                    .onDrop(of: [.text], delegate: SidebarDropDelegate(item: item, dragging: $dragging, move: move))
                    .contextMenu {
                        Button("Move up") { shift(item, by: -1) }
                            .disabled(order.first == item)
                        Button("Move down") { shift(item, by: 1) }
                            .disabled(order.last == item)
                        Divider()
                        Button("Reset order") { storedOrder = "" }
                    }
            }

            Spacer()

            button(for: .settings)
                // A red dot when an update is waiting.
                .overlay(alignment: .topTrailing) {
                    if Updater.shared.available != nil {
                        Circle()
                            .fill(Color(red: 0.95, green: 0.26, blue: 0.24))
                            .frame(width: 9, height: 9)
                            .overlay { Circle().stroke(NonnaTheme.sunken, lineWidth: 2) }
                            .offset(x: 1, y: -1)
                            .transition(.scale.combined(with: .opacity))
                            .help("An update is ready")
                    }
                }
        }
        .padding(.top, 24)
        .padding(.horizontal, 15)
        .padding(.bottom, 18)
        // Solid, so theme scenery (frost, petals) never shows through the sidebar.
        .background(NonnaTheme.sunken)
        // A drop anywhere else in the sidebar just ends the drag.
        .onDrop(of: [.text], isTargeted: nil) { _ in
            dragging = nil
            return true
        }
    }

    private func button(for item: AppSection) -> some View {
        Button {
            dragging = nil
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
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(SidebarButtonStyle(isSelected: selection == item))
        .help(item == .settings ? "Settings" : "\(item.rawValue), drag to reorder")
        .accessibilityLabel(item.rawValue)
    }

    private func move(_ item: AppSection, to target: AppSection) {
        var items = order
        guard item != target, let from = items.firstIndex(of: item), let to = items.firstIndex(of: target) else { return }
        items.remove(at: from)
        items.insert(item, at: to)
        withAnimation(reduceMotion ? nil : NonnaMotion.selection) {
            storedOrder = items.map(\.rawValue).joined(separator: ",")
        }
    }

    private func shift(_ item: AppSection, by offset: Int) {
        let items = order
        guard let index = items.firstIndex(of: item), items.indices.contains(index + offset) else { return }
        move(item, to: items[index + offset])
    }
}

/// Reorders the sidebar live as an icon is dragged over another.
private struct SidebarDropDelegate: DropDelegate {
    let item: AppSection
    @Binding var dragging: AppSection?
    let move: (AppSection, AppSection) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != item else { return }
        move(dragging, item)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
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
