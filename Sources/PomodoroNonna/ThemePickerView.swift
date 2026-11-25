import AppKit
import SwiftUI

// MARK: - Picker

/// The grid of looks in Settings: four up front, the rest under More themes. Picking one restyles
/// the whole app immediately, with a soft crossfade.
struct ThemePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var columns = 5
    @Environment(\.compactLayout) private var compact

    /// nil while a theme from a code is in use.
    private var selected: ThemeChoice? { ThemeChoice(rawValue: model.settings.themeID) }
    @State private var code = ""
    @State private var codeMessage: (ok: Bool, text: String)?
    @State private var showsMore = false

    /// Four looks up front (and yours, if it's another); the rest under More themes.
    private var featured: [ThemeChoice] {
        FeaturedThemes.choices + (selected.map { FeaturedThemes.choices.contains($0) ? [] : [$0] } ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: compact ? 3 : columns), spacing: 14) {
                ForEach(featured) { choice in
                    ThemeSwatchButton(choice: choice, custom: model.settings.customTheme, isSelected: selected == choice) {
                        ThemeCrossfade.perform(reduceMotion: reduceMotion) {
                            model.updateSettings { $0.themeID = choice.rawValue }
                        }
                    }
                }
            }
            Button {
                withAnimation(reduceMotion ? nil : NonnaMotion.selection) { showsMore.toggle() }
            } label: {
                Label(showsMore ? "Fewer themes" : "More themes", systemImage: showsMore ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(NonnaTheme.terracotta)
            if showsMore {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: compact ? 3 : columns), spacing: 14) {
                // Limited editions show up in their season, or while they're in use.
                ForEach(ThemeChoice.allCases.filter { ($0.isAvailable() || $0 == selected) && !featured.contains($0) }) { choice in
                    ThemeSwatchButton(choice: choice, custom: model.settings.customTheme, isSelected: selected == choice) {
                        ThemeCrossfade.perform(reduceMotion: reduceMotion) {
                            model.updateSettings { $0.themeID = choice.rawValue }
                        }
                    }
                }
                // Themes added from codes, rare ones first.
                ForEach(model.settings.savedThemes.sorted { $0.isRare && !$1.isRare }) { theme in
                    SavedThemeSwatch(theme: theme, isSelected: model.settings.themeID == theme.themeID) {
                        ThemeCrossfade.perform(reduceMotion: reduceMotion) {
                            model.updateSettings { $0.themeID = theme.themeID }
                        }
                    }
                }
            }
            }
            if selected == .custom {
                CustomThemeEditor()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            codeField
        }
        .animation(reduceMotion ? nil : NonnaMotion.selection, value: selected)
    }
}

extension ThemePicker {
    /// Paste a code from a friend, or a rare one from the developer.
    var codeField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "ticket")
                    .foregroundStyle(NonnaTheme.secondaryInk)
                TextField("Paste a theme code", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addCode)
                Button("Add", action: addCode)
                    .buttonStyle(NonnaButtonStyle(prominent: false))
                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let codeMessage {
                Text(codeMessage.text)
                    .font(.system(size: 11))
                    .foregroundStyle(codeMessage.ok ? NonnaTheme.sage : NonnaTheme.alert)
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    func addCode() {
        let result = model.addTheme(fromCode: code)
        codeMessage = (result.ok, result.message)
        if result.ok { code = "" }
    }
}

/// A theme from a code: a preview, its name and note, and a Rare or Shared tag.
private struct SavedThemeSwatch: View {
    @Environment(AppModel.self) private var model
    let theme: SharedTheme
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                ThemeMiniPreview(theme: ResolvedTheme(theme.spec.palette))
                    .frame(height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? NonnaTheme.terracotta : (theme.isRare ? Color(hex: "C9A55A") : NonnaTheme.line),
                                    lineWidth: isSelected ? 2 : (theme.isRare ? 1.2 : 0.8))
                    }
                    .overlay(alignment: .topLeading) {
                        Label(theme.isRare ? "Rare" : "Shared", systemImage: theme.isRare ? "seal.fill" : "person.2")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.isRare ? Color(hex: "1A1408") : .white)
                            .padding(.horizontal, 7)
                            .frame(height: 18)
                            .background(theme.isRare ? Color(hex: "D9B86A") : Color.black.opacity(0.55), in: Capsule())
                            .padding(7)
                    }
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(theme.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text(theme.note ?? "From a theme code")
                            .font(.system(size: 10))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(NonnaTheme.terracotta)
                    }
                }
            }
            .scaleEffect(hovering && !isSelected ? 1.02 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(NonnaMotion.quick, value: hovering)
        .help(theme.note ?? theme.name)
        .contextMenu {
            if !theme.isRare {
                Button("Copy code") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ThemeCodes.code(for: theme), forType: .string)
                }
            }
            Button("Remove", role: .destructive) { model.removeSavedTheme(theme.id) }
        }
        .accessibilityLabel("\(theme.name), \(theme.isRare ? "rare" : "shared") theme")
    }
}

