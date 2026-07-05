import EventKit
import Combine

/// Today's calendar events and open reminders via EventKit.
@MainActor
final class CalendarManager: ObservableObject {
    enum Access {
        case unknown, granted, denied
    }

    @Published private(set) var eventAccess: Access = .unknown
    @Published private(set) var reminderAccess: Access = .unknown
    @Published private(set) var upcomingEvents: [EKEvent] = []
    @Published private(set) var openReminders: [EKReminder] = []

    private let store = EKEventStore()

    init() {
        updateAccessFromSystem()
    }

    private func updateAccessFromSystem() {
        eventAccess = Self.access(for: .event)
        reminderAccess = Self.access(for: .reminder)
    }

    private static func access(for entity: EKEntityType) -> Access {
        let status = EKEventStore.authorizationStatus(for: entity)
        if #available(macOS 14.0, *) {
            switch status {
            case .fullAccess: return .granted
            case .notDetermined: return .unknown
            default: return .denied
            }
        } else {
            switch status {
            case .authorized: return .granted
            case .notDetermined: return .unknown
            default: return .denied
            }
        }
    }

    func requestAccessAndRefresh() {
        requestEventAccess { [weak self] in
            self?.requestReminderAccess {
                self?.refresh()
            }
        }
    }

    private func requestEventAccess(completion: @escaping () -> Void) {
        let handler: (Bool, Error?) -> Void = { granted, _ in
            Task { @MainActor [weak self] in
                self?.eventAccess = granted ? .granted : .denied
                completion()
            }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents(completion: handler)
        } else {
            store.requestAccess(to: .event, completion: handler)
        }
    }

    private func requestReminderAccess(completion: @escaping () -> Void) {
        let handler: (Bool, Error?) -> Void = { granted, _ in
            Task { @MainActor [weak self] in
                self?.reminderAccess = granted ? .granted : .denied
                completion()
            }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToReminders(completion: handler)
        } else {
            store.requestAccess(to: .reminder, completion: handler)
        }
    }

    func refresh() {
        if eventAccess == .granted {
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: Date())
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            let events = store.events(matching: predicate)
                .filter { !$0.isAllDay || calendar.isDateInToday($0.startDate) }
                .sorted { $0.startDate < $1.startDate }
            upcomingEvents = Array(events.prefix(24))
        }
        if reminderAccess == .granted {
            let predicate = store.predicateForReminders(in: nil)
            store.fetchReminders(matching: predicate) { [weak self] reminders in
                let open = (reminders ?? [])
                    .filter { !$0.isCompleted }
                    .sorted { a, b in
                        let dateA = a.dueDateComponents?.date ?? .distantFuture
                        let dateB = b.dueDateComponents?.date ?? .distantFuture
                        return dateA < dateB
                    }
                Task { @MainActor in
                    self?.openReminders = Array(open.prefix(16))
                }
            }
        }
    }

    func complete(_ reminder: EKReminder) {
        reminder.isCompleted = true
        try? store.save(reminder, commit: true)
        openReminders.removeAll { $0.calendarItemIdentifier == reminder.calendarItemIdentifier }
    }
}
