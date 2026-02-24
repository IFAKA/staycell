import Foundation
import os.log

/// Central observable state for the StayCell app.
/// Persisted to UserDefaults for crash recovery.
@Observable
@MainActor
final class AppState {
    // MARK: - Current State

    var currentMode: Mode {
        didSet { persist() }
    }

    var isOnboardingComplete: Bool {
        didSet { UserDefaults.standard.set(isOnboardingComplete, forKey: Keys.onboardingComplete) }
    }

    var isDaemonInstalled: Bool {
        didSet { UserDefaults.standard.set(isDaemonInstalled, forKey: Keys.daemonInstalled) }
    }

    var lastError: StayCellError?
    var hasError: Bool { lastError != nil }

    // MARK: - Error Log

    struct ErrorLogEntry: Identifiable, Sendable {
        let id = UUID()
        let timestamp: Date
        let message: String
        let suggestion: String
        let context: [String: String]
    }

    private(set) var errorLog: [ErrorLogEntry] = []

    // MARK: - Timer State

    var timerRemainingSeconds: Int = 0
    var timerIsRunning: Bool = false
    var currentSessionIntention: String?
    var sessionsCompletedToday: Int = 0

    // MARK: - Schedule Auto-Switch

    /// Set when the user manually switches mode. The auto-switch timer respects this
    /// and skips auto-switching until the next schedule block starts.
    var lastManualModeSwitchTime: Date? {
        didSet {
            if let t = lastManualModeSwitchTime {
                UserDefaults.standard.set(t, forKey: Keys.lastManualModeSwitchTime)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.lastManualModeSwitchTime)
            }
        }
    }

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
        return (dir as NSString).appendingPathComponent("StayCell/dirty_shutdown")
    }()

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard
        self.currentMode = Mode(rawValue: defaults.string(forKey: Keys.currentMode) ?? "") ?? .personalTime
        self.isOnboardingComplete = defaults.bool(forKey: Keys.onboardingComplete)
        self.isDaemonInstalled = defaults.bool(forKey: Keys.daemonInstalled)
        self.lastManualModeSwitchTime = defaults.object(forKey: Keys.lastManualModeSwitchTime) as? Date
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

    func setError(_ error: StayCellError, context: [String: String] = [:]) {
        lastError = error
        let ctx = context.merging(["mode": currentMode.rawValue]) { existing, _ in existing }
        let entry = ErrorLogEntry(
            timestamp: Date(),
            message: error.localizedDescription,
            suggestion: error.suggestion,
            context: ctx
        )
        errorLog.append(entry)
        if errorLog.count > 50 { errorLog.removeFirst() }
        logError(error, context: ctx)
    }

    func clearError() {
        lastError = nil
    }

    func clearErrorLog() {
        errorLog = []
    }

    /// Formats the error log as a plain-text block ready to paste into an AI agent.
    var errorLogForAI: String {
        guard !errorLog.isEmpty else { return "No errors recorded." }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return errorLog.map { entry in
            let ctx = entry.context.isEmpty ? "" : "\n  Context: \(entry.context.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))"
            return "[\(formatter.string(from: entry.timestamp))] \(entry.message)\(ctx)\n  Fix: \(entry.suggestion)"
        }.joined(separator: "\n\n")
    }

    private enum Keys {
        static let currentMode = "staycell.currentMode"
        static let onboardingComplete = "staycell.onboardingComplete"
        static let daemonInstalled = "staycell.daemonInstalled"
        static let lastManualModeSwitchTime = "staycell.lastManualModeSwitchTime"
        static let workdayStartHour = "staycell.workdayStartHour"
        static let workDays = "staycell.workDays"
    }
}
