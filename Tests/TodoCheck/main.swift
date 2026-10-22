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
check(parse("Read chapter 4")?.minutes == nil, "no length unless given")
check(parse("   ") == nil && parse("- ") == nil, "blank lines are skipped")

// Time, in minutes.
check(parse("Lab report 1h")?.minutes == 60 && parse("Lab report 1h")?.title == "Lab report", "1h")
check(parse("Lab report 1.5h")?.minutes == 90, "1.5h")
check(parse("Lab report 1h 30m")?.minutes == 90 && parse("Lab report 1h 30m")?.title == "Lab report", "1h 30m")
check(parse("Quick email 10m")?.minutes == 10, "10m")
check(parse("Quick email 2m")?.minutes == 5, "lengths are at least 5 minutes")
check(parse("Thesis 40h")?.minutes == 1440, "lengths are capped at a day")

// Pomodoro shorthand still works, converted at the focus length.
check(parse("Problem set 5 3p")?.minutes == 75 && parse("Problem set 5 3p")?.title == "Problem set 5", "3p at 25m")
check(parse("Essay 2 pomos", focus: 50)?.minutes == 100, "2 pomos at 50m")
check(parse("Essay 3🍅")?.minutes == 75 && parse("Essay 🍅2")?.minutes == 50, "tomato emoji")
check(parse("Pomodoro technique video")?.minutes == nil, "words containing p aren't lengths")

// Dates.
check(parse("Quiz prep today")?.due == today && parse("Quiz prep tonight")?.due == today, "today / tonight")
check(parse("Quiz prep tomorrow")?.due == day(1) && parse("Quiz prep tmrw")?.due == day(1), "tomorrow / tmrw")
check(parse("Quiz prep next week")?.due == day(7), "next week")
check(parse("Quiz prep fri")?.due == day(3) && parse("Quiz prep friday")?.due == day(3), "weekday → this Friday")
check(parse("Quiz prep tuesday")?.due == today, "today's weekday is today")
check(parse("Quiz prep mon")?.due == day(6), "Monday wraps to next week")
check(parse("Quiz prep due wednesday")?.title == "Quiz prep", "'due' is removed with the date")
check(parse("Monitor setup")?.due == nil && parse("Monitor setup")?.title == "Monitor setup", "weekday prefixes inside words are left alone")

// Things that look like tags or days but aren't.
check(parse("Assignment #3")?.title == "Assignment #3" && parse("Assignment #3")?.listName == nil, "#3 stays in the title")
check(parse("Study for SAT")?.title == "Study for SAT" && parse("Study for SAT")?.due == nil, "SAT isn't Saturday")
check(parse("Quiz prep sat")?.due == day(4), "lowercase sat is Saturday")

// Lists and combinations.
let full = parse("- Problem set 5 3p tomorrow #Math")
check(full == ParsedTodo(title: "Problem set 5", minutes: 75, due: day(1), listName: "Math"), "everything at once: \(String(describing: full))")

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
check(items[3].minutes == 60 && items[3].due == day(3), "length and date on a pasted line")

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
