import Foundation

/// A to-do inside a list. Lists are the colour-coded categories (`FocusTask`) the timer
/// already knows, such as "Deep work" or a course code.
struct TodoItem: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var listID: UUID?
    /// How many focus blocks (pomodoros) this should take.
    var estimate: Int?
    /// The day it's due (start of day), or nil for "someday".
    var due: Date?
    var notes = ""
    var isDone = false
    var completedAt: Date?
    var createdAt = Date()
}

/// The parts of a typed line like "Problem set 5 3p tomorrow #Math".
struct ParsedTodo: Equatable, Sendable {
    var title: String
    var estimate: Int?
    var due: Date?
    var listName: String?
    var isDone = false
}

/// Turns quick-add lines and pasted notes into tasks.
///
/// Understands, anywhere in a line:
/// - pomodoros: `3p`, `3 pomos`, `3 pomodoros`, `3🍅`
/// - time: `45m`, `1h`, `1.5h`, `1h 30m`, `2 hours` (converted to pomodoros)
/// - dates: `today`, `tonight`, `tomorrow`, `tmrw`, `mon`…`sunday`, `next week`
/// - a list: `#Math`
/// and in pasted notes: bullets (`-`, `*`, `•`, `1.`), checkboxes (`[ ]`, `[x]`), and
/// headings (`Math:` or `# Math`) that put the lines below them in that list.
enum TodoParser {
    static func parseLine(_ raw: String, focusMinutes: Int, now: Date = Date(), calendar: Calendar = .current) -> ParsedTodo? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var isDone = false

        text = text.replacingOccurrences(of: #"^(?:[-*•–]|\d{1,2}[.)])\s+"#, with: "", options: .regularExpression)
        if let match = text.range(of: #"^\[([ xX✓])\]\s*"#, options: .regularExpression) {
            isDone = text[match].contains { "xX✓".contains($0) }
            text.removeSubrange(match)
        }

        var estimate: Int?
        var minutes: Double?
        var due: Date?
        var listName: String?
        let focus = Double(max(1, focusMinutes))

        func take(_ pattern: String, _ handle: ([String]) -> Void) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return }
            while let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                let groups = (0..<match.numberOfRanges).map { index -> String in
                    guard let range = Range(match.range(at: index), in: text) else { return "" }
                    return String(text[range])
                }
                handle(groups)
                if let range = Range(match.range, in: text) { text.replaceSubrange(range, with: " ") }
            }
        }

        take(#"#([\p{L}\p{N}_\-.]+)"#) { listName = $0[1] }
        take(#"(?:🍅\s*(\d{1,2})|(\d{1,2})\s*(?:🍅|p\b|poms?\b|pomos?\b|pomodoros?\b))"#) { groups in
            estimate = Int(groups[1].isEmpty ? groups[2] : groups[1])
        }
        take(#"\b(\d+(?:\.\d+)?)\s*(?:h|hr|hrs|hours?)\b(?:\s*(\d{1,2})\s*(?:m|min|mins|minutes?)\b)?"#) { groups in
            minutes = (minutes ?? 0) + (Double(groups[1]) ?? 0) * 60 + (Double(groups[2]) ?? 0)
        }
        take(#"\b(\d{1,3})\s*(?:m|min|mins|minutes?)\b"#) { groups in
            minutes = (minutes ?? 0) + (Double(groups[1]) ?? 0)
        }
        if estimate == nil, let minutes, minutes > 0 {
            estimate = max(1, Int((minutes / focus).rounded(.up)))
        }

        let today = calendar.startOfDay(for: now)
        take(#"\b(?:due\s+)?(?:today|tonight)\b"#) { _ in due = today }
        take(#"\b(?:due\s+)?(?:tomorrow|tmrw|tmr)\b"#) { _ in due = calendar.date(byAdding: .day, value: 1, to: today) }
        take(#"\b(?:due\s+)?next\s+week\b"#) { _ in due = calendar.date(byAdding: .day, value: 7, to: today) }
        take(#"\b(?:due\s+)?(mon|tues?|wed|thu(?:rs?)?|fri|sat|sun)(?:day|nesday|sday|urday)?\b"#) { groups in
            let names = ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]
            guard let weekday = names[String(groups[1].lowercased().prefix(3))] else { return }
            let current = calendar.component(.weekday, from: today)
            let ahead = (weekday - current + 7) % 7
            due = calendar.date(byAdding: .day, value: ahead, to: today)
        }

        let title = text
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–·,;:")))
        guard !title.isEmpty else { return nil }
        return ParsedTodo(title: title, estimate: estimate.map { min(20, max(1, $0)) }, due: due, listName: listName, isDone: isDone)
    }

    /// Parses a whole pasted list. A heading sets the list for every line beneath it,
    /// unless a line names its own `#list`.
    static func parseDocument(_ text: String, focusMinutes: Int, now: Date = Date(), calendar: Calendar = .current) -> [ParsedTodo] {
        var currentList: String?
        var result: [ParsedTodo] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if let heading = heading(in: line) {
                currentList = heading
                continue
            }
            guard var parsed = parseLine(line, focusMinutes: focusMinutes, now: now, calendar: calendar) else { continue }
            if parsed.listName == nil { parsed.listName = currentList }
            result.append(parsed)
        }
        return result
    }

    /// "Math:", "# Math", "## Chemistry" → the list name. A line with a colon and words
    /// after it ("Note: buy milk") is a task, not a heading.
    static func heading(in line: String) -> String? {
        if line.hasPrefix("#"), let space = line.firstIndex(of: " "), line[..<space].allSatisfy({ $0 == "#" }) {
            let name = line[space...].trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : name
        }
        if line.hasSuffix(":") {
            let name = String(line.dropLast()).trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: #"^(?:[-*•]\s+)"#, with: "", options: .regularExpression)
            return name.isEmpty || name.count > 40 ? nil : name
        }
        return nil
    }
}

// MARK: - Due dates

enum DueBucket: Int, CaseIterable, Sendable {
    case overdue, today, tomorrow, thisWeek, later, someday

    var title: String {
        switch self {
        case .overdue: "Overdue"
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .thisWeek: "This week"
        case .later: "Later"
        case .someday: "No date"
        }
    }

    static func of(_ due: Date?, now: Date = Date(), calendar: Calendar = .current) -> DueBucket {
        guard let due else { return .someday }
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: due)).day ?? 0
        switch days {
        case ..<0: return .overdue
        case 0: return .today
        case 1: return .tomorrow
        case 2...6: return .thisWeek
        default: return .later
        }
    }
}

extension TodoItem {
    /// "Today", "Tomorrow", "Fri", "Oct 21", or "2d overdue".
    func dueLabel(now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let due else { return nil }
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: due)).day ?? 0
        switch days {
        case ..<0: return days == -1 ? "Yesterday" : "\(-days)d overdue"
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2...6: return due.formatted(.dateTime.weekday(.abbreviated))
        default: return due.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    /// Sort: overdue and soonest first, undated last, then oldest first.
    static func dueOrder(_ a: TodoItem, _ b: TodoItem) -> Bool {
        switch (a.due, b.due) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a.createdAt < b.createdAt
        }
    }
}

extension Int {
    /// Minutes as "1h 15m", "45m".
    var minutesString: String {
        let value = Swift.max(0, self)
        let hours = value / 60, minutes = value % 60
        if hours == 0 { return "\(minutes)m" }
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
}