struct ThemeSwatchButton: View {
    let choice: ThemeChoice
    let custom: CustomThemeSpec
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                preview
                    .frame(height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? NonnaTheme.terracotta : NonnaTheme.line, lineWidth: isSelected ? 2 : 0.8)
                    }
                    .shadow(color: isSelected ? NonnaTheme.terracotta.opacity(0.3) : .clear, radius: 10)
                    .overlay(alignment: .topLeading) {
                        if choice.isLimitedEdition {
                            Text("Limited")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .frame(height: 18)
                                .background(Color(hex: "B4501E"), in: Capsule())
                                .padding(7)
                                .help("A limited edition, here for the fall")
                        }
                    }
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(choice.title).font(.system(size: 12, weight: .semibold))
                        Text(choice.subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(NonnaTheme.terracotta)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .scaleEffect(hovering && !isSelected ? 1.02 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(NonnaMotion.quick, value: hovering)
        .accessibilityLabel("\(choice.title) theme")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var preview: some View {
        switch choice {
        case .system:
            ZStack {
                ThemeMiniPreview(theme: ResolvedTheme(.ivory))
                ThemeMiniPreview(theme: ResolvedTheme(.obsidian))
                    .mask {
                        GeometryReader { proxy in
                            Path { path in
                                path.move(to: CGPoint(x: proxy.size.width * 0.62, y: 0))
                                path.addLine(to: CGPoint(x: proxy.size.width, y: 0))
                                path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
                                path.addLine(to: CGPoint(x: proxy.size.width * 0.38, y: proxy.size.height))
                                path.closeSubpath()
                            }
                        }
                    }
            }
        case .custom:
            ThemeMiniPreview(theme: ResolvedTheme(custom.palette))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "paintbrush.pointed.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: custom.palette.onAccent))
                        .frame(width: 22, height: 22)
                        .background(Color(hex: custom.accent), in: Circle())
                        .padding(7)
                }
        default:
            ThemeMiniPreview(theme: ResolvedTheme(choice.palette ?? .obsidian))
        }
    }
}

