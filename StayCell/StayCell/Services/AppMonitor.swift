import AppKit
import GRDB
import os.log

/// Observes NSWorkspace app-activation events and persists them as AppEvent rows.
/// Used downstream to compute app-switching frequency around override attempts.
@MainActor
final class AppMonitor {
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "appmonitor")
    private var dbPool: DatabasePool?

    func setDatabase(_ pool: DatabasePool) {
        dbPool = pool
    }

    func startMonitoring() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Extract Sendable data before the Task boundary to avoid data races.
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let appName = app?.localizedName ?? "Unknown"
            let bundleId = app?.bundleIdentifier
            Task { @MainActor in
                self?.persistActivation(appName: appName, bundleId: bundleId)
            }
        }
        logger.info("AppMonitor started")
    }

    func stopMonitoring() {
        NSWorkspace.shared.notificationCenter.removeObserver(
            self,
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    /// Count app activations in the last N minutes.
    /// Called synchronously from logOverride on the main thread.
    func switchesInLast(minutes: Int) -> Int {
        guard let dbPool else { return 0 }
        let since = Date().addingTimeInterval(-Double(minutes * 60))
        do {
            return try dbPool.read { db in
                try AppEvent.filter(Column("timestamp") >= since).fetchCount(db)
            }
        } catch {
            return 0
        }
    }

    /// Prune app_events older than 30 days. Call on app launch to keep DB lean.
    func pruneOldEvents() {
        guard let dbPool else { return }
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        Task.detached {
            try? await dbPool.write { db in
                try AppEvent.filter(Column("timestamp") < cutoff).deleteAll(db)
            }
        }
    }

    // MARK: - Private

    private func persistActivation(appName: String, bundleId: String?) {
        guard let dbPool else { return }
        let event = AppEvent(timestamp: Date(), appName: appName, bundleId: bundleId, sessionId: nil)
        Task.detached {
            try? await dbPool.write { db in
                try db.execute(
                    sql: "INSERT INTO app_events (timestamp, appName, bundleId) VALUES (?, ?, ?)",
                    arguments: [event.timestamp, event.appName, event.bundleId as DatabaseValueConvertible?]
                )
            }
        }
    }
}
