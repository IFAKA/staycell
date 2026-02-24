import Foundation
import os.log

/// Central observable state for the Focus app.
/// Persisted to UserDefaults for crash recovery.
@Observable
@MainActor
final class AppState {
    // MARK: - Current State

    var currentMode: FocusMode {
        didSet { persist() }
    }

    var isOnboardingComplete: Bool {
        didSet { UserDefaults.standard.set(isOnboardingComplete, forKey: Keys.onboardingComplete) }
    }

    var isDaemonInstalled: Bool {
        didSet { UserDefaults.standard.set(isDaemonInstalled, forKey: Keys.daemonInstalled) }
    }

    var lastError: FocusError?
    var hasError: Bool { lastError != nil }

    // MARK: - Day Schedule

    var workdayStartHour: Int {
        didSet { UserDefaults.standard.set(workdayStartHour, forKey: Keys.workdayStartHour) }
    }

    var workDays: Set<Int> {
        didSet {
            UserDefaults.standard.set(Array(workDays), forKey: Keys.workDays)
        }
    }

    // MARK: - Dirty Shutdown Detection

    var isDirtyShutdown: Bool {
        FileManager.default.fileExists(atPath: dirtyFlagPath)
    }

    private let dirtyFlagPath: String = {
        let dir = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first!
        return (dir as NSString).appendingPathComponent("Focus/dirty_shutdown")
    }()

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard
        self.currentMode = FocusMode(rawValue: defaults.string(forKey: Keys.currentMode) ?? "") ?? .personalTime
        self.isOnboardingComplete = defaults.bool(forKey: Keys.onboardingComplete)
        self.isDaemonInstalled = defaults.bool(forKey: Keys.daemonInstalled)
        self.workdayStartHour = defaults.object(forKey: Keys.workdayStartHour) as? Int ?? 9
        let savedDays = defaults.array(forKey: Keys.workDays) as? [Int]
        self.workDays = Set(savedDays ?? [2, 3, 4, 5, 6]) // Mon-Fri (Calendar weekday: Sun=1)

        setDirtyFlag()
    }

    // MARK: - Persistence

    private func persist() {
        UserDefaults.standard.set(currentMode.rawValue, forKey: Keys.currentMode)
    }

    func setDirtyFlag() {
        let dir = (dirtyFlagPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dirtyFlagPath, contents: nil)
    }

    func clearDirtyFlag() {
        try? FileManager.default.removeItem(atPath: dirtyFlagPath)
    }

    // MARK: - Error Handling

    func setError(_ error: FocusError) {
        lastError = error
        logError(error, context: ["mode": currentMode.rawValue])
    }

    func clearError() {
        lastError = nil
    }

    private enum Keys {
        static let currentMode = "focus.currentMode"
        static let onboardingComplete = "focus.onboardingComplete"
        static let daemonInstalled = "focus.daemonInstalled"
        static let workdayStartHour = "focus.workdayStartHour"
        static let workDays = "focus.workDays"
    }
}
