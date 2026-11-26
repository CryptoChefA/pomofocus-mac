import SwiftUI

// Progress as a board of widgets, like the ones on the Mac desktop: pick what to show, drag
// them into any order, make each small, medium, large or extra large, and keep several
// dashboards. Widgets pack together on a four-column grid, filling gaps the way macOS does.

// MARK: - Model

enum WidgetSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large, extraLarge

    var id: String { rawValue }
    var columns: Int { switch self { case .small: 1; case .medium, .large: 2; case .extraLarge: 4 } }
    var rows: Int { switch self { case .small, .medium: 1; case .large, .extraLarge: 2 } }

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .extraLarge: "Extra large"
        }
    }

    var short: String {
        switch self {
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        case .extraLarge: "XL"
        }
    }
}

enum StatWidget: String, Codable, CaseIterable, Identifiable {
    case today, thisWeek, plan, focusScore, mood, peakHours, streak
    case focusTotal, completed, daysUsed, breakTime, breakOvertime
    case dailyFocus, hoursByWeek, timeByList, consistency
    case weekRecap, yearRecap
    case trends, rhythm, quality, breaks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .thisWeek: "This week"
        case .plan: "Your plan"
        case .focusScore: "Focus score"
        case .mood: "Mood"
        case .peakHours: "Peak hours"
        case .streak: "Streak"
        case .focusTotal: "Focus time"
        case .completed: "Completed sessions"
        case .daysUsed: "Days used"
        case .breakTime: "Break time"
        case .breakOvertime: "Break overtime"
        case .dailyFocus: "Daily focus"
        case .hoursByWeek: "Hours by week"
        case .timeByList: "Time by list"
        case .consistency: "Consistency"
        case .weekRecap: "Your week"
        case .yearRecap: "Your year"
        case .trends: "Focus over time"
        case .rhythm: "Time of day"
        case .quality: "Ratings"
        case .breaks: "Breaks and overtime"
        }
    }

    var detail: String {
        switch self {
        case .today: "Focus today against your goal"
        case .thisWeek: "This week against last week"
        case .plan: "Your block length and level"
        case .focusScore: "Today's score out of 100"
        case .mood: "Today's check-in and recent days"
        case .peakHours: "When you focus best"
        case .streak: "Days in a row"
        case .focusTotal: "All your focus time"
        case .completed: "Blocks run to the bell"
        case .daysUsed: "Days with any focus"
        case .breakTime: "Time on breaks"
        case .breakOvertime: "Breaks that ran long"
        case .dailyFocus: "The last 14 days"
        case .hoursByWeek: "The last 12 weeks"
        case .timeByList: "Focus by list"
        case .consistency: "A square for each day"
        case .weekRecap: "Last week's recap"
        case .yearRecap: "Your year so far"
        case .trends: "The last month, day by day"
        case .rhythm: "Your hours and weekdays"
        case .quality: "How your blocks felt"
        case .breaks: "Skipped and long breaks"
        }
    }

    var icon: String {
        switch self {
        case .today: "sun.max"
        case .thisWeek: "calendar"
        case .plan: "figure.stairs"
        case .focusScore: "gauge.with.dots.needle.67percent"
        case .mood: "heart.text.square"
        case .peakHours: "clock"
        case .streak: "flame.fill"
        case .focusTotal: "hourglass"
        case .completed: "checkmark.seal.fill"
        case .daysUsed: "calendar.badge.checkmark"
        case .breakTime: "cup.and.saucer.fill"
        case .breakOvertime: "clock.badge.exclamationmark"
        case .dailyFocus: "chart.bar"
        case .hoursByWeek: "chart.bar.xaxis"
        case .timeByList: "list.bullet.rectangle"
        case .consistency: "square.grid.3x3.fill"
        case .weekRecap: "calendar.day.timeline.left"
        case .yearRecap: "rectangle.stack"
        case .trends: "chart.xyaxis.line"
        case .rhythm: "clock.arrow.2.circlepath"
        case .quality: "star.leadinghalf.filled"
        case .breaks: "cup.and.heat.waves"
        }
    }

    var sizes: [WidgetSize] {
        switch self {
        case .today, .thisWeek, .plan, .streak, .focusTotal, .completed, .daysUsed, .breakTime, .breakOvertime:
            [.small, .medium]
        case .focusScore: [.small, .medium, .extraLarge]
        case .mood: [.small, .medium, .extraLarge]
        case .peakHours: [.medium, .extraLarge]
        case .dailyFocus, .hoursByWeek: [.medium, .large, .extraLarge]
        case .timeByList: [.medium, .large]
        case .consistency: [.large, .extraLarge]
        case .weekRecap, .yearRecap: [.small, .medium]
        case .trends, .rhythm: [.large, .extraLarge]
        case .quality, .breaks: [.large, .extraLarge]
        }
    }

    /// Shown as the full card from elsewhere in the app, which can be taller than its size.
    func isFullCard(at size: WidgetSize) -> Bool {
        switch self {
        case .dailyFocus, .hoursByWeek, .timeByList: size != .medium
        case .consistency, .trends, .rhythm, .quality, .breaks: true
        case .focusScore, .mood, .peakHours: size == .extraLarge
        default: false
        }
    }

    var metric: DashboardMetric? {
        switch self {
        case .focusTotal: .focus
        case .completed: .completed
        case .daysUsed: .daysUsed
        case .breakTime: .breakTime
        case .breakOvertime: .breakOvertime
        case .streak: .rhythm
        default: nil
        }
    }
}

