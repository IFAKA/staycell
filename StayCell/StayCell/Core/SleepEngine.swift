import Foundation
import os.log

/// Progressive sleep enforcement state machine.
/// Wind-down → bedtime → post-bedtime → nuclear.
@MainActor
final class SleepEngine {
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "sleep")
    private var windDownTimer: DispatchSourceTimer?

    let appState: AppState
    let blockingEngine: BlockingEngine
    let audioMonitor: AudioMonitor
    let notificationService: NotificationService

    private(set) var sleepPhase: SleepPhase = .normal
    private(set) var bedtime: Date?
    private(set) var extensionUsed = false

    var onPhaseChanged: ((SleepPhase) -> Void)?
    var onShowBedtimeOverlay: (() -> Void)?

    init(
        appState: AppState,
        blockingEngine: BlockingEngine,
        audioMonitor: AudioMonitor,
        notificationService: NotificationService
    ) {
        self.appState = appState
        self.blockingEngine = blockingEngine
        self.audioMonitor = audioMonitor
        self.notificationService = notificationService
    }

    /// Calculate bedtime from day anchor.
    /// Bedtime = earlier of (wake + 16h) or 1:00 AM.
    func calculateBedtime(dayAnchor: Date) {
        let sixteenHoursLater = dayAnchor.addingTimeInterval(16 * 3600)

        // Cap at 1:00 AM next day
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: dayAnchor)
        components.hour = 1
        components.minute = 0
        let nextDay1AM = calendar.date(byAdding: .day, value: 1, to: calendar.date(from: components)!)!

        bedtime = min(sixteenHoursLater, nextDay1AM)

        if let bedtime {
            logger.info("Bedtime calculated: \(bedtime)")
            scheduleWindDown(bedtime: bedtime)
        }
    }

    /// Start monitoring sleep phases.
    func startMonitoring() {
        guard let bedtime else { return }

        let now = Date()
        let timeUntilBedtime = bedtime.timeIntervalSince(now)

        if timeUntilBedtime <= 0 {
            // Already past bedtime
            transitionTo(.bedtime)
        } else if timeUntilBedtime <= 3600 {
            transitionTo(.windDown60)
        }
    }

    /// Handle a 3 AM unlock (midnight-5 AM after 2+ hours locked).
    func handleLateNightUnlock() {
        let hour = Calendar.current.component(.hour, from: Date())
        guard hour >= 0 && hour < 5 else { return }

        logger.warning("Late night unlock detected (3 AM pattern)")
        transitionTo(.nuclear)
    }

    /// User requests a 15 or 30 min extension.
    func requestExtension(minutes: Int) -> Bool {
        guard !extensionUsed else {
            logger.info("Extension already used tonight")
            return false
        }

        extensionUsed = true
        let newBedtime = Date().addingTimeInterval(Double(minutes) * 60)
        bedtime = newBedtime
        transitionTo(.normal)
        scheduleWindDown(bedtime: newBedtime)
        logger.info("Extension granted: \(minutes) min, new bedtime: \(newBedtime)")
        return true
    }

    /// Reset for a new day.
    func reset() {
        sleepPhase = .normal
        extensionUsed = false
        bedtime = nil
        windDownTimer?.cancel()
        windDownTimer = nil
        restoreBrightness()
    }

    // MARK: - Phase Transitions

    private func transitionTo(_ phase: SleepPhase) {
        guard phase != sleepPhase else { return }
        let previousPhase = sleepPhase
        sleepPhase = phase

        logger.info("Sleep phase: \(previousPhase.rawValue) → \(phase.rawValue)")

        switch phase {
        case .normal:
            restoreBrightness()

        case .windDown60:
            // -60 min: notification + tighten blocking
            notificationService.sendWindDownNotification(minutesLeft: 60)
            Task {
                try? await blockingEngine.applyMode(.offline)
            }

        case .windDown30:
            // -30 min: dim to 70%
            notificationService.sendWindDownNotification(minutesLeft: 30)
            setBrightness(0.7)

        case .windDown15:
            // -15 min: "Close your sessions"
            if audioMonitor.isAudioActive {
                logger.info("Active call detected — delaying sleep enforcement")
                waitForCallToEnd()
                return
            }
            notificationService.sendCloseSessionsNotification()

        case .bedtime:
            // Full offline, dim to 30%
            Task {
                try? await blockingEngine.applyMode(.offline)
                appState.currentMode = .offline
            }
            setBrightness(0.3)

        case .postBedtime:
            // +30 min: persistent overlay
            onShowBedtimeOverlay?()

        case .nuclear:
            // +60 min or 3 AM: minimum brightness
            setBrightness(0.1)
            onShowBedtimeOverlay?()
        }

        onPhaseChanged?(phase)
    }

    // MARK: - Scheduling

    private func scheduleWindDown(bedtime: Date) {
        windDownTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 60.0)

        timer.setEventHandler { [weak self] in
            self?.checkSleepPhase()
        }

        timer.resume()
        windDownTimer = timer
    }

    private func checkSleepPhase() {
        guard let bedtime else { return }
        let now = Date()
        let minutesUntil = bedtime.timeIntervalSince(now) / 60

        switch minutesUntil {
        case ...(-60):
            transitionTo(.nuclear)
        case ...(-30):
            transitionTo(.postBedtime)
        case ...0:
            transitionTo(.bedtime)
        case ...15:
            transitionTo(.windDown15)
        case ...30:
            transitionTo(.windDown30)
        case ...60:
            transitionTo(.windDown60)
        default:
            break // Not yet in wind-down
        }
    }

    private func waitForCallToEnd() {
        audioMonitor.onAudioStateChanged = { [weak self] active in
            guard let self, !active else { return }
            // Call ended — resume sleep enforcement after 10 min grace
            DispatchQueue.main.asyncAfter(deadline: .now() + 600) { [weak self] in
                self?.transitionTo(.windDown15)
            }
        }
    }

    // MARK: - Display Brightness

    private func setBrightness(_ level: Float) {
        // IODisplaySetBrightness requires IOKit
        // Using a process-based approach for simplicity
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"System Events\" to set value of slider 1 of group 1 of window \"Displays\" of application process \"System Preferences\" to \(level)"]
        // This doesn't actually work well — use the CoreDisplay private API instead

        // Alternative: use brightness command if available, or fall back to overlay
        logger.info("Setting display brightness to \(level)")

        // For now, log intent — actual IODisplaySetBrightness requires linking IOKit
        // Phase 7 polish can add the proper implementation
    }

    private func restoreBrightness() {
        logger.info("Restoring display brightness")
    }
}

/// Sleep enforcement phases.
enum SleepPhase: String, Sendable {
    case normal        // No sleep enforcement
    case windDown60    // -60 min: notification + tighten blocking
    case windDown30    // -30 min: dim display
    case windDown15    // -15 min: close sessions prompt
    case bedtime       // Full offline + dimmed
    case postBedtime   // +30 min: persistent overlay
    case nuclear       // +60 min: minimum brightness
}
