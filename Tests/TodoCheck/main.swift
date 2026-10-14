import Foundation

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "UTC")!
// Tuesday, 13 October 2026, mid-afternoon.
let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 15))!
let today = calendar.startOfDay(for: now)
func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
func parse(_ line: String, focus: Int = 25) -> ParsedTodo? { TodoParser.parseLine(line, focusMinutes: focus, now: now, calendar: calendar) }

// Plain titles survive untouched.
check(parse("Read chapter 4")?.title == "Read chapter 4", "plain title")
check(parse("Read chapter 4")?.estimate == nil, "no estimate unless asked")
check(parse("   ") == nil && parse("- ") == nil, "blank lines are skipped")

// Pomodoro estimates in every spelling.
check(parse("Problem set 5 3p")?.estimate == 3 && parse("Problem set 5 3p")?.title == "Problem set 5", "3p")
check(parse("Essay 2 pomos")?.estimate == 2, "2 pomos")
check(parse("Essay 4 pomodoros")?.estimate == 4, "4 pomodoros")
check(parse("Essay 3🍅")?.estimate == 3 && parse("Essay 🍅2")?.estimate == 2, "tomato emoji")
check(parse("Essay 99p")?.estimate == 20, "estimates are capped")

// Time converts to pomodoros at the current focus length, rounding up.
check(parse("Lab report 1h")?.estimate == 3, "1h at 25m = 3")
check(parse("Lab report 1h", focus: 50)?.estimate == 2, "1h at 50m = 2")
check(parse("Lab report 1.5h", focus: 45)?.estimate == 2, "1.5h at 45m = 2")
check(parse("Lab report 1h 30m")?.estimate == 4, "1h 30m at 25m = 4")
check(parse("Quick email 10m")?.estimate == 1, "short tasks are at least one block")
check(parse("Lab report 1h 30m")?.title == "Lab report", "time removed from title")
check(parse("Pomodoro technique video")?.estimate == nil, "words containing p aren't estimates")

// Dates.
check(parse("Quiz prep today")?.due == today && parse("Quiz prep tonight")?.due == today, "today / tonight")
check(parse("Quiz prep tomorrow")?.due == day(1) && parse("Quiz prep tmrw")?.due == day(1), "tomorrow / tmrw")
check(parse("Quiz prep next week")?.due == day(7), "next week")
check(parse("Quiz prep fri")?.due == day(3) && parse("Quiz prep friday")?.due == day(3), "weekday → this Friday")
check(parse("Quiz prep tuesday")?.due == today, "today's weekday is today")
check(parse("Quiz prep mon")?.due == day(6), "Monday wraps to next week")
check(parse("Quiz prep due wednesday")?.title == "Quiz prep", "'due' is removed with the date")
check(parse("Monitor setup")?.due == nil && parse("Monitor setup")?.title == "Monitor setup", "weekday prefixes inside words are left alone")

// Lists and combinations.
let full = parse("- Problem set 5 3p tomorrow #Math")
check(full == ParsedTodo(title: "Problem set 5", estimate: 3, due: day(1), listName: "Math"), "everything at once: \(String(describing: full))")

// Bullets and checkboxes.
check(parse("* Flashcards")?.title == "Flashcards" && parse("• Flashcards")?.title == "Flashcards" && parse("2. Flashcards")?.title == "Flashcards", "bullets")
check(parse("- [x] Flashcards")?.isDone == true && parse("[ ] Flashcards")?.isDone == false, "checkboxes")
check(parse("- [x] Flashcards")?.title == "Flashcards", "checkbox removed from title")

// Headings.
check(TodoParser.heading(in: "Math:") == "Math" && TodoParser.heading(in: "# Chemistry") == "Chemistry" && TodoParser.heading(in: "## Bio") == "Bio", "headings")
check(TodoParser.heading(in: "Note: buy milk") == nil && TodoParser.heading(in: "#Math thing") == nil, "not headings")

// A whole pasted note.
let note = """
Math:
- Make formula sheet 2p today
- Problem set 5 3p tomorrow

Bio:
- [x] Read chapter 3
- Practice midterm 1h fri #Exams
Email professor
"""
let items = TodoParser.parseDocument(note, focusMinutes: 25, now: now, calendar: calendar)
check(items.count == 5, "five tasks from the note (\(items.count))")
check(items.map(\.listName) == ["Math", "Math", "Bio", "Exams", "Bio"], "headings set lists, #list overrides (\(items.map(\.listName)))")
check(items[2].isDone && !items[3].isDone, "checked lines come in done")
check(items[3].estimate == 3 && items[3].due == day(3), "estimate and date on a pasted line")

// Due buckets and labels.
check(DueBucket.of(day(-2), now: now, calendar: calendar) == .overdue, "overdue")
check(DueBucket.of(day(0), now: now, calendar: calendar) == .today && DueBucket.of(day(1), now: now, calendar: calendar) == .tomorrow, "today / tomorrow")
check(DueBucket.of(day(4), now: now, calendar: calendar) == .thisWeek && DueBucket.of(day(10), now: now, calendar: calendar) == .later, "week / later")
check(DueBucket.of(nil) == .someday, "no date")
check(TodoItem(title: "", due: day(-3)).dueLabel(now: now, calendar: calendar) == "3d overdue", "overdue label")
check(TodoItem(title: "", due: day(1)).dueLabel(now: now, calendar: calendar) == "Tomorrow", "tomorrow label")

// Sorting: dated first, soonest first, undated last.
let a = TodoItem(title: "a", due: day(2)), b = TodoItem(title: "b", due: day(-1)), c = TodoItem(title: "c")
check([a, c, b].sorted(by: TodoItem.dueOrder).map(\.title) == ["b", "a", "c"], "due order")

check(75.minutesString == "1h 15m" && 45.minutesString == "45m" && 120.minutesString == "2h", "minute strings")

// Old data without to-dos still decodes.
check((try? JSONDecoder().decode(TodoItem.self, from: Data(#"{"id":"\#(UUID().uuidString)","title":"x","notes":"","isDone":false,"createdAt":0}"#.utf8))) != nil, "decodes minimal JSON")

print("Todo checks passed")