struct PlacedWidget: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: StatWidget
    var size: WidgetSize
}

struct StatDashboard: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var widgets: [PlacedWidget]

    static var defaults: [StatDashboard] {
        [
            StatDashboard(name: "Overview", widgets: [
                .init(kind: .thisWeek, size: .medium), .init(kind: .plan, size: .medium),
                .init(kind: .today, size: .small), .init(kind: .streak, size: .small),
                .init(kind: .mood, size: .medium),
                .init(kind: .peakHours, size: .extraLarge),
                .init(kind: .weekRecap, size: .medium), .init(kind: .yearRecap, size: .medium),
            ]),
            StatDashboard(name: "In depth", widgets: [
                .init(kind: .focusScore, size: .medium),
                .init(kind: .focusTotal, size: .small), .init(kind: .completed, size: .small),
                .init(kind: .daysUsed, size: .small), .init(kind: .streak, size: .small),
                .init(kind: .breakTime, size: .small), .init(kind: .breakOvertime, size: .small),
                .init(kind: .timeByList, size: .medium),
                .init(kind: .dailyFocus, size: .extraLarge),
                .init(kind: .hoursByWeek, size: .large), .init(kind: .consistency, size: .large),
                .init(kind: .trends, size: .extraLarge),
                .init(kind: .rhythm, size: .extraLarge),
                .init(kind: .quality, size: .large), .init(kind: .breaks, size: .large),
            ]),
        ]
    }
}

/// Dashboards are saved on this Mac as JSON in the app's preferences.
@MainActor
@Observable
final class DashboardStore {
    static let shared = DashboardStore()
    private static let key = "progressDashboards"
    private static let selectedKey = "progressDashboardSelected"

    var dashboards: [StatDashboard] { didSet { save() } }
    var selectedID: UUID { didSet { UserDefaults.standard.set(selectedID.uuidString, forKey: Self.selectedKey) } }

    private init() {
        let saved = UserDefaults.standard.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([StatDashboard].self, from: $0) }
        var list = (saved?.isEmpty == false ? saved : nil) ?? StatDashboard.defaults
        // A size a widget no longer comes in moves to the closest one it does.
        for d in list.indices {
            for w in list[d].widgets.indices {
                let widget = list[d].widgets[w]
                guard !widget.kind.sizes.contains(widget.size) else { continue }
                list[d].widgets[w].size = widget.kind.sizes.min {
                    abs($0.columns - widget.size.columns) + abs($0.rows - widget.size.rows)
                        < abs($1.columns - widget.size.columns) + abs($1.rows - widget.size.rows)
                } ?? widget.kind.sizes[0]
            }
        }
        dashboards = list
        let stored = UserDefaults.standard.string(forKey: Self.selectedKey).flatMap(UUID.init)
        selectedID = list.contains { $0.id == stored } ? stored! : list[0].id
        // The defaults get new ids each time they're made, so keep the first set.
        if saved != list { save() }
    }

    var selectedIndex: Int { dashboards.firstIndex { $0.id == selectedID } ?? 0 }

    private func save() {
        if let data = try? JSONEncoder().encode(dashboards) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    func add(named name: String) {
        let dashboard = StatDashboard(name: name, widgets: [])
        dashboards.append(dashboard)
        selectedID = dashboard.id
    }

    func deleteSelected() {
        guard dashboards.count > 1 else { return }
        let index = selectedIndex
        dashboards.remove(at: index)
        selectedID = dashboards[max(0, index - 1)].id
    }

    func resetSelected() {
        let index = selectedIndex
        let name = dashboards[index].name
        if let match = StatDashboard.defaults.first(where: { $0.name == name }) {
            dashboards[index].widgets = match.widgets
        } else {
            dashboards[index].widgets = []
        }
    }
}

