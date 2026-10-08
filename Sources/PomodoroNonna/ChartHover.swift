import Charts
import SwiftUI

extension View {
    /// Reports the x-axis value under the pointer while it moves over a chart, and nil when it leaves.
    @MainActor
    func chartHover<P: Plottable>(_ type: P.Type, perform: @escaping (P?) -> Void) -> some View {
        chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plotFrame = proxy.plotFrame else {
                                perform(nil)
                                return
                            }
                            let frame = geometry[plotFrame]
                            guard frame.contains(location) else {
                                perform(nil)
                                return
                            }
                            perform(proxy.value(atX: location.x - frame.origin.x, as: P.self))
                        case .ended:
                            perform(nil)
                        }
                    }
                    .onHover { isInside in
                        // A chart can animate beneath a stationary pointer while a sheet opens.
                        // macOS does not always deliver a matching continuous-hover `.ended`
                        // event after that transition, so explicitly clear any stale selection.
                        if !isInside { perform(nil) }
                    }
                    .onDisappear { perform(nil) }
            }
        }
    }

    /// Draws hover content above a chart without participating in chart layout or hit testing.
    /// Keeping the tooltip out of `RuleMark.annotation` prevents the plot frame from moving
    /// underneath the pointer, which otherwise creates an enter/leave feedback loop on macOS.
    func chartHoverTooltip<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        overlay(alignment: .topTrailing) {
            content()
                .padding(8)
                .allowsHitTesting(false)
                .transaction { transaction in
                    transaction.animation = nil
                }
        }
    }
}

/// The small card that follows the pointer on a chart.
struct ChartTooltip: View {
    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(NonnaTheme.ink)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(NonnaTheme.raisedPaper)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(NonnaTheme.strongLine, lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        .fixedSize()
        .allowsHitTesting(false)
    }
}
