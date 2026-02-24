import Foundation
import GRDB
import os.log

/// JSON data export for all StayCell app data.
enum DataExportService {
    private static let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "export")

    struct ExportData: Codable {
        let exportDate: String
        let sessions: [Session]
        let overrides: [Override]
        let fireSnapshots: [FIRESnapshot]
    }

    /// Export all data as JSON to the given URL.
    static func exportJSON(from dbPool: DatabasePool, to url: URL) throws {
        let data = try dbPool.read { db in
            let sessions = try Session.order(Column("startedAt").desc).fetchAll(db)
            let overrides = try Override.order(Column("attemptedAt").desc).fetchAll(db)
            let snapshots = try FIRESnapshot.order(Column("date").desc).fetchAll(db)

            return ExportData(
                exportDate: ISO8601DateFormatter().string(from: Date()),
                sessions: sessions,
                overrides: overrides,
                fireSnapshots: snapshots
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(data)
        try jsonData.write(to: url)

        logger.info("Exported data to \(url.path)")
    }
}
