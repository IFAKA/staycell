import Foundation
import os.log

/// DispatchSourceTimer-based countdown engine.
/// Persists start timestamp for crash recovery (not count-based).
@MainActor
final class TimerEngine {
    private var timer: DispatchSourceTimer?
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "timer")

    // MARK: - State

    private(set) var isRunning = false
    private(set) var startDate: Date?
    private(set) var totalDurationSeconds: Int = 0
    private(set) var elapsedSeconds: Int = 0

    var remainingSeconds: Int {
        max(0, totalDurationSeconds - elapsedSeconds)
    }

    var remainingMinutes: Int {
        remainingSeconds / 60
    }

    var progress: Double {
        guard totalDurationSeconds > 0 else { return 0 }
        return Double(elapsedSeconds) / Double(totalDurationSeconds)
    }

    // MARK: - Callbacks

    var onTick: ((Int) -> Void)?
    var onComplete: (() -> Void)?
    var onMilestone: ((Int) -> Void)? // Called at specific minute marks (e.g., 45 min for movement)

    // MARK: - Public API

    func start(durationMinutes: Int) {
        stop()

        totalDurationSeconds = durationMinutes * 60
        elapsedSeconds = 0
        startDate = Date()
        isRunning = true

        persistState()
        startDispatchTimer()

        logger.info("Timer started: \(durationMinutes) minutes")
    }

    func stop() {
        timer?.cancel()
        timer = nil
        isRunning = false
        startDate = nil
        elapsedSeconds = 0
        totalDurationSeconds = 0
        clearPersistedState()
    }

    /// Recover timer state after crash/restart.
    /// Returns true if a session was recovered.
    func recoverIfNeeded() -> Bool {
        let defaults = UserDefaults.standard
        guard let startTimestamp = defaults.object(forKey: Keys.timerStart) as? TimeInterval,
              let duration = defaults.object(forKey: Keys.timerDuration) as? Int
        else {
            return false
        }

        let start = Date(timeIntervalSince1970: startTimestamp)
        let elapsed = Int(Date().timeIntervalSince(start))

        if elapsed >= duration {
            // Session already ended during crash
            clearPersistedState()
            logger.info("Recovered expired timer session — marking as complete")
            return false
        }

        // Resume the session
        startDate = start
        totalDurationSeconds = duration
        elapsedSeconds = elapsed
        isRunning = true

        startDispatchTimer()

        logger.info("Recovered timer: \(elapsed)/\(duration) seconds elapsed")
        return true
    }

    // MARK: - Private

    private func startDispatchTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1.0)

        timer.setEventHandler { [weak self] in
            self?.tick()
        }

        timer.resume()
        self.timer = timer
    }

    private func tick() {
        guard isRunning, let startDate else { return }

        elapsedSeconds = Int(Date().timeIntervalSince(startDate))

        onTick?(remainingSeconds)

        // Movement reminder at 45 minutes
        let elapsedMinutes = elapsedSeconds / 60
        if elapsedSeconds % 60 == 0 && elapsedMinutes > 0 {
            onMilestone?(elapsedMinutes)
        }

        if elapsedSeconds >= totalDurationSeconds {
            logger.info("Timer completed")
            isRunning = false
            timer?.cancel()
            timer = nil
            clearPersistedState()
            onComplete?()
        }
    }

    private func persistState() {
        let defaults = UserDefaults.standard
        defaults.set(startDate?.timeIntervalSince1970, forKey: Keys.timerStart)
        defaults.set(totalDurationSeconds, forKey: Keys.timerDuration)
    }

    private func clearPersistedState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.timerStart)
        defaults.removeObject(forKey: Keys.timerDuration)
    }

    private enum Keys {
        static let timerStart = "focus.timer.startTimestamp"
        static let timerDuration = "focus.timer.durationSeconds"
    }
}