/// A tiny picture of the app in a given palette: sidebar, card, dial, button.
struct ThemeMiniPreview: View {
    let theme: ResolvedTheme

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(theme.sunken)
                .frame(width: 16)
                .overlay(alignment: .top) {
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(theme.ink).frame(width: 7, height: 7)
                        ForEach(0..<3, id: \.self) { _ in Circle().fill(theme.secondaryInk.opacity(0.6)).frame(width: 4, height: 4) }
                    }
                    .padding(.top, 8)
                }
            ZStack {
                theme.background
                RadialGradient(colors: [theme.accent.opacity(0.18), .clear], center: .topTrailing, startRadius: 2, endRadius: 90)
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(theme.raised)
                        Circle().stroke(theme.line, lineWidth: 1)
                        Circle()
                            .trim(from: 0, to: 0.62)
                            .stroke(theme.accent, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .padding(1)
                        Circle().fill(theme.accent.opacity(0.22)).padding(9)
                    }
                    .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 5) {
                        Capsule().fill(theme.ink).frame(width: 40, height: 5)
                        Capsule().fill(theme.secondaryInk.opacity(0.7)).frame(width: 30, height: 4)
                        HStack(spacing: 4) {
                            Capsule().fill(theme.accent).frame(width: 24, height: 10)
                            Capsule().fill(theme.raised).overlay(Capsule().stroke(theme.line, lineWidth: 0.8)).frame(width: 18, height: 10)
                        }
                        HStack(spacing: 3) {
                            Circle().fill(theme.rest).frame(width: 5, height: 5)
                            Circle().fill(theme.longRest).frame(width: 5, height: 5)
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Custom editor

private struct CustomThemeEditor: View {
    @Environment(AppModel.self) private var model
    @State private var copied = false

    private var spec: CustomThemeSpec { model.settings.customTheme }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Build your theme")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.shareCodeForCustomTheme(), forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.6))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Code copied" : "Share this theme", systemImage: copied ? "checkmark" : "square.and.arrow.up")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(NonnaTheme.terracotta)
                .help("Copy a code anyone can paste into Settings to get this theme")
                Menu {
                    ForEach(ThemeChoice.allCases.filter { $0.palette != nil }) { choice in
                        Button(choice.title) {
                            guard let palette = choice.palette else { return }
                            update { $0 = CustomThemeSpec(isDark: palette.isDark, background: palette.background, accent: palette.accent, rest: palette.rest) }
                        }
                    }
                } label: {
                    Label("Start from…", systemImage: "square.on.square")
                        .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            HStack(spacing: 18) {
                Picker("Base", selection: Binding(
                    get: { spec.isDark },
                    set: { dark in
                        update { custom in
                            let starter = dark ? CustomThemeSpec() : CustomThemeSpec.lightStarter
                            custom.isDark = dark
                            custom.background = starter.background
                        }
                    }
                )) {
                    Text("Dark").tag(true)
                    Text("Light").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)

                colorWell("Background", \.background)
                colorWell("Focus", \.accent)
                colorWell("Breaks", \.rest)
                Spacer(minLength: 0)
            }

            let contrast = RGB(hex: spec.accent).contrast(with: RGB(hex: spec.background))
            if contrast < 2.2 {
                Label("Your focus colour is hard to see on this background. Try something brighter or darker.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(NonnaTheme.alert)
            } else {
                Text("Surfaces, lines and text are derived for you, so every combination stays readable.")
                    .font(.system(size: 11))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
        }
        .padding(16)
        .background(NonnaTheme.sunken.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }
    }

    private func colorWell(_ title: String, _ key: WritableKeyPath<CustomThemeSpec, String>) -> some View {
        HStack(spacing: 7) {
            ColorPicker(title, selection: Binding(
                get: { Color(hex: spec[keyPath: key]) },
                set: { color in
                    guard let hex = color.sRGBHex, hex != spec[keyPath: key] else { return }
                    update { $0[keyPath: key] = hex }
                }
            ), supportsOpacity: false)
            .labelsHidden()
            Text(title).font(.system(size: 12))
        }
    }

    private func update(_ mutate: (inout CustomThemeSpec) -> Void) {
        model.updateSettings { mutate(&$0.customTheme) }
    }
}

extension Color {
    /// The colour as six-digit sRGB hex, for saving.
    var sRGBHex: String? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return RGB(r: Double(color.redComponent), g: Double(color.greenComponent), b: Double(color.blueComponent)).hex
    }
}

// MARK: - Settings card

struct AppearanceSettingsCard: View {
    var body: some View {
        SettingsCard(title: "Appearance", icon: "paintpalette",
                     summary: ThemeChoice(rawValue: ThemeManager.shared.themeID)?.title ?? "Your own theme") {
            Text("Changes apply instantly, everywhere: windows, menu bar panel, Cinema and celebrations.")
                .font(.system(size: 11))
                .foregroundStyle(NonnaTheme.secondaryInk)
            ThemePicker()
            GlassSetting()
            if ThemeManager.shared.themeID == ThemeChoice.london.rawValue {
                LondonWeatherSettings()
                    .transition(.opacity)
            }
        }
    }
}

/// The Glass slider: from solid paper to clear glass, for the timer, cards and panels.
private struct GlassSetting: View {
    private var glass: Double { ThemeManager.shared.glass }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Glass").font(.system(size: 12, weight: .medium))
                Text("Let the theme show through the timer, cards and panels.")
                    .font(.system(size: 10))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            Spacer(minLength: 12)
            Text("Solid").font(.system(size: 10)).foregroundStyle(NonnaTheme.secondaryInk)
            Slider(value: Binding(get: { ThemeManager.shared.glass }, set: { ThemeManager.shared.glass = $0 }), in: 0...1)
                .frame(width: 180)
                .tint(NonnaTheme.terracotta)
                .accessibilityLabel("Glass")
                .accessibilityValue(glass < 0.01 ? "Solid" : "\(Int((glass * 100).rounded())) percent")
            Text("Glass").font(.system(size: 10)).foregroundStyle(NonnaTheme.secondaryInk)
        }
        .frame(maxWidth: 520, alignment: .leading)
    }
}

/// The London theme's weather: rain on or off, and a storm on top of it.
private struct LondonWeatherSettings: View {
    @AppStorage(LondonWeather.rainKey) private var rain = true
    @AppStorage(LondonWeather.stormKey) private var storm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("London weather")
                .font(.system(size: 13, weight: .semibold))
            row("Rain", "Rain falling over the river, rings on the water.", $rain)
            row("Storm", rain ? "Heavier, windier rain, with lightning in the clouds." : "Needs rain on.", $storm)
                .disabled(!rain)
                .opacity(rain ? 1 : 0.5)
        }
        .padding(16)
        .background(NonnaTheme.sunken.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }
        .frame(maxWidth: 520, alignment: .leading)
    }

    private func row(_ title: String, _ subtitle: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(NonnaTheme.secondaryInk)
            }
            Spacer(minLength: 12)
            Toggle(title, isOn: binding)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

// MARK: - Themes tip

/// The four looks offered first: in the tip on Focus and at the top of the picker.
enum FeaturedThemes {
    static let choices: [ThemeChoice] = [.system, .blackIce, .london, .layla]
}

