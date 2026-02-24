import Foundation
import GRDB

/// A focus session record.
struct Session: Codable, Sendable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var mode: String
    var intention: String?
    var startedAt: Date
    var endedAt: Date?
    var plannedDurationSeconds: Int
    var actualDurationSeconds: Int?
    var completed: Bool
    var abandoned: Bool

    static let databaseTableName = "sessions"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension Session {
    /// Create a new session for the given mode.
    static func start(mode: FocusMode, intention: String?, durationMinutes: Int) -> Session {
        Session(
            mode: mode.rawValue,
            intention: intention?.trimmingCharacters(in: .whitespacesAndNewlines),
            startedAt: Date(),
            plannedDurationSeconds: durationMinutes * 60,
            completed: false,
            abandoned: false
        )
    }

    /// Mark the session as completed normally.
    mutating func markCompleted() {
        endedAt = Date()
        actualDurationSeconds = Int(endedAt!.timeIntervalSince(startedAt))
        completed = true
    }

    /// Mark the session as abandoned (ended early).
    mutating func markAbandoned() {
        endedAt = Date()
        actualDurationSeconds = Int(endedAt!.timeIntervalSince(startedAt))
        abandoned = true
    }
}
