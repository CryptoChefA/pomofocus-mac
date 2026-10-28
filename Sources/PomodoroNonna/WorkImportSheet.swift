import SwiftUI

/// Shown once after updating: what you've already been timing, ready to become tasks.
/// Nothing is added unless it's ticked.
struct WorkImportSheet: View {
    @Environment(AppModel.self) private var model
    let suggestions: [WorkSuggestion]
    let onDone: () -> Void
    @State private var picked: Set<String>

    init(suggestions: [WorkSuggestion], onDone: @escaping () -> Void) {
        self.suggestions = suggestions
        self.onDone = onDone
        _picked = State(initialValue: Set(suggestions.filter(\.startsPicked).map(\.id)))
    }

    private var worked: [WorkSuggestion] { suggestions.filter { $0.source == .workedOn } }
    private var lists: [WorkSuggestion] { suggestions.filter { $0.source == .list } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Bring your work into Tasks")
                    .font(.system(size: 26, weight: .regular, design: .serif))
                Text("Pomofocus found what you've been focusing on. Tick what you'd like as tasks; you can rename or delete them any time.")
                    .font(.system(size: 12))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !worked.isEmpty { group("What you've been working on", worked) }
                    if !lists.isEmpty { group("Your lists", lists) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 340)

            HStack {
                Button("Not now", action: onDone)
                    .buttonStyle(NonnaButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(picked.count == 1 ? "Add 1 task" : "Add \(picked.count) tasks") {
                    model.addTodos(fromWork: suggestions.filter { picked.contains($0.id) })
                    onDone()
                }
                .buttonStyle(NonnaButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(picked.isEmpty)
            }
        }
        .padding(28)
        .frame(width: 480, alignment: .leading)
        .background(NonnaTheme.cream)
        .foregroundStyle(NonnaTheme.ink)
        .preferredColorScheme(NonnaTheme.colorScheme)
    }

    private func group(_ title: String, _ items: [WorkSuggestion]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NonnaTheme.secondaryInk)
                .padding(.bottom, 4)
            ForEach(items) { item in row(item) }
        }
    }

    private func row(_ item: WorkSuggestion) -> some View {
        let list = model.tasks.first { $0.id == item.listID }
        return Toggle(isOn: Binding(
            get: { picked.contains(item.id) },
            set: { if $0 { picked.insert(item.id) } else { picked.remove(item.id) } }
        )) {
            HStack(spacing: 8) {
                Text(item.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if item.source == .workedOn, let list {
                    HStack(spacing: 5) {
                        Circle().fill(NonnaTheme.taskColor(for: list.colorHex)).frame(width: 6, height: 6)
                        Text(list.name)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                }
                if item.blocks > 0 {
                    Text(item.blocks == 1 ? "1 block" : "\(item.blocks) blocks")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(NonnaTheme.paper.opacity(picked.contains(item.id) ? 1 : 0.5),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
