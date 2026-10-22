import SwiftUI

/// The "what are you working on?" line on the timer. Typing in it should feel alive: the
/// caret and border take the theme's colour, the glow breathes a little with every
/// keystroke, and Return begins the block.
struct IntentionField: View {
    enum Style { case pill, underline }

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var style: Style = .pill
    @FocusState private var focused: Bool
    @State private var keystrokes = 0

    private var accent: Color { NonnaTheme.terracotta }
    private var canBegin: Bool { model.status == .idle && model.phase == .focus && !model.isBreathing }

    var body: some View {
        @Bindable var model = model
        let field = ZStack(alignment: .leading) {
            if model.intention.isEmpty {
                Text(style == .pill ? "What are you working on?" : "e.g. Draft the opening section")
                    .foregroundStyle(NonnaTheme.secondaryInk.opacity(focused ? 0.45 : 0.62))
                    .allowsHitTesting(false)
            }
            TextField("", text: $model.intention, axis: style == .underline ? .vertical : .horizontal)
                .textFieldStyle(.plain)
                .foregroundStyle(NonnaTheme.ink)
                .lineLimit(style == .underline ? 1...3 : 1...1)
                .focused($focused)
                .disabled(model.phase != .focus)
                .onSubmit {
                    if canBegin { model.start() }
                    focused = false
                }
                .onExitCommand { focused = false }
                .onChange(of: model.intention) { _, _ in
                    if focused { keystrokes += 1 }
                }
        }
        .tint(accent)

        Group {
            switch style {
            case .pill: pill(field)
            case .underline: underline(field)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: focused)
    }

    // MARK: Styles

    private func pill(_ field: some View) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil.line")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(focused ? accent : NonnaTheme.secondaryInk.opacity(0.7))
            field
                .font(.system(size: 15, weight: .medium))
            hint
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: 460)
        .frame(height: 46)
        .background(focused ? NonnaTheme.paper : NonnaTheme.raisedPaper.opacity(0.82),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .keyframeAnimator(initialValue: 0.0, trigger: reduceMotion ? 0 : keystrokes) { content, glow in
            content
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(focused ? accent.opacity(0.55 + 0.4 * glow) : NonnaTheme.line, lineWidth: focused ? 1.2 : 0.8)
                }
                .shadow(color: focused ? accent.opacity(0.16 + 0.22 * glow) : .clear, radius: 10 + 6 * glow)
        } keyframes: { _ in
            LinearKeyframe(1.0, duration: 0.05)
            CubicKeyframe(0.0, duration: 0.5)
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    private func underline(_ field: some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                field
                    .font(.system(size: 18, weight: .medium))
                hint
            }
            ZStack(alignment: .leading) {
                Rectangle().fill(NonnaTheme.line).frame(height: 1)
                Rectangle()
                    .fill(accent)
                    .frame(height: 1.5)
                    .scaleEffect(x: focused ? 1 : 0, anchor: .leading)
                    .keyframeAnimator(initialValue: 0.0, trigger: reduceMotion ? 0 : keystrokes) { bar, glow in
                        bar.shadow(color: accent.opacity(0.25 + 0.5 * glow), radius: 2 + 5 * glow)
                    } keyframes: { _ in
                        LinearKeyframe(1.0, duration: 0.05)
                        CubicKeyframe(0.0, duration: 0.5)
                    }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.15), value: focused)
        }
    }

    @ViewBuilder
    private var hint: some View {
        if focused, canBegin {
            Text("↩ Begin")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(accent)
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(accent.opacity(0.12), in: Capsule())
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .help("Press Return to begin focusing")
        }
    }
}
