import Foundation
import GRDB
import os.log

/// State machine managing mode transitions, timer lifecycle, and session tracking.
@MainActor
final class ModeEngine {
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "mode")

    let timerEngine: TimerEngine
    let blockingEngine: BlockingEngine
    let notificationService: NotificationService
    let appState: AppState
    private var dbPool: DatabasePool?

    private(set) var currentSession: Session?
    private(set) var sessionCount = 0 // Sessions completed today

    /// Called when a session starts and an intention prompt is needed.
    var onIntentionNeeded: ((@escaping (String?) -> Void) -> Void)?
    /// Called when a session ends and completion confirmation is needed.
    var onCompletionPrompt: ((@escaping (Bool) -> Void) -> Void)?
    /// Called when mode changes.
    var onModeChanged: ((Mode) -> Void)?

    init(
        timerEngine: TimerEngine,
        blockingEngine: BlockingEngine,
        notificationService: NotificationService,
        appState: AppState
    ) {
        self.timerEngine = timerEngine
        self.blockingEngine = blockingEngine
        self.notificationService = notificationService
        self.appState = appState

        setupTimerCallbacks()
    }

    func setDatabase(_ db: DatabasePool) {
        self.dbPool = db
    }

    // MARK: - Session Control

    /// Start a deep work session with an optional intention.
    func startDeepWork(intention: String? = nil) {
        let intent = intention ?? appState.currentSessionIntention
        beginSession(mode: .deepWork, intention: intent)
    }

    /// Start a shallow work session (no intention prompt).
    func startShallowWork() {
        beginSession(mode: .shallowWork, intention: nil)
    }

    /// Start a break.
    func startBreak() {
        beginSession(mode: .personalTime, intention: nil, durationMinutes: TimerDurations.breakMinutes)
        notificationService.sendBreakStarted()
    }

    /// End the current session early.
    func endCurrentSession() {
        guard var session = currentSession else { return }
        session.markAbandoned()
        saveSession(session)
        currentSession = nil
        timerEngine.stop()
        logger.info("Session abandoned: \(session.mode)")
    }

    /// Switch to a mode without starting a timed session.
    func switchMode(to mode: Mode) {
        // End any running session
        if currentSession != nil {
            endCurrentSession()
        }

        Task {
            do {
                try await blockingEngine.applyMode(mode)
                appState.currentMode = mode
                onModeChanged?(mode)
                logger.info("Switched to \(mode.rawValue)")
            } catch let error as StayCellError {
                appState.setError(error)
            } catch {
                appState.setError(.xpcConnectionFailed(underlying: error.localizedDescription))
            }
        }
    }

    // MARK: - Private

    private func beginSession(mode: Mode, intention: String?, durationMinutes: Int? = nil) {
        // End any existing session
        if var existing = currentSession {
            existing.markAbandoned()
            saveSession(existing)
        }

        let duration = durationMinutes ?? (mode == .deepWork ? TimerDurations.deepWorkMinutes : TimerDurations.breakMinutes)

        var session = Session.start(mode: mode, intention: intention, durationMinutes: duration)
        saveSession(session)
        currentSession = session

        // Apply blocking rules
        Task {
            do {
                try await blockingEngine.applyMode(mode)
                appState.currentMode = mode
                onModeChanged?(mode)
            } catch let error as StayCellError {
                appState.setError(error)
            } catch {
                appState.setError(.xpcConnectionFailed(underlying: error.localizedDescription))
            }
        }

        // Start timer
        timerEngine.start(durationMinutes: duration)
        logger.info("Session started: \(mode.rawValue), \(duration) min, intention: \(intention ?? "none")")
    }

    private func setupTimerCallbacks() {
        timerEngine.onComplete = { [weak self] in
            self?.handleSessionComplete()
        }

        timerEngine.onMilestone = { [weak self] minutes in
            guard let self else { return }
            // Movement reminder at 45 minutes into deep work
            if minutes == 45 && self.appState.currentMode == .deepWork {
                self.notificationService.sendMovementReminder()
            }
        }
    }

    private func handleSessionComplete() {
        guard var session = currentSession else { return }

        notificationService.sendSessionComplete()

        let wasDeepWork = session.mode == Mode.deepWork.rawValue
        let wasBreak = session.mode == Mode.personalTime.rawValue && session.plannedDurationSeconds <= TimerDurations.breakMinutes * 60

        session.markCompleted()
        saveSession(session)
        currentSession = nil

        if wasDeepWork {
            sessionCount += 1
            logger.info("Deep work session #\(self.sessionCount) completed")
            // Auto-transition to break
            startBreak()
        } else if wasBreak {
            logger.info("Break completed")
            // After break, switch to personal time (user decides when to start next session)
            switchMode(to: .personalTime)
        }
    }

    private func saveSession(_ session: Session) {
        guard let dbPool else {
            logger.warning("No database — session not saved")
            return
        }
        do {
            try dbPool.write { db in
                var s = session
                try s.save(db)
            }
        } catch {
            logger.error("Failed to save session: \(error.localizedDescription)")
        }
    }
}
