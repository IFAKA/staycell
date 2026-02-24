import AppKit
import os.log

/// Detects first screen unlock of the day to set the day anchor.
/// Uses NSWorkspace + DistributedNotificationCenter (event-driven, no polling).
@MainActor
final class WakeDetector {
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "wake")
    private var hasDetectedFirstUnlock = false

    /// The anchor time for today's schedule.
    private(set) var dayAnchor: Date?

    /// Called when the day anchor is set or updated.
    var onDayAnchorSet: ((Date) -> Void)?

    func startMonitoring() {
        // Screen unlock via DistributedNotificationCenter
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenDidUnlock),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )

        // Wake from sleep
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        // Screen lock (for break/sleep detection)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenDidLock),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )

        // Set initial anchor if launching fresh
        if dayAnchor == nil {
            setDayAnchor(Date())
        }

        logger.info("Wake detector started monitoring")
    }

    func stopMonitoring() {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// Reset for a new day (called at midnight or after long sleep).
    func resetForNewDay() {
        hasDetectedFirstUnlock = false
        dayAnchor = nil
        logger.info("Wake detector reset for new day")
    }

    // MARK: - Notifications

    @objc private func screenDidUnlock() {
        let now = Date()

        if !hasDetectedFirstUnlock || isNewDay(now) {
            hasDetectedFirstUnlock = true
            setDayAnchor(now)
            logger.info("First unlock detected — day anchor set to \(now)")
        }
    }

    @objc private func systemDidWake() {
        // System woke from sleep — check if it's a new day
        let now = Date()
        if isNewDay(now) {
            resetForNewDay()
            screenDidUnlock()
        }
    }

    @objc private func screenDidLock() {
        logger.info("Screen locked")
        // Future: track for break detection and movement proxy
    }

    // MARK: - Private

    private func setDayAnchor(_ date: Date) {
        dayAnchor = date
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "staycell.dayAnchor")
        onDayAnchorSet?(date)
    }

    private func isNewDay(_ date: Date) -> Bool {
        guard let anchor = dayAnchor else { return true }
        return !Calendar.current.isDate(date, inSameDayAs: anchor)
    }
}
