import Foundation
import GRDB

/// Aggregated daily statistics, computed from sessions and overrides.
struct DailyStats: Codable, Sendable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var date: String // ISO date: "2026-02-24"
    var deepWorkMinutes: Int
    var shallowWorkMinutes: Int
    var sessionsCompleted: Int
    var sessionsAbandoned: Int
    var overrideCount: Int
    var overridesGranted: Int

    static let databaseTableName = "daily_stats"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension DailyStats {
    /// Compute stats for a given date from raw session/override data.
    static func compute(for date: Date, in db: Database) throws -> DailyStats {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let dateString = ISO8601DateFormatter.dateOnly.string(from: date)

        let sessions = try Session
            .filter(Column("startedAt") >= startOfDay && Column("startedAt") < endOfDay)
            .fetchAll(db)

        let deepWork = sessions
            .filter { $0.mode == FocusMode.deepWork.rawValue && $0.completed }
            .compactMap(\.actualDurationSeconds)
            .reduce(0, +) / 60

        let shallowWork = sessions
            .filter { $0.mode == FocusMode.shallowWork.rawValue && $0.completed }
            .compactMap(\.actualDurationSeconds)
            .reduce(0, +) / 60

        let completed = sessions.filter(\.completed).count
        let abandoned = sessions.filter(\.abandoned).count

        let overrides = try Override
            .filter(Column("attemptedAt") >= startOfDay && Column("attemptedAt") < endOfDay)
            .fetchAll(db)

        return DailyStats(
            date: dateString,
            deepWorkMinutes: deepWork,
            shallowWorkMinutes: shallowWork,
            sessionsCompleted: completed,
            sessionsAbandoned: abandoned,
            overrideCount: overrides.count,
            overridesGranted: overrides.filter(\.granted).count
        )
    }
}

extension ISO8601DateFormatter {
    nonisolated(unsafe) static let dateOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}