/// A one-time tip on the Focus screen once you've finished a block.
struct ThemeTip: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("themeTipDone") private var done = false

    var body: some View {
        if !done, model.status == .idle, model.sessions.contains(where: { $0.outcome == .completed }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Make it yours")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Pick a look. More in Settings.")
                            .font(.system(size: 12))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                    }
                    Spacer()
                    Button { done = true } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .accessibilityLabel("Dismiss")
                }
                HStack(spacing: 12) {
                    ForEach(FeaturedThemes.choices) { choice in
                        ThemeSwatchButton(choice: choice, custom: model.settings.customTheme,
                                          isSelected: model.settings.themeID == choice.rawValue) {
                            ThemeCrossfade.perform(reduceMotion: reduceMotion) {
                                model.updateSettings { $0.themeID = choice.rawValue }
                            }
                        }
                    }
                }
                .frame(maxWidth: 520)
            }
            .padding(16)
            .background(NonnaTheme.raisedPaper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NonnaTheme.terracotta.opacity(0.35), lineWidth: 0.8) }
        }
    }
}

// MARK: - Setup

/// Shown once on a fresh install, and again from Settings: one question, how you like to
/// work, then straight into a first block. Everything else waits for the tips and Settings.
struct QuickSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var style: WorkStyle = .classic
    /// Called once setup closes; true when they chose to build a plan.
    let onDone: (_ buildPlan: Bool) -> Void

    var body: some View {
        VStack(spacing: 30) {
            Spacer(minLength: 0)
            Text("How do you like to work?")
                .font(.system(size: 40, weight: .regular, design: .serif))
                .tracking(-0.6)
            Text("You can change this any time. Everything else can wait.")
                .font(.system(size: 15))
                .foregroundStyle(NonnaTheme.secondaryInk)
            HStack(spacing: 14) {
                ForEach(WorkStyle.allCases, id: \.self) { option in
                    OnboardingChoice(icon: option.icon, title: option.title, detail: option.detail, selected: style == option) {
                        withAnimation(reduceMotion ? nil : NonnaMotion.selection) { style = option }
                    }
                }
            }
            Spacer(minLength: 0)
            Button(style == .buildUp ? "Build my plan" : "Start my first block") { finish() }
                .buttonStyle(OnboardingButtonStyle(color: NonnaTheme.terracotta))
                .keyboardShortcut(.defaultAction)
        }
        .padding(48)
        .frame(width: 760, height: 520)
        .background {
            ZStack {
                NonnaTheme.cream
                RadialGradient(colors: [NonnaTheme.terracotta.opacity(0.16), .clear], center: .top, startRadius: 10, endRadius: 480)
            }
        }
        .foregroundStyle(NonnaTheme.ink)
        .tint(NonnaTheme.terracotta)
        .preferredColorScheme(NonnaTheme.colorScheme)
        .interactiveDismissDisabled()
    }

    private func finish() {
        model.updateSettings { settings in
            switch style {
            case .classic, .buildUp:
                settings.focusMinutes = 25
                settings.shortBreakMinutes = 5
                settings.longBreakMinutes = 20
            case .longer:
                settings.focusMinutes = 50
                settings.shortBreakMinutes = 10
                settings.longBreakMinutes = 30
            }
        }
        model.completeOnboarding()
        onDone(style == .buildUp)
        if style != .buildUp {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                model.startFocus()
            }
        }
    }
}

/// The three ways to start, asked on the setup page.
enum WorkStyle: CaseIterable {
    case classic, longer, buildUp

    var title: String {
        switch self {
        case .classic: "Classic"
        case .longer: "Longer blocks"
        case .buildUp: "Build up slowly"
        }
    }

    var detail: String {
        switch self {
        case .classic: "25 minutes of focus, 5 minutes off. The original Pomodoro."
        case .longer: "50 minutes of focus, 10 off. For when you get into a rhythm."
        case .buildUp: "Start where you are today and add five minutes as you go."
        }
    }

    var icon: String {
        switch self {
        case .classic: "timer"
        case .longer: "hourglass"
        case .buildUp: "chart.line.uptrend.xyaxis"
        }
    }
}

/// One of the setup's big choices: an icon, a name and a line under it.
struct OnboardingChoice: View {
    let icon: String
    let title: String
    let detail: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? NonnaTheme.terracotta : NonnaTheme.secondaryInk)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(width: 196, height: 160, alignment: .topLeading)
            .background(selected ? NonnaTheme.raisedPaper : NonnaTheme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? NonnaTheme.terracotta : NonnaTheme.line, lineWidth: selected ? 1.4 : 0.8)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A wide capsule in the theme's accent, like a Mac setup assistant's main button.
struct OnboardingButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(NonnaTheme.onAccent)
            .frame(width: 240, height: 40)
            .background(color, in: Capsule())
            .shadow(color: color.opacity(0.3), radius: 12, y: 4)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}
