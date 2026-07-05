import AppKit
import Combine

/// Pomodoro, countdown and stopwatch in one engine with a single tick source.
@MainActor
final class TimerCenter: ObservableObject {
    // MARK: Pomodoro
    enum PomodoroPhase: String {
        case work = "Odak"
        case rest = "Mola"
    }

    @Published var workMinutes: Int {
        didSet { UserDefaults.standard.set(workMinutes, forKey: "pomodoro.work") }
    }
    @Published var breakMinutes: Int {
        didSet { UserDefaults.standard.set(breakMinutes, forKey: "pomodoro.break") }
    }
    @Published private(set) var pomodoroPhase: PomodoroPhase = .work
    @Published private(set) var pomodoroRemaining: TimeInterval = 25 * 60
    @Published private(set) var pomodoroRunning = false
    @Published private(set) var pomodoroCycles = 0

    // MARK: Countdown
    @Published var countdownMinutes: Int = 10
    @Published private(set) var countdownRemaining: TimeInterval = 0
    @Published private(set) var countdownRunning = false

    // MARK: Stopwatch
    @Published private(set) var stopwatchElapsed: TimeInterval = 0
    @Published private(set) var stopwatchRunning = false

    private var timer: Timer?
    private var lastTick = Date()

    init() {
        let work = UserDefaults.standard.integer(forKey: "pomodoro.work")
        let rest = UserDefaults.standard.integer(forKey: "pomodoro.break")
        workMinutes = work > 0 ? work : 25
        breakMinutes = rest > 0 ? rest : 5
        pomodoroRemaining = TimeInterval((work > 0 ? work : 25) * 60)

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = Date()
        let delta = now.timeIntervalSince(lastTick)
        lastTick = now
        guard delta > 0, delta < 10 else { return }

        if pomodoroRunning {
            pomodoroRemaining -= delta
            if pomodoroRemaining <= 0 {
                advancePomodoroPhase()
            }
        }
        if countdownRunning {
            countdownRemaining -= delta
            if countdownRemaining <= 0 {
                countdownRemaining = 0
                countdownRunning = false
                notifyDone()
            }
        }
        if stopwatchRunning {
            stopwatchElapsed += delta
        }
    }

    private func advancePomodoroPhase() {
        notifyDone()
        if pomodoroPhase == .work {
            pomodoroCycles += 1
            pomodoroPhase = .rest
            pomodoroRemaining = TimeInterval(breakMinutes * 60)
        } else {
            pomodoroPhase = .work
            pomodoroRemaining = TimeInterval(workMinutes * 60)
        }
    }

    private func notifyDone() {
        NSSound(named: "Glass")?.play()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    // MARK: - Pomodoro controls

    func pomodoroToggle() {
        pomodoroRunning.toggle()
        lastTick = Date()
    }

    func pomodoroReset() {
        pomodoroRunning = false
        pomodoroPhase = .work
        pomodoroRemaining = TimeInterval(workMinutes * 60)
        pomodoroCycles = 0
    }

    // MARK: - Countdown controls

    func countdownStart() {
        if countdownRemaining <= 0 {
            countdownRemaining = TimeInterval(countdownMinutes * 60)
        }
        countdownRunning = true
        lastTick = Date()
    }

    func countdownPause() { countdownRunning = false }

    func countdownReset() {
        countdownRunning = false
        countdownRemaining = 0
    }

    // MARK: - Stopwatch controls

    func stopwatchToggle() {
        stopwatchRunning.toggle()
        lastTick = Date()
    }

    func stopwatchReset() {
        stopwatchRunning = false
        stopwatchElapsed = 0
    }

    // MARK: - Collapsed pill badge

    /// Short text shown next to the notch while a timer runs.
    var collapsedBadge: String? {
        if pomodoroRunning {
            return Self.format(pomodoroRemaining)
        }
        if countdownRunning {
            return Self.format(countdownRemaining)
        }
        if stopwatchRunning {
            return Self.format(stopwatchElapsed)
        }
        return nil
    }

    static func format(_ interval: TimeInterval) -> String {
        let total = max(Int(interval.rounded()), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