// MARK: - Packing

/// Where a widget sits on the grid, in cells.
struct GridSlot: Equatable {
    var column: Int
    var row: Int
    var columns: Int
    var rows: Int
}

enum WidgetPacking {
    /// Each widget, in order, takes the first place it fits, scanning rows top to bottom,
    /// so a small widget later in the list fills a gap left beside a bigger one.
    /// `rows` holds extra height for cards that need more than their size's rows.
    static func pack(_ widgets: [PlacedWidget], columns: Int, rows: [UUID: Int] = [:]) -> [UUID: GridSlot] {
        var taken: [[Bool]] = []
        var slots: [UUID: GridSlot] = [:]
        func free(_ row: Int, _ column: Int, _ width: Int, _ height: Int) -> Bool {
            for r in row..<(row + height) {
                guard r < taken.count else { continue }
                for c in column..<(column + width) where taken[r][c] { return false }
            }
            return true
        }
        for widget in widgets {
            let width = min(widget.size.columns, columns)
            let height = max(widget.size.rows, rows[widget.id] ?? 0)
            var row = 0
            search: while true {
                for column in 0...(columns - width) where free(row, column, width, height) {
                    while taken.count < row + height { taken.append(Array(repeating: false, count: columns)) }
                    for r in row..<(row + height) { for c in column..<(column + width) { taken[r][c] = true } }
                    slots[widget.id] = GridSlot(column: column, row: row, columns: width, rows: height)
                    break search
                }
                row += 1
            }
        }
        return slots
    }
}

// MARK: - Board

