import SwiftUI

/// A small "?" that explains a number or chart in plain words when clicked.
struct InfoButton: View {
    let title: String
    let text: String
    @State private var showing = false
    @State private var hovering = false

    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: "questionmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(hovering || showing ? NonnaTheme.ink : NonnaTheme.secondaryInk)
                .frame(width: 16, height: 16)
                .background(NonnaTheme.raisedPaper, in: Circle())
                .overlay { Circle().stroke(NonnaTheme.line, lineWidth: 0.8) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("What is \(title)?")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 260, alignment: .leading)
        }
    }
}
