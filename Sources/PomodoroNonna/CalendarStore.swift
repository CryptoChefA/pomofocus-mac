import AppKit
import EventKit
import Foundation
import SwiftUI

/// A read-only copy of one calendar event. Pomofocus never creates, edits, or deletes events.
struct CalendarEvent: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let calendarID: String
    let calendarName: String
    let color: Color
    let startedAt: Date
    let endedAt: Date
    let isAllDay: Bool
    let location: String
    /// Shown as free in the calendar (holds, reminders, working-location entries).
    var isFree = false

    /// Whether planning should keep clear of it. All-day events, events marked free, and
    /// ones lasting 8 hours or more (trips, "at work", multi-day blocks) would otherwise
    /// fill the whole day and leave nothing to plan into.
    var blocksPlanning: Bool {
        !isAllDay && !isFree && endedAt.timeIntervalSince(startedAt) < 8 * 3600
    }
}

struct CalendarInfo: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let sourceTitle: String
    let color: Color
}

enum CalendarAccess: Sendable {
    case notDetermined
    case granted
    case denied
}

/// Reads events from the calendars macOS already syncs (iCloud, Google, Exchange, and so on)
/// through EventKit. There is no networking here and no write path of any kind.
@MainActor
final class CalendarStore: ObservableObject {
    @Published private(set) var access: CalendarAccess = .notDetermined
    @Published private(set) var calendars: [CalendarInfo] = []
    @Published private(set) var revision = 0
    @Published private(set) var isRequestingAccess = false
    @Published private(set) var accessError: String?

    private var store = EKEventStore()
    private var cache: [Date: [CalendarEvent]] = [:]
    private var observer: NSObjectProtocol?
    /// The app's store, for windows outside the main scene such as Cinema mode.
    private(set) static weak var current: CalendarStore?

    init() {
        Self.current = self
        refreshAccess()
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { @Sendable [weak self] _ in
            Task { @MainActor in self?.storeChanged() }
        }
    }

    func refreshAccess() {
        let status = EKEventStore.authorizationStatus(for: .event)
        let resolved: CalendarAccess
        switch status {
        case .fullAccess: resolved = .granted
        case .notDetermined: resolved = .notDetermined
        default: resolved = .denied
        }
        let changed = resolved != access
        access = resolved
        if resolved == .granted {
            if changed { store = EKEventStore() }
            reloadCalendars()
        } else {
            calendars = []
        }
        cache = [:]
        revision += 1
    }

    func requestAccess() {
        guard !isRequestingAccess else { return }
        isRequestingAccess = true
        accessError = nil
        store.requestFullAccessToEvents { @Sendable [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                self.isRequestingAccess = false
                self.accessError = error?.localizedDescription
                self.refreshAccess()
            }
        }
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }

    func events(on day: Date, hiddenIDs: [String]) -> [CalendarEvent] {
        guard access == .granted else { return [] }
        let dayStart = Calendar.current.startOfDay(for: day)
        let all: [CalendarEvent]
        if let cached = cache[dayStart] {
            all = cached
        } else {
            all = loadEvents(startingAt: dayStart)
            if cache.count > 60 { cache = [:] }
            cache[dayStart] = all
        }
        guard !hiddenIDs.isEmpty else { return all }
        let hidden = Set(hiddenIDs)
        return all.filter { !hidden.contains($0.calendarID) }
    }

    /// The next timed event starting within `horizon`, looking into tomorrow when the
    /// evening is nearly over. All-day events are left out: they don't start at a time.
    func nextEvent(after now: Date = Date(), within horizon: TimeInterval = 12 * 3600, hiddenIDs: [String]) -> CalendarEvent? {
        let today = Calendar.current.startOfDay(for: now)
        var days = [today]
        if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today),
           now.addingTimeInterval(horizon) > tomorrow {
            days.append(tomorrow)
        }
        return days.flatMap { events(on: $0, hiddenIDs: hiddenIDs) }
            .filter { !$0.isAllDay && $0.startedAt > now && $0.startedAt <= now.addingTimeInterval(horizon) }
            .min { $0.startedAt < $1.startedAt }
    }

    private func storeChanged() {
        guard access == .granted else { return }
        cache = [:]
        reloadCalendars()
        revision += 1
    }

    private func reloadCalendars() {
        calendars = store.calendars(for: .event)
            .map { calendar -> CalendarInfo in
                CalendarInfo(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    sourceTitle: calendar.source?.title ?? "",
                    color: Self.color(for: calendar)
                )
            }
            .sorted {
                if $0.sourceTitle == $1.sourceTitle {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.sourceTitle.localizedCaseInsensitiveCompare($1.sourceTitle) == .orderedAscending
            }
    }

    private func loadEvents(startingAt dayStart: Date) -> [CalendarEvent] {
        guard let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)
        return store.events(matching: predicate).compactMap { event -> CalendarEvent? in
            let start: Date? = event.startDate
            let end: Date? = event.endDate
            let calendar: EKCalendar? = event.calendar
            guard let start, let end, let calendar, end > dayStart, start < dayEnd else { return nil }
            if event.status == .canceled { return nil }
            let declined = (event.attendees ?? []).contains {
                $0.isCurrentUser && $0.participantStatus == .declined
            }
            if declined { return nil }

            let identifier: String? = event.eventIdentifier
            let title: String? = event.title
            let trimmedTitle = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return CalendarEvent(
                id: "\(identifier ?? UUID().uuidString)-\(Int(start.timeIntervalSince1970))",
                title: trimmedTitle.isEmpty ? "Untitled event" : trimmedTitle,
                calendarID: calendar.calendarIdentifier,
                calendarName: calendar.title,
                color: Self.color(for: calendar),
                startedAt: start,
                endedAt: max(end, start.addingTimeInterval(60)),
                isAllDay: event.isAllDay,
                location: event.location ?? "",
                isFree: event.availability == .free
            )
        }
        .sorted { $0.startedAt < $1.startedAt }
    }

    private static func color(for calendar: EKCalendar) -> Color {
        let cgColor: CGColor? = calendar.cgColor
        guard let cgColor else { return NonnaTheme.secondaryInk }
        return Color(cgColor: cgColor)
    }
}