struct DashboardBoard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = DashboardStore.shared
    @State private var editing = false
    @State private var showsGallery = false
    @State private var width: CGFloat = 800
    @State private var dragging: UUID?
    @State private var dragOrigin: CGPoint = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var lastSwap: UUID?
    @State private var resizing: UUID?
    @State private var resizeStart: CGSize = .zero
    @State private var selectedMetric: DashboardMetric?
    @State private var renaming = false
    @State private var newName = ""
    /// Rows a full chart card needs at its width, measured, so it grows instead of clipping.
    @State private var neededRows: [UUID: Int] = [:]

    static let columns = 4
    static let gap: CGFloat = 14
    static let rowHeight: CGFloat = 168

    private var unitWidth: CGFloat { max(80, (width - Self.gap * CGFloat(Self.columns - 1)) / CGFloat(Self.columns)) }

    private var widgets: [PlacedWidget] { store.dashboards[store.selectedIndex].widgets }

    private func setWidgets(_ update: (inout [PlacedWidget]) -> Void) {
        update(&store.dashboards[store.selectedIndex].widgets)
    }

    private func frame(_ slot: GridSlot) -> CGRect {
        CGRect(x: CGFloat(slot.column) * (unitWidth + Self.gap),
               y: CGFloat(slot.row) * (Self.rowHeight + Self.gap),
               width: CGFloat(slot.columns) * unitWidth + CGFloat(slot.columns - 1) * Self.gap,
               height: CGFloat(slot.rows) * Self.rowHeight + CGFloat(slot.rows - 1) * Self.gap)
    }

    private var motion: Animation? { reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.15) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if showsGallery {
                    WidgetGallery(onAdd: add)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                board
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 26)
            .frame(maxWidth: 940)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $selectedMetric) { metric in
            MetricDeepDiveView(metric: metric, sessions: model.sessions, breaks: model.breakSessions,
                               tasks: model.data.tasks, dailyGoalMinutes: model.settings.dailyGoalMinutes)
                .closesOnClickOutside { selectedMetric = nil }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(store.dashboards) { dashboard in
                    Button {
                        withAnimation(motion) { store.selectedID = dashboard.id }
                    } label: {
                        if dashboard.id == store.selectedID {
                            Label(dashboard.name, systemImage: "checkmark")
                        } else {
                            Text(dashboard.name)
                        }
                    }
                }
                Divider()
                Button("New dashboard") {
                    store.add(named: "Dashboard \(store.dashboards.count + 1)")
                    withAnimation(motion) { editing = true; showsGallery = true }
                }
                Button("Rename…") { newName = store.dashboards[store.selectedIndex].name; renaming = true }
                Button("Reset to default") { withAnimation(motion) { store.resetSelected() } }
                Button("Delete dashboard", role: .destructive) { withAnimation(motion) { store.deleteSelected() } }
                    .disabled(store.dashboards.count < 2)
            } label: {
                HStack(spacing: 6) {
                    Text(store.dashboards[store.selectedIndex].name)
                        .font(.system(size: 26, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .popover(isPresented: $renaming) {
                HStack {
                    TextField("Name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .onSubmit(rename)
                    Button("Rename", action: rename)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(12)
            }

            Spacer()

            if editing {
                Button {
                    withAnimation(motion) { showsGallery.toggle() }
                } label: {
                    Label(showsGallery ? "Hide widgets" : "Add widgets", systemImage: showsGallery ? "chevron.up" : "plus")
                }
                .buttonStyle(NonnaButtonStyle(prominent: false))
            }
            Button(editing ? "Done" : "Edit widgets") {
                withAnimation(motion) {
                    editing.toggle()
                    showsGallery = editing && widgets.isEmpty
                }
            }
            .buttonStyle(NonnaButtonStyle(prominent: editing))
        }
    }

    private func rename() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { store.dashboards[store.selectedIndex].name = name }
        renaming = false
    }

    // MARK: Grid

    private var board: some View {
        let slots = WidgetPacking.pack(widgets, columns: Self.columns, rows: neededRows)
        let rows = slots.values.map { $0.row + $0.rows }.max() ?? 0
        let height = rows == 0 ? 0 : CGFloat(rows) * Self.rowHeight + CGFloat(rows - 1) * Self.gap
        return ZStack(alignment: .topLeading) {
            Color.clear.frame(height: max(height, widgets.isEmpty ? 180 : 0))
            if widgets.isEmpty {
                emptyBoard
            }
            ForEach(widgets) { widget in
                if let slot = slots[widget.id] {
                    let rect = frame(slot)
                    let isDragged = dragging == widget.id
                    tile(widget, rect: rect)
                        .frame(width: rect.width, height: rect.height)
                        .scaleEffect(isDragged ? 1.03 : 1)
                        .shadow(color: .black.opacity(isDragged ? 0.3 : 0), radius: 20, y: 8)
                        .offset(x: isDragged ? dragOrigin.x + dragOffset.width : rect.minX,
                                y: isDragged ? dragOrigin.y + dragOffset.height : rect.minY)
                        .zIndex(isDragged ? 1 : 0)
                        // Ahead of the buttons inside a widget, so moving the pointer picks the
                        // widget up straight away; a click without moving still reaches them.
                        .highPriorityGesture(dragGesture(widget, rect: rect, slots: slots))
                }
            }
        }
        .coordinateSpace(.named("board"))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private var emptyBoard: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(NonnaTheme.secondaryInk)
            Text("No widgets yet")
                .font(.system(size: 15, weight: .semibold))
            Text("Click Add widgets to choose what this dashboard shows.")
                .font(.system(size: 12))
                .foregroundStyle(NonnaTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(NonnaTheme.line, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        }
    }

    @ViewBuilder
    private func content(_ widget: PlacedWidget, rect: CGRect) -> some View {
        let view = StatWidgetView(kind: widget.kind, size: widget.size, onMetric: { selectedMetric = $0 })
        if widget.kind.isFullCard(at: widget.size) {
            view
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: rect.width)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    let rows = Int(((height + Self.gap) / (Self.rowHeight + Self.gap)).rounded(.up))
                    if neededRows[widget.id] != rows { neededRows[widget.id] = rows }
                }
        } else {
            view
        }
    }

    private func tile(_ widget: PlacedWidget, rect: CGRect) -> some View {
        content(widget, rect: rect)
            .frame(width: rect.width, height: rect.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .background {
                NonnaSurface(shape: RoundedRectangle(cornerRadius: 16, style: .continuous), tint: NonnaTheme.paper,
                             opacity: 0.94, shadowRadius: 14)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(editing ? NonnaTheme.terracotta.opacity(0.45) : NonnaTheme.line.opacity(0.78), lineWidth: 0.8)
            }
            .overlay(alignment: .topLeading) {
                if editing {
                    Button { remove(widget) } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Color.black.opacity(0.65), in: Circle())
                            .overlay { Circle().stroke(.white.opacity(0.35), lineWidth: 0.8) }
                    }
                    .buttonStyle(.plain)
                    .offset(x: -7, y: -7)
                    .help("Remove widget")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if editing, widget.kind.sizes.count > 1 {
                    resizeHandle(widget, rect: rect)
                        .transition(.opacity)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contextMenu {
                ForEach(widget.kind.sizes) { size in
                    Button {
                        resize(widget, to: size)
                    } label: {
                        if size == widget.size { Label(size.title, systemImage: "checkmark") } else { Text(size.title) }
                    }
                }
                Divider()
                Button("Remove widget", role: .destructive) { remove(widget) }
                Button(editing ? "Done editing" : "Edit widgets") {
                    withAnimation(motion) { editing.toggle(); showsGallery = false }
                }
            }
    }

    private func resizeHandle(_ widget: PlacedWidget, rect: CGRect) -> some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(NonnaTheme.ink)
            .frame(width: 22, height: 22)
            .background(NonnaTheme.raisedPaper, in: Circle())
            .overlay { Circle().stroke(NonnaTheme.terracotta.opacity(0.6), lineWidth: 0.8) }
            .padding(6)
            .contentShape(Rectangle())
            .help("Drag to resize")
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if resizing != widget.id {
                            resizing = widget.id
                            resizeStart = rect.size
                        }
                        let columns = (resizeStart.width + value.translation.width + Self.gap) / (unitWidth + Self.gap)
                        let rows = (resizeStart.height + value.translation.height + Self.gap) / (Self.rowHeight + Self.gap)
                        let best = widget.kind.sizes.min {
                            abs(Double($0.columns) - columns) + abs(Double($0.rows) - rows)
                                < abs(Double($1.columns) - columns) + abs(Double($1.rows) - rows)
                        } ?? widget.size
                        if best != widget.size { resize(widget, to: best) }
                    }
                    .onEnded { _ in resizing = nil }
            )
    }

    private func dragGesture(_ widget: PlacedWidget, rect: CGRect, slots: [UUID: GridSlot]) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("board"))
            .onChanged { value in
                guard resizing == nil else { return }
                if dragging != widget.id {
                    dragging = widget.id
                    dragOrigin = rect.origin
                    lastSwap = nil
                }
                // The held widget follows the pointer exactly, with no animation in the way.
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { dragOffset = value.translation }
                // Over another widget: take its place. Wait until the pointer leaves the one
                // just swapped with, so two widgets of different sizes don't flicker back and forth.
                let target = widgets.first { other in
                    other.id != widget.id && slots[other.id].map { frame($0).contains(value.location) } == true
                }
                guard let target else { lastSwap = nil; return }
                guard target.id != lastSwap,
                      let from = widgets.firstIndex(where: { $0.id == widget.id }),
                      let to = widgets.firstIndex(where: { $0.id == target.id }) else { return }
                lastSwap = target.id
                // The others slide out of the way.
                withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.12)) {
                    setWidgets { list in
                        let moving = list.remove(at: from)
                        list.insert(moving, at: to)
                    }
                }
            }
            .onEnded { _ in
                withAnimation(motion) {
                    dragging = nil
                    dragOffset = .zero
                }
                lastSwap = nil
            }
    }

    private func add(_ kind: StatWidget, _ size: WidgetSize) {
        withAnimation(motion) {
            setWidgets { $0.append(PlacedWidget(kind: kind, size: size)) }
            editing = true
        }
    }

    private func remove(_ widget: PlacedWidget) {
        withAnimation(motion) { setWidgets { $0.removeAll { $0.id == widget.id } } }
    }

    private func resize(_ widget: PlacedWidget, to size: WidgetSize) {
        withAnimation(motion) {
            setWidgets { list in
                if let index = list.firstIndex(where: { $0.id == widget.id }) { list[index].size = size }
            }
        }
    }
}

