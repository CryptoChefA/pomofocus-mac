import SwiftUI

/// The end-of-day wrap-up: what got done, where the time went, and what moves to tomorrow.
struct WrapUpSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onDone: () -> Void
    @State private var summary: AppModel.DayWrapUp?
    /// Leftovers ticked to move to tomorrow; all of them to begin with.
    @State private var moving: Set<UUID> = []
    @State private var appeared = false

    var body: some View {
        let wrap = summary ?? model.wrapUp()
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Wrap up today")
                    .font(.system(size: 30, weight: .regular, design: .serif))
                Text(headline(wrap))
                    .font(.system(size: 13))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }

            HStack(spacing: 0) {
                stat(wrap.focusedSeconds.focusDurationString, "focused")
                divider
                stat("\(wrap.blocks)", wrap.blocks == 1 ? "block" : "blocks")
                divider
                stat("\(wrap.finished.count)", wrap.finished.count == 1 ? "task done" : "tasks done")
            }
            .padding(.vertical, 14)
            .background(NonnaTheme.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !wrap.lists.isEmpty {
                        section("Where the time went") {
                            let top = max(1, wrap.lists.first?.seconds ?? 1)
                            ForEach(wrap.lists, id: \.name) { item in
                                HStack(spacing: 10) {
                                    Circle().fill(NonnaTheme.taskColor(for: item.colorHex)).frame(width: 7, height: 7)
                                    Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                        .frame(width: 140, alignment: .leading)
                                    GeometryReader { proxy in
                                        Capsule().fill(NonnaTheme.taskColor(for: item.colorHex).opacity(0.75))
                                            .frame(width: appeared ? proxy.size.width * Double(item.seconds) / Double(top) : 0, height: 6)
                                            .frame(maxHeight: .infinity, alignment: .center)
                                    }
                                    .frame(height: 12)
                                    Text(item.seconds.focusDurationString)
                                        .font(.system(size: 11).monospacedDigit())
                                        .foregroundStyle(NonnaTheme.secondaryInk)
                                        .frame(width: 60, alignment: .trailing)
                                }
                            }
                        }
                    }

                    if !wrap.finished.isEmpty {
                        section("Done") {
                            ForEach(wrap.finished) { todo in
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(NonnaTheme.terracotta)
                                    Text(todo.title).font(.system(size: 12)).lineLimit(1)
                                }
                            }
                        }
                    }

                    section(wrap.leftovers.isEmpty ? "Nothing left over" : "Move to tomorrow") {
                        if wrap.leftovers.isEmpty {
                            Text("Everything planned or due today is done.")
                                .font(.system(size: 12))
                                .foregroundStyle(NonnaTheme.secondaryInk)
                        }
                        ForEach(wrap.leftovers) { todo in
                            Toggle(isOn: Binding(
                                get: { moving.contains(todo.id) },
                                set: { on in if on { moving.insert(todo.id) } else { moving.remove(todo.id) } }
                            )) {
                                HStack(spacing: 8) {
                                    Text(todo.title).font(.system(size: 12)).lineLimit(1)
                                    if let left = Optional(model.minutesLeft(on: todo)), left > 0 {
                                        Text("\(left.minutesString) left")
                                            .font(.system(size: 11).monospacedDigit())
                                            .foregroundStyle(NonnaTheme.secondaryInk)
                                    }
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 340)

            HStack {
                Button("Close") {
                    model.markWrappedUp()
                    onDone()
                }
                .buttonStyle(NonnaButtonStyle(prominent: false))
                .keyboardShortcut(.cancelAction)
                Spacer()
                if !moving.isEmpty {
                    Button("Move \(moving.count) to tomorrow") {
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.35)) {
                            model.moveToTomorrow(Array(moving))
                        }
                        onDone()
                    }
                    .buttonStyle(NonnaButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(30)
        .frame(width: 540)
        .background(NonnaTheme.cream)
        .foregroundStyle(NonnaTheme.ink)
        .preferredColorScheme(NonnaTheme.colorScheme)
        .onAppear {
            // Take one snapshot so ticking boxes doesn't reshuffle the list.
            let wrap = model.wrapUp()
            summary = wrap
            moving = Set(wrap.leftovers.map(\.id))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.6).delay(0.15)) { appeared = true }
        }
    }

    private func headline(_ wrap: AppModel.DayWrapUp) -> String {
        if wrap.blocks == 0 && wrap.finished.isEmpty { return "A quiet day. Tomorrow starts with one block." }
        if wrap.leftovers.isEmpty { return "Everything you planned is done. Nice work." }
        return "Here's your day. Pick what carries over, then you're done."
    }

    private var divider: some View {
        Rectangle().fill(NonnaTheme.line).frame(width: 0.8, height: 34)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(NonnaTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            content()
        }
    }
}

/// A quiet evening nudge on the timer screen.
struct WrapUpBanner: View {
    @Environment(AppModel.self) private var model
    @State private var dismissed = false

    var body: some View {
        if !dismissed, model.shouldOfferWrapUp {
            HStack(spacing: 12) {
                Image(systemName: "moon.stars")
                    .foregroundStyle(NonnaTheme.terracotta)
                Text("Ready to wrap up today?")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button("Wrap up") { model.showsWrapUp = true }
                    .buttonStyle(NonnaButtonStyle(prominent: false))
                Button {
                    model.markWrappedUp()
                    dismissed = true
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(NonnaTheme.secondaryInk)
                .help("Not today")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(NonnaTheme.raisedPaper.opacity(0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }
        }
    }
}
