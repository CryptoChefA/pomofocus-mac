import Foundation

/// One daily check-in: how the day feels on the whole, a few words for it, and what's
/// behind it. Stays on this Mac with the rest of your data.
struct MoodCheckIn: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var date: Date
    /// 1 (very unpleasant) to 7 (very pleasant), the same seven steps as Apple's State of Mind.
    var level: Int
    var feelings: [String] = []
    var influences: [String] = []
    /// Exactly where the slider was left, 0 (very unpleasant) to 1 (very pleasant).
    var valence: Double? = nil
    /// An optional line in your own words.
    var note: String? = nil
}

/// The words and choices a check-in offers. Naming a feeling is most of the point: putting
/// it into words tends to take some of its edge off.
enum MoodScale {
    static let levels = 1...7

    static func clamped(_ level: Int) -> Int { min(levels.upperBound, max(levels.lowerBound, level)) }

    static func title(_ level: Int) -> String {
        ["Very unpleasant", "Unpleasant", "Slightly unpleasant", "Neutral",
         "Slightly pleasant", "Pleasant", "Very pleasant"][clamped(level) - 1]
    }

    static func isPleasant(_ level: Int) -> Bool { level >= 5 }
    static func isUnpleasant(_ level: Int) -> Bool { level <= 3 }

    /// Every feeling word, each placed on the scale from 0 (very unpleasant) to 1 (very
    /// pleasant), close to the words Apple's State of Mind offers.
    static let vocabulary: [(word: String, valence: Double)] = [
        ("Hopeless", 0.02), ("Scared", 0.07), ("Ashamed", 0.09), ("Angry", 0.1), ("Guilty", 0.13),
        ("Overwhelmed", 0.15), ("Lonely", 0.16), ("Sad", 0.18), ("Anxious", 0.2), ("Stressed", 0.22),
        ("Jealous", 0.23), ("Frustrated", 0.25), ("Embarrassed", 0.26), ("Worried", 0.27), ("Discouraged", 0.28),
        ("Disappointed", 0.3), ("Irritated", 0.31), ("Drained", 0.33), ("Annoyed", 0.35), ("Tired", 0.4),
        ("Restless", 0.42), ("Bored", 0.45), ("Distracted", 0.46), ("Indifferent", 0.5), ("Okay", 0.53),
        ("Calm", 0.61), ("Peaceful", 0.63), ("Content", 0.65), ("Relieved", 0.67), ("Focused", 0.69),
        ("Satisfied", 0.71), ("Hopeful", 0.73), ("Surprised", 0.74), ("Grateful", 0.78), ("Confident", 0.79),
        ("Brave", 0.8), ("Motivated", 0.81), ("Proud", 0.83), ("Happy", 0.85), ("Amused", 0.86),
        ("Passionate", 0.87), ("Energised", 0.89), ("Excited", 0.91), ("Joyful", 0.94), ("Amazed", 0.97),
    ]

    static func valence(ofFeeling word: String) -> Double? { vocabulary.first { $0.word == word }?.valence }

    /// The words closest to where the slider sits, unpleasant to pleasant, so the list stays short.
    static func feelings(near valence: Double, count: Int = 12) -> [String] {
        vocabulary.sorted { abs($0.valence - valence) < abs($1.valence - valence) }
            .prefix(count)
            .sorted { $0.valence < $1.valence }
            .map(\.word)
    }

    static func feelings(for level: Int) -> [String] { feelings(near: valence(forLevel: level)) }

    static func valence(forLevel level: Int) -> Double { Double(clamped(level) - 1) / 6 }
    static func level(forValence valence: Double) -> Int { clamped(Int((min(1, max(0, valence)) * 6).rounded()) + 1) }

    /// What's having the biggest effect, with a symbol each.
    static let influences: [(name: String, icon: String)] = [
        ("School", "book.closed"), ("Exams", "pencil.and.list.clipboard"), ("Work", "briefcase"),
        ("Friends", "person.2"), ("Family", "house"), ("Partner", "heart"),
        ("Sleep", "bed.double"), ("Health", "cross.case"), ("Fitness", "figure.run"),
        ("Self-care", "leaf"), ("Hobbies", "paintpalette"), ("Money", "creditcard"),
        ("Social media", "iphone"), ("Travel", "airplane"), ("Weather", "cloud.sun"), ("Current events", "newspaper"),
    ]

