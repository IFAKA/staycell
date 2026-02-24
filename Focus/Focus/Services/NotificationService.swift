import UserNotifications
import os.log

/// Manages local notifications for prayer offices, movement reminders, and session events.
@MainActor
final class NotificationService {
    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "notifications")

    func requestPermission() {
        Task {
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                logger.info("Notification permission: \(granted)")
            } catch {
                logger.warning("Notification permission request failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Prayer Office Notifications

    func schedulePrayerNotification(title: String, at date: Date, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.sound = .default

        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(request) { [weak self] error in
            if let error {
                self?.logger.warning("Failed to schedule notification '\(identifier)': \(error.localizedDescription)")
            }
        }
    }

    func scheduleSolarPrayers(solarTimes: SolarCalculator.SolarTimes) {
        // Remove old prayer notifications
        center.removePendingNotificationRequests(withIdentifiers: [
            "prayer.sunrise", "prayer.solarNoon", "prayer.sunset",
        ])

        schedulePrayerNotification(
            title: "Prime — Morning Prayer",
            at: solarTimes.sunrise,
            identifier: "prayer.sunrise"
        )

        schedulePrayerNotification(
            title: "Sext — Sixth Hour",
            at: solarTimes.solarNoon,
            identifier: "prayer.solarNoon"
        )

        schedulePrayerNotification(
            title: "Vespers — Evening Prayer",
            at: solarTimes.sunset,
            identifier: "prayer.sunset"
        )

        logger.info("Scheduled prayer notifications for today")
    }

    // MARK: - Movement Reminders

    func sendMovementReminder() {
        let content = UNMutableNotificationContent()
        content.title = "Stand up. Stretch. 60 seconds."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "movement.\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // Immediate
        )

        center.add(request)
    }

    func sendExtendedSedentaryWarning(hours: Int) {
        let content = UNMutableNotificationContent()
        content.title = "You've been seated for \(hours) hours."
        content.body = "Take a 10-minute walk."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "sedentary.\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        center.add(request)
    }

    // MARK: - Session Notifications

    func sendBreakStarted() {
        let content = UNMutableNotificationContent()
        content.title = "Break Time"
        content.body = "Walk for 5 minutes before your next session."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "break.\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        center.add(request)
    }

    func sendSessionComplete() {
        let content = UNMutableNotificationContent()
        content.title = "Session Complete"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "session.complete.\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        center.add(request)
    }

    func removeAllPending() {
        center.removeAllPendingNotificationRequests()
    }
}