// MARK: - Gallery

/// Every widget in a strip above the board, with the sizes it comes in. Click a size to add it.
private struct WidgetGallery: View {
    let onAdd: (StatWidget, WidgetSize) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 10) {
            ForEach(StatWidget.allCases) { kind in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: kind.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(NonnaTheme.terracotta)
                        .frame(width: 30, height: 30)
                        .background(NonnaTheme.terracotta.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(kind.title)
                                .font(.system(size: 12, weight: .semibold))
                            Text(kind.detail)
                                .font(.system(size: 10))
                                .foregroundStyle(NonnaTheme.secondaryInk)
                                .lineLimit(1)
                        }
                        HStack(spacing: 5) {
                            ForEach(kind.sizes) { size in
                                SizeChip(size: size) { onAdd(kind, size) }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .frame(width: 214)
                .background(NonnaTheme.raisedPaper.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.6) }
            }
            }
            .padding(12)
        }
        .scrollIndicators(.visible)
        .background(NonnaTheme.sunken.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct SizeChip: View {
    let size: WidgetSize
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                // A little picture of the shape: one cell, two wide, a square or the full row.
                RoundedRectangle(cornerRadius: 1.5)
                    .frame(width: CGFloat(size.columns) * 4 + CGFloat(size.columns - 1), height: CGFloat(size.rows) * 4 + CGFloat(size.rows - 1))
                Text(size.short)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(hovering ? NonnaTheme.onAccent : NonnaTheme.ink)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(hovering ? NonnaTheme.terracotta : NonnaTheme.paper, in: Capsule())
            .overlay { Capsule().stroke(NonnaTheme.line, lineWidth: 0.6) }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Add \(size.title.lowercased())")
    }
}

