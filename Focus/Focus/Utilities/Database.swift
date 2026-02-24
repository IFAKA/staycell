import Foundation
import GRDB
import os.log

/// GRDB database setup and migrations.
/// Phase 1: minimal setup. Sessions, overrides, daily stats added in later phases.
enum DatabaseManager {
    private static let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "database")

    /// Path to the user's database file.
    static var databasePath: String {
        let dir = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first!
        let appDir = (dir as NSString).appendingPathComponent("Focus")
        try? FileManager.default.createDirectory(atPath: appDir, withIntermediateDirectories: true)
        return (appDir as NSString).appendingPathComponent("focus.db")
    }

    /// Create and configure the database connection pool.
    static func openDatabase() throws -> DatabasePool {
        let dbPool = try DatabasePool(path: databasePath)

        // Run migrations
        var migrator = DatabaseMigrator()

        // Phase 2 will add: sessions, overrides, daily_stats
        migrator.registerMigration("v1_initial") { db in
            // App metadata table for internal state
            try db.create(table: "app_meta") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
        }

        migrator.registerMigration("v2_sessions") { db in
            try db.create(table: "sessions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("mode", .text).notNull()
                t.column("intention", .text)
                t.column("startedAt", .datetime).notNull()
                t.column("endedAt", .datetime)
                t.column("plannedDurationSeconds", .integer).notNull()
                t.column("actualDurationSeconds", .integer)
                t.column("completed", .boolean).notNull().defaults(to: false)
                t.column("abandoned", .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("v3_overrides") { db in
            try db.create(table: "overrides") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("attemptedAt", .datetime).notNull()
                t.column("mode", .text).notNull()
                t.column("overrideLevel", .integer).notNull()
                t.column("granted", .boolean).notNull().defaults(to: false)
                t.column("cancelled", .boolean).notNull().defaults(to: false)
                t.column("phraseUsed", .text).notNull()
                t.column("typingDurationSeconds", .integer)
                t.column("sessionIntention", .text)
            }
        }

        try migrator.migrate(dbPool)
        logger.info("Database opened at \(databasePath)")
        return dbPool
    }
}
