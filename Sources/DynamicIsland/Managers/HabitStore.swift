import Foundation
import Combine

struct DaysLeftEvent: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var date: Date

    var daysLeft: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: target).day ?? 0
    }
}

private struct HabitState: Codable {
    var waterCount: Int
    var waterGoal: Int
    var waterDay: String
    var counterValue: Int
    var events: [DaysLeftEvent]
}

/// Daily water tracking, a general-purpose counter and "days left" events.
@MainActor
final class HabitStore: ObservableObject {
    @Published var waterCount: Int = 0 { didSet { persist() } }
    @Published var waterGoal: Int = 8 { didSet { persist() } }
    @Published var counterValue: Int = 0 { didSet { persist() } }
    @Published var events: [DaysLeftEvent] = [] { didSet { persist() } }

    private var waterDay: String = HabitStore.todayKey()
    private var loading = true

    init() {
        if let state = Persistence.load(HabitState.self, from: "habits.json") {
            waterGoal = max(state.waterGoal, 1)
            counterValue = state.counterValue
            events = state.events
            // Water resets every day.
            if state.waterDay == Self.todayKey() {
                waterCount = state.waterCount
            } else {
                waterCount = 0
            }
        }
        loading = false
        persist()
    }

    func drinkWater() {
        rolloverIfNeeded()
        waterCount += 1
    }

    func undoWater() {
        rolloverIfNeeded()
        waterCount = max(waterCount - 1, 0)
    }

    func addEvent(name: String, date: Date) {
        events.append(DaysLeftEvent(id: UUID(), name: name, date: date))
        events.sort { $0.date < $1.date }
    }

    func removeEvent(_ event: DaysLeftEvent) {
        events.removeAll { $0.id == event.id }
    }

    private func rolloverIfNeeded() {
        let today = Self.todayKey()
        if waterDay != today {
            waterDay = today
            // waterCount'ın didSet'i persist()'i tetikler ve yeni waterDay'i de yazar.
            waterCount = 0
        }
    }

    private static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func persist() {
        guard !loading else { return }
        Persistence.save(
            HabitState(
                waterCount: waterCount,
                waterGoal: waterGoal,
                waterDay: waterDay,
                counterValue: counterValue,
                events: events
            ),
            to: "habits.json"
        )
    }
}
