import AppKit
import SwiftUI

// MARK: - Picker

/// The grid of looks, shared by Settings and the welcome screen. Picking one restyles
/// the whole app immediately, with a soft crossfade.
struct ThemePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var columns = 5

    private var selected: ThemeChoice { ThemeChoice(rawValue: model.settings.themeID) ?? .obsidian }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: columns), spacing: 14) {
                ForEach(ThemeChoice.allCases) { choice in
                    ThemeSwatchButton(choice: choice, custom: model.settings.customTheme, isSelected: selected == choice) {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) {
                            model.updateSettings { $0.themeID = choice.rawValue }
                        }
                    }
                }
            }
            if selected == .custom {
                CustomThemeEditor()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(reduceMotion ? nil : NonnaMotion.selection, value: selected)
    }
}

private struct ThemeSwatchButton: View {
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

    private var spec: CustomThemeSpec { model.settings.customTheme }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("BUILD YOUR THEME")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(NonnaTheme.terracotta)
                Spacer()
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
        NonnaCard {
            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Appearance", systemImage: "paintpalette")
                        .font(.system(size: 17, weight: .bold))
                    Spacer()
                    Text("Changes apply instantly, everywhere: windows, menu bar panel, Cinema and celebrations.")
                        .font(.system(size: 10))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
                Divider().overlay(NonnaTheme.line)
                ThemePicker()
            }
        }
    }
}

// MARK: - Welcome

/// Shown once on a fresh install: pick a look, then optionally start a focus plan.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @State private var appeared = false
    let onBuildPlan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if page == 0 { themePage.transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .offset(x: -40)))) }
                else { planPage.transition(.opacity.combined(with: .offset(x: 40))) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<2, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? NonnaTheme.terracotta : NonnaTheme.strongLine)
                            .frame(width: index == page ? 22 : 8, height: 4)
                    }
                }
                Spacer()
                if page == 0 {
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.1)) { page = 1 }
                    } label: {
                        Label("Continue", systemImage: "chevron.right")
                    }
                    .buttonStyle(NonnaButtonStyle())
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Maybe later") { model.completeOnboarding() }
                        .buttonStyle(NonnaButtonStyle(prominent: false))
                    Button {
                        model.completeOnboarding()
                        onBuildPlan()
                    } label: {
                        Label("Build my focus plan", systemImage: "sparkles")
                    }
                    .buttonStyle(NonnaButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
            }
            .animation(reduceMotion ? nil : NonnaMotion.selection, value: page)
        }
        .padding(38)
        .frame(width: 820, height: 640)
        .background {
            ZStack {
                NonnaTheme.cream
                RadialGradient(colors: [NonnaTheme.terracotta.opacity(0.14), .clear], center: .topLeading, startRadius: 10, endRadius: 520)
            }
        }
        .foregroundStyle(NonnaTheme.ink)
        .preferredColorScheme(NonnaTheme.colorScheme)
        .interactiveDismissDisabled()
        .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.9)) { appeared = true } }
    }

    private var themePage: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 10) {
                Text("WELCOME TO POMOFOCUS")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2.4)
                    .foregroundStyle(NonnaTheme.terracotta)
                Text("Make it yours.")
                    .font(.system(size: 44, weight: .regular, design: .serif))
                    .tracking(-0.8)
                Text("Pick a look. You can change it, or build your own, any time in Settings.")
                    .font(.system(size: 14))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 12)
            ThemePicker()
                .opacity(appeared ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.9).delay(0.2), value: appeared)
        }
    }

    private var planPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("ONE MORE THING")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(2.4)
                .foregroundStyle(NonnaTheme.terracotta)
            Text("Want help rebuilding your focus?")
                .font(.system(size: 40, weight: .regular, design: .serif))
                .tracking(-0.6)
                .fixedSize(horizontal: false, vertical: true)
            Text("Answer eight quick questions and Pomofocus builds a plan that starts where your attention is today and climbs, five minutes at a time, to the blocks you want. Like 45 minutes of focus with 15-minute breaks.")
                .font(.system(size: 14))
                .foregroundStyle(NonnaTheme.secondaryInk)
                .frame(maxWidth: 600, alignment: .leading)
            HStack(spacing: 14) {
                welcomeFact("figure.stairs", "A ladder you climb", "Earn five more minutes at a time.")
                welcomeFact("leaf", "Breaks that reset you", "Low-stimulation, no feeds.")
                welcomeFact("gift", "A reward at the end", "Saved for after the last block.")
            }
            Spacer(minLength: 0)
        }
    }

    private func welcomeFact(_ icon: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(NonnaTheme.terracotta)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(NonnaTheme.secondaryInk)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NonnaTheme.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }
    }
}
