import SwiftUI

/// Swatches for a list's colour, plus a colour wheel for anything else.
struct ListColorPicker: View {
    @Binding var hex: String
    var size: CGFloat = 26

    /// The original muted set first, then brighter picks.
    static let swatches = [
        "BDA56F", "738B80", "A9A4B5", "788897", "8F7581", "6F858F", "837765",
        "E07A5F", "E9B44C", "6BAF6B", "4A90D9", "8E6BD6", "E06C9F", "D64545",
    ]

    var body: some View {
        FlowChips {
            ForEach(Self.swatches, id: \.self) { swatch in
                Button { hex = swatch } label: { dot(Color(hex: swatch), selected: hex.uppercased() == swatch) }
                    .buttonStyle(.plain)
                    .help("Use this colour")
            }
            ColorPicker("Custom colour", selection: Binding(
                get: { Color(hex: hex) },
                set: { if let value = $0.sRGBHex { hex = value } }
            ), supportsOpacity: false)
            .labelsHidden()
            .help("Pick any colour")
        }
    }

    private func dot(_ color: Color, selected: Bool) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                if selected {
                    Circle().stroke(.white, lineWidth: 2.5).padding(3)
                }
            }
            .overlay { Circle().stroke(NonnaTheme.line, lineWidth: 0.6) }
    }
}
