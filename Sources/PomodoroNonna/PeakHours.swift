import Foundation

/// When you focus best: each hour of the day judged by how its blocks went, not only how
/// many minutes landed there. A block counts toward the hour it started in. Plain data in,
/// plain data out, so it can be checked on its own.
struct PeakHours: Equatable {
    struct Hour: Identifiable, Equatable {
        let hour: Int
        let blocks: Int
        /// Blocks run to their full length.
        let finished: Int
        let minutes: Int
        let ratingSum: Int
        let rated: Int

        var id: Int { hour }
        var finishRate: Double { blocks == 0 ? 0 : Double(finished) / Double(blocks) }
        var averageRating: Double? { rated == 0 ? nil : Double(ratingSum) / Double(rated) }

        /// 0...1: half how often blocks were finished, half how they felt (Scattered 0 to
        /// Flow 1). An unrated block counts as Steady, in the middle, so hours you never rate
        /// can't outrank hours you rated honestly.
        var quality: Double {
            guard blocks > 0 else { return 0 }
            let feel = (Double(ratingSum + 3 * (blocks - rated)) / Double(blocks) - 1) / 4
            return 0.5 * finishRate + 0.5 * feel
        }
    }

    /// A stretch of the day, `start` up to (not including) `end`.
    struct Window: Equatable {
        let start: Int
        let end: Int
        let blocks: Int
        let finishRate: Double
        let averageRating: Double?
        let quality: Double
    }

    let hours: [Hour]
    let blockCount: Int
    /// The best two-hour stretch, once there's enough to say.
    let best: Window?
    /// The hardest two-hour stretch, when it's clearly worse than the best.
    let hardest: Window?

    /// Blocks needed before naming a peak, and in a window before it can be the one.
    static let minimumBlocks = 8
    static let minimumInWindow = 3

    var hasEnoughData: Bool { blockCount >= Self.minimumBlocks && best != nil }

    static func calculate(sessions: [FocusSession], days: Int = 60, now: Date = Date(),
                          calendar: Calendar = .current) -> PeakHours {
        let since = calendar.date(byAdding: .day, value: -days, to: now) ?? .distantPast
        // One block per block, even when it switched lists; misclicks under a minute don't count.
        let blocks = FocusSession.mergedBlocks(sessions).filter {
            $0.startedAt >= since && $0.startedAt <= now && $0.focusedSeconds >= 60
        }
        var hours = (0..<24).map { Hour(hour: $0, blocks: 0, finished: 0, minutes: 0, ratingSum: 0, rated: 0) }
        for block in blocks {
            let h = calendar.component(.hour, from: block.startedAt)
            let old = hours[h]
            let finished = block.outcome == .completed && block.focusedSeconds >= block.plannedSeconds - 30
            hours[h] = Hour(hour: h, blocks: old.blocks + 1, finished: old.finished + (finished ? 1 : 0),
                            minutes: old.minutes + block.focusedSeconds / 60,
                            ratingSum: old.ratingSum + (block.focusRating ?? 0),
                            rated: old.rated + (block.focusRating == nil ? 0 : 1))
        }

        func window(from start: Int) -> Window? {
            let slice = [hours[start], hours[(start + 1) % 24]]
            let count = slice.reduce(0) { $0 + $1.blocks }
            guard count >= minimumInWindow else { return nil }
            let finished = slice.reduce(0) { $0 + $1.finished }
            let rated = slice.reduce(0) { $0 + $1.rated }
            let ratingSum = slice.reduce(0) { $0 + $1.ratingSum }
            let quality = slice.reduce(0.0) { $0 + $1.quality * Double($1.blocks) } / Double(count)
            return Window(start: start, end: (start + 2) % 24, blocks: count,
                          finishRate: Double(finished) / Double(count),
                          averageRating: rated == 0 ? nil : Double(ratingSum) / Double(rated), quality: quality)
        }
        let windows = (0..<24).compactMap(window)
        // Ranked with a little caution: each window's quality is pulled toward your overall
        // average by a few blocks' worth, so three great blocks don't outrank eight good ones.
        let overall = blocks.isEmpty ? 0 : hours.reduce(0.0) { $0 + $1.quality * Double($1.blocks) } / Double(blocks.count)
        func confidence(_ w: Window) -> Double {
            let prior = Double(minimumInWindow)
            return (w.quality * Double(w.blocks) + overall * prior) / (Double(w.blocks) + prior)
        }
        let best = windows.max { confidence($0) < confidence($1) }
        let worst = windows.min { confidence($0) < confidence($1) }
        let hardest = (best != nil && worst != nil && worst!.quality <= best!.quality - 0.2) ? worst : nil
        return PeakHours(hours: hours, blockCount: blocks.count,
                         best: blocks.count >= minimumBlocks ? best : nil,
                         hardest: blocks.count >= minimumBlocks ? hardest : nil)
    }
}

extension Int {
    /// "2 PM", "12 AM", for an hour of the day.
    var clockHourLabel: String {
        let h = ((self % 24) + 24) % 24
        let twelve = h % 12 == 0 ? 12 : h % 12
        return "\(twelve) \(h < 12 ? "AM" : "PM")"
    }
}