// MARK: - Widgets

struct StatWidgetView: View {
    @Environment(AppModel.self) private var model
    let kind: StatWidget
    let size: WidgetSize
    let onMetric: (DashboardMetric) -> Void

    private var analytics: AnalyticsSnapshot { model.analytics }

    var body: some View {
        Group {
            switch kind {
            case .today: today
            case .thisWeek: thisWeek
            case .plan: plan
            case .focusScore: focusScore
            case .mood: mood
            case .peakHours: peakHours
            case .streak: streak
            case .focusTotal, .completed, .daysUsed, .breakTime, .breakOvertime: metric
            case .dailyFocus: size == .medium ? AnyView(miniDays) : AnyView(full(DashboardView(part: .dailyFocus)))
            case .hoursByWeek: size == .medium ? AnyView(miniWeeks) : AnyView(full(DashboardView(part: .hoursByWeek)))
            case .timeByList: size == .medium ? AnyView(miniLists) : AnyView(full(DashboardView(part: .timeByList)))
            case .consistency: full(DashboardView(part: .consistency))
            case .weekRecap: size == .small ? AnyView(recapSmall(week: true)) : AnyView(full(WeekDashboardRow(), center: true))
            case .yearRecap: size == .small ? AnyView(recapSmall(week: false)) : AnyView(full(YearDashboardRow(), center: true))
            case .trends: full(InsightsSection(only: .trends))
            case .rhythm: full(InsightsSection(only: .rhythm))
            case .quality: full(InsightsSection(only: .quality))
            case .breaks: full(InsightsSection(only: .breaks))
            }
        }
    }

