import Foundation
import GRDB

/// Records each foreground app activation.
/// Used to measure app-switching frequency before override attempts.
struct AppEvent: Codable, Sendable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var timestamp: Date
    var appName: String
    var bundleId: String?
    /// FK to sessions table — nil for switches outside active sessions.
    var sessionId: Int64?

    static let databaseTableName = "app_events"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