    static func icon(forInfluence name: String) -> String {
        influences.first { $0.name == name }?.icon ?? "circle"
    }
}

/// What the Dashboard shows about mood, worked out from the check-ins.
struct MoodSummary {
    struct Day: Identifiable { let day: Date; let level: Int?; var id: Date { day } }
    struct Count: Identifiable { let name: String; let count: Int; let averageLevel: Double; var id: String { name } }

    /// The window, oldest first, one entry per day (nil where there was no check-in).
    let days: [Day]
    let checkInsInWindow: Int
    let averageLevel: Double?
    let topFeelings: [Count]
    let topInfluences: [Count]
    /// Average focused seconds on pleasant and on unpleasant days, once there are at least
    /// three of each in the last 90 days; nil until then, so a couple of days can't mislead.
    let focusOnGoodDays: Int?
    let focusOnHardDays: Int?
    /// Most of the last two weeks' check-ins were unpleasant. Shown as a gentle nudge to talk
    /// to someone, never as a judgement or a diagnosis.
    let heavyStretch: Bool

    static func calculate(checkIns: [MoodCheckIn], focusByDay: [Date: Int], windowDays: Int = 30,
                          now: Date = Date(), calendar: Calendar = .current) -> MoodSummary {
        let today = calendar.startOfDay(for: now)
        // One check-in per day: the latest wins.
        var byDay: [Date: MoodCheckIn] = [:]
        for checkIn in checkIns.sorted(by: { $0.date < $1.date }) {
            byDay[calendar.startOfDay(for: checkIn.date)] = checkIn
        }
        func since(_ days: Int) -> [MoodCheckIn] {
            guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
            return byDay.filter { $0.key >= start && $0.key <= today }.sorted { $0.key < $1.key }.map(\.value)
        }

        let window = since(windowDays)
        let days: [Day] = (0..<windowDays).reversed().compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            return Day(day: day, level: byDay[day]?.level)
        }
        let average = window.isEmpty ? nil : Double(window.reduce(0) { $0 + $1.level }) / Double(window.count)

        func counts(_ names: (MoodCheckIn) -> [String], limit: Int) -> [Count] {
            var tally: [String: (count: Int, levels: Int)] = [:]
            for checkIn in window {
                for name in Set(names(checkIn)) {
                    let current = tally[name] ?? (0, 0)
                    tally[name] = (current.count + 1, current.levels + checkIn.level)
                }
            }
            return tally.map { Count(name: $0.key, count: $0.value.count, averageLevel: Double($0.value.levels) / Double($0.value.count)) }
                .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
                .prefix(limit).map { $0 }
        }

        let recent = since(90)
        let good = recent.filter { MoodScale.isPleasant($0.level) }
        let hard = recent.filter { MoodScale.isUnpleasant($0.level) }
        func averageFocus(_ list: [MoodCheckIn]) -> Int? {
            guard list.count >= 3 else { return nil }
            let total = list.reduce(0) { $0 + (focusByDay[calendar.startOfDay(for: $1.date)] ?? 0) }
            return total / list.count
        }
        let goodFocus = averageFocus(good), hardFocus = averageFocus(hard)

        let fortnight = since(14)
        let heavy = fortnight.count >= 5
            && Double(fortnight.filter { MoodScale.isUnpleasant($0.level) }.count) / Double(fortnight.count) >= 0.7

        return MoodSummary(
            days: days,
            checkInsInWindow: window.count,
            averageLevel: average,
            topFeelings: counts(\.feelings, limit: 3),
            topInfluences: counts(\.influences, limit: 4),
            focusOnGoodDays: goodFocus == nil || hardFocus == nil ? nil : goodFocus,
            focusOnHardDays: goodFocus == nil || hardFocus == nil ? nil : hardFocus,
            heavyStretch: heavy
        )
    }
}