    /// A full card from elsewhere in the app, without its own card behind it.
    private func full<Content: View>(_ content: Content, center: Bool = false) -> some View {
        content
            .environment(\.cardChrome, false)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: center ? .leading : .topLeading)
            .frame(maxHeight: center ? .infinity : nil)
    }

    // MARK: Pieces

    private func heading(_ trailing: String? = nil) -> some View {
        HStack(spacing: 5) {
            Image(systemName: kind.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NonnaTheme.terracotta)
            Text(kind.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NonnaTheme.secondaryInk)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
        }
    }

    private func value(_ text: String, size points: CGFloat = 30) -> some View {
        Text(text)
            .font(.system(size: points, weight: .semibold).monospacedDigit())
            .foregroundStyle(NonnaTheme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(.numericText())
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(NonnaTheme.secondaryInk)
            .lineLimit(2)
    }

    private func padded<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Today

    private var todaySeconds: Int {
        let today = Calendar.current.startOfDay(for: Date())
        return analytics.recentDays.first { $0.day == today }?.seconds ?? 0
    }

    private var today: some View {
        let goal = max(1, model.settings.dailyGoalMinutes * 60)
        let progress = min(1, Double(todaySeconds) / Double(goal))
        let ring = ZStack {
            Circle().stroke(NonnaTheme.line, lineWidth: 6)
            Circle().trim(from: 0, to: progress)
                .stroke(NonnaTheme.terracotta, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        return padded {
            heading()
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: 14) {
                if size == .medium {
                    ring.frame(width: 74, height: 74)
                }
                VStack(alignment: .leading, spacing: 3) {
                    value(todaySeconds.focusDurationString)
                    caption("of \(model.settings.dailyGoalMinutes.minutesString) goal")
                }
                if size == .small {
                    Spacer(minLength: 0)
                }
            }
            if size == .small {
                ProgressView(value: progress)
                    .tint(NonnaTheme.terracotta)
            }
        }
    }

    // MARK: This week

    private var thisWeek: some View {
        let totals = WeeklyTotals.calculate(sessions: model.sessions, weeks: 8)
        let now = totals.thisWeek?.seconds ?? 0
        let before = totals.lastWeekToDateSeconds
        let change = before > 0 ? Int((Double(now - before) / Double(before) * 100).rounded()) : nil
        let peak = max(1, totals.weeks.map(\.seconds).max() ?? 1)
        return padded {
            heading()
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    value(now.focusDurationString)
                    caption(change.map { $0 >= 0 ? "\($0)% more than last week" : "\(-$0)% less than last week" } ?? "Since Monday")
                }
                if size == .medium {
                    Spacer(minLength: 0)
                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(totals.weeks) { week in
                            Capsule()
                                .fill(week.id == totals.thisWeek?.id ? NonnaTheme.terracotta : NonnaTheme.terracotta.opacity(0.3))
                                .frame(width: 9, height: max(4, 70 * CGFloat(week.seconds) / CGFloat(peak)))
                        }
                    }
                    .frame(height: 70, alignment: .bottom)
                    .help("The last 8 weeks")
                }
            }
        }
    }

    // MARK: Plan

    private var plan: some View {
        padded {
            heading()
            Spacer(minLength: 0)
            if let plan = model.focusPlan {
                value("\(plan.level.focusMinutes)m", size: size == .small ? 30 : 34)
                caption("Level \(plan.levelIndex + 1) of \(plan.levels.count)\(size == .medium ? ", aiming for \(plan.levels.last?.focusMinutes ?? plan.level.focusMinutes) minutes" : "")")
                if size == .medium {
                    HStack(spacing: 3) {
                        ForEach(plan.levels.indices, id: \.self) { index in
                            Capsule()
                                .fill(index <= plan.levelIndex ? NonnaTheme.terracotta : NonnaTheme.line)
                                .frame(height: 5)
                        }
                    }
                }
            } else {
                value("\(model.settings.focusMinutes)m")
                Button("Build a focus plan") { model.progressTab = 2 }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NonnaTheme.terracotta)
            }
        }
    }

    // MARK: Focus score

    @ViewBuilder
    private var focusScore: some View {
        if size == .extraLarge {
            full(FocusScoreCard())
        } else {
            let week = model.focusScoreHistory(days: 7)
            let score = week.last?.score
            padded {
                heading()
                HStack(spacing: 14) {
                    FocusScoreRing(score: score?.total, size: size == .small ? 84 : 104, lineWidth: 8)
                    if size == .medium {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(score.map { FocusScore.label(for: $0.total) } ?? "No score yet")
                                .font(.system(size: 16, weight: .semibold))
                            caption(score == nil ? "Finish a block today to get one." : "Today, out of 100")
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: size == .small ? .center : .leading)
            }
        }
    }

    // MARK: Mood

    @ViewBuilder
    private var mood: some View {
        if size == .extraLarge {
            full(MoodCard())
        } else {
            let todayCheckIn = model.todaysCheckIn
            let calendar = Calendar.current
            let recent: [(Date, MoodCheckIn?)] = (0..<7).reversed().compactMap { offset in
                guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: Date())) else { return nil }
                return (day, model.moodCheckIns.last { calendar.isDate($0.date, inSameDayAs: day) })
            }
            padded {
                heading()
                HStack(spacing: 14) {
                    MoodBloom(valence: todayCheckIn.map { $0.valence ?? MoodScale.valence(forLevel: $0.level) } ?? 0.62, turning: false)
                        .frame(width: size == .small ? 46 : 58, height: size == .small ? 46 : 58)
                        .saturation(todayCheckIn == nil ? 0.2 : 1)
                        .opacity(todayCheckIn == nil ? 0.6 : 1)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(todayCheckIn.map { MoodScale.title($0.level) } ?? "Not checked in")
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(2)
                        if size == .medium {
                            HStack(spacing: 6) {
                                ForEach(recent, id: \.0) { day, checkIn in
                                    Circle()
                                        .fill(checkIn.map { MoodColor.color(valence: $0.valence ?? MoodScale.valence(forLevel: $0.level)) } ?? NonnaTheme.line)
                                        .frame(width: 12, height: 12)
                                        .help(day.formatted(.dateTime.weekday(.wide)) + (checkIn.map { ": " + MoodScale.title($0.level) } ?? ""))
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                Button(todayCheckIn == nil ? "Check in" : "Update") { model.showsMoodCheckIn = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NonnaTheme.terracotta)
            }
        }
    }

    // MARK: Peak hours

    @ViewBuilder
    private var peakHours: some View {
        if size == .extraLarge {
            full(PeakHoursCard())
        } else {
            let peak = PeakHours.calculate(sessions: model.sessions)
            padded {
                heading()
                Spacer(minLength: 0)
                if let best = peak.best, peak.hasEnoughData {
                    value("\(best.start.clockHourLabel) to \(best.end.clockHourLabel)", size: 24)
                    caption(peak.hardest.map { "Toughest: \($0.start.clockHourLabel) to \($0.end.clockHourLabel)" } ?? "Your best two hours")
                } else {
                    caption("Shows after \(PeakHours.minimumBlocks) blocks. You've finished \(peak.blockCount).")
                }
            }
        }
    }

    // MARK: Streak

    private var streak: some View {
        let days = analytics.recentDays.suffix(14)
        return Button { onMetric(.rhythm) } label: {
            padded {
                heading()
                Spacer(minLength: 0)
                value("\(analytics.currentStreak) \(analytics.currentStreak == 1 ? "day" : "days")")
                caption("Best: \(analytics.longestStreak) \(analytics.longestStreak == 1 ? "day" : "days")")
                if size == .medium {
                    HStack(spacing: 4) {
                        ForEach(Array(days)) { day in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(day.seconds > 0 ? NonnaTheme.sage : NonnaTheme.line)
                                .frame(height: 12)
                                .help(day.day.formatted(.dateTime.month(.abbreviated).day()))
                        }
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Metrics

    private var metric: some View {
        let breaks = model.breakSessions
        let (text, note): (String, String) = switch kind {
        case .focusTotal:
            (analytics.totalFocusSeconds.focusDurationString,
             analytics.overtimeSeconds >= 60 ? "Includes \(analytics.overtimeSeconds.focusDurationString) past the bell" : "Across every list")
        case .completed:
            ("\(analytics.completedSessions)", analytics.endedEarlySessions > 0 ? "Plus \(analytics.endedEarlySessions) ended early" : "Full planned blocks")
        case .daysUsed:
            ("\(analytics.usedDays)", "Days with any focus")
        case .breakTime:
            (breaks.reduce(0) { $0 + $1.restedSeconds }.focusDurationString, "All recorded breaks")
        default:
            (breaks.reduce(0) { $0 + $1.overtimeSeconds }.focusDurationString, "Past planned length")
        }
        return Button { if let metric = kind.metric { onMetric(metric) } } label: {
            padded {
                heading()
                Spacer(minLength: 0)
                value(text)
                caption(note)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Click for details")
    }

    // MARK: Mini charts

    private var miniDays: some View {
        let days = analytics.recentDays
        let peak = max(1, days.map(\.seconds).max() ?? 1)
        let total = days.reduce(0) { $0 + $1.seconds }
        return padded {
            heading("14 days")
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    value(total.focusDurationString, size: 24)
                    caption("Last 14 days")
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(days) { day in
                        Capsule()
                            .fill(NonnaTheme.terracotta.opacity(day.seconds > 0 ? 1 : 0.25))
                            .frame(width: 7, height: max(3, 70 * CGFloat(day.seconds) / CGFloat(peak)))
                            .help("\(day.day.formatted(.dateTime.weekday(.abbreviated).day())): \(day.seconds.focusDurationString)")
                    }
                }
                .frame(height: 70, alignment: .bottom)
            }
        }
    }

    private var miniWeeks: some View {
        let totals = WeeklyTotals.calculate(sessions: model.sessions)
        let peak = max(1, totals.weeks.map(\.seconds).max() ?? 1)
        return padded {
            heading("12 weeks")
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    value((totals.averageSeconds ?? 0).focusDurationString, size: 24)
                    caption("Weekly average")
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(totals.weeks) { week in
                        Capsule()
                            .fill(NonnaTheme.terracotta.opacity(week.id == totals.thisWeek?.id ? 1 : 0.55))
                            .frame(width: 8, height: max(3, 70 * CGFloat(week.seconds) / CGFloat(peak)))
                            .help("Week of \(week.start.formatted(.dateTime.month(.abbreviated).day())): \(week.seconds.focusDurationString)")
                    }
                }
                .frame(height: 70, alignment: .bottom)
            }
        }
    }

    private var miniLists: some View {
        let lists = Array(analytics.taskTotals.prefix(3))
        let peak = max(1, lists.first?.seconds ?? 1)
        return padded {
            heading()
            if lists.isEmpty {
                Spacer(minLength: 0)
                caption("Finish a session to see time by list.")
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(lists) { list in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(list.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                Spacer()
                                Text(list.seconds.focusDurationString)
                                    .font(.system(size: 10).monospacedDigit())
                                    .foregroundStyle(NonnaTheme.secondaryInk)
                            }
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(NonnaTheme.taskColor(for: list.colorHex))
                                    .frame(width: proxy.size.width * CGFloat(list.seconds) / CGFloat(peak))
                            }
                            .frame(height: 5)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: Recaps

    private func recapSmall(week: Bool) -> some View {
        padded {
            heading()
            Spacer(minLength: 0)
            caption(week ? "Last week's totals and one suggestion" : "Your year in a few cards")
            Button("Open") {
                if week {
                    model.weekSheetStart = model.lastWeekStart
                } else {
                    model.yearSheet = Calendar.current.component(.year, from: Date())
                }
            }
            .buttonStyle(NonnaButtonStyle(prominent: false))
        }
    }
}
