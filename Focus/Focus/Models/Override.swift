import Foundation
import GRDB

/// Records every override attempt and outcome.
struct Override: Codable, Sendable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var attemptedAt: Date
    var mode: String
    var overrideLevel: Int       // 1st, 2nd, 3rd attempt
    var granted: Bool            // Did the user complete the gate?
    var cancelled: Bool          // Did the user cancel?
    var phraseUsed: String
    var typingDurationSeconds: Int?
    var sessionIntention: String?

    static let databaseTableName = "overrides"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension Override {
    /// Create a new override attempt record.
    static func attempt(mode: FocusMode, level: Int, phrase: String, intention: String?) -> Override {
        Override(
            attemptedAt: Date(),
            mode: mode.rawValue,
            overrideLevel: level,
            granted: false,
            cancelled: false,
            phraseUsed: phrase,
            sessionIntention: intention
        )
    }

    /// Count overrides in the last hour for tamper detection.
    static func countInLastHour(db: Database) throws -> Int {
        let oneHourAgo = Date().addingTimeInterval(-3600)
        return try Override
            .filter(Column("attemptedAt") >= oneHourAgo)
            .fetchCount(db)
    }

    /// Count overrides today for escalation.
    static func countToday(db: Database) throws -> Int {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return try Override
            .filter(Column("attemptedAt") >= startOfDay)
            .filter(Column("granted") == true)
            .fetchCount(db)
    }
}
