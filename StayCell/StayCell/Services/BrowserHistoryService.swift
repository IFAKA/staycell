import Foundation
import GRDB
import os.log
import IOKit

// MARK: - Output types

struct BrowserSnapshot: Sendable {
    let navIntent: String?
    let reloadCount: Int
    let tabsOpened: Int
    let backNavRatio: Double
}

// MARK: - Service

/// Imports Chromium-family browser history once per day and provides
/// fast per-override context snapshots. No special permissions required —
/// reads the user's own SQLite files from ~/Library/Application Support/.
@MainActor
final class BrowserHistoryService {
    private var dbPool: DatabasePool?
    nonisolated private static let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "browserHistory")
    nonisolated private static let lastImportKey = "staycell.browserHistoryLastImport"

    // nonisolated so static helpers and contextSnapshot can access without actor hop
    nonisolated static let browserPaths: [(name: String, relativePath: String)] = [
        ("Brave",  "BraveSoftware/Brave-Browser/Default/History"),
        ("Chrome", "Google/Chrome/Default/History"),
        ("Arc",    "Arc/User Data/Default/History"),
        ("Edge",   "Microsoft Edge/Default/History"),
    ]

    func setDatabase(_ pool: DatabasePool) {
        dbPool = pool
    }

    /// Import once per calendar day. Safe to call at app launch.
    func importIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        if let last = UserDefaults.standard.object(forKey: Self.lastImportKey) as? Date,
           last >= today { return }
        guard let pool = dbPool else { return }
        Task.detached {
            await BrowserHistoryService.runImport(dbPool: pool)
        }
    }

    // MARK: - Import pipeline (nonisolated async — runs off main actor)

    private nonisolated static func runImport(dbPool: DatabasePool) async {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first!
        for browser in browserPaths {
            let historyURL = appSupport.appendingPathComponent(browser.relativePath)
            guard FileManager.default.fileExists(atPath: historyURL.path) else { continue }
            do {
                try await importBrowser(name: browser.name, historyURL: historyURL, into: dbPool)
            } catch {
                logger.error("Browser import failed [\(browser.name)]: \(error.localizedDescription)")
            }
        }
        UserDefaults.standard.set(Date(), forKey: lastImportKey)
    }

    private nonisolated static func importBrowser(
        name: String,
        historyURL: URL,
        into dbPool: DatabasePool
    ) async throws {
        // Copy to a temp file so we don't contend with the browser's lock
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("staycell_\(name)_history_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.copyItem(at: historyURL, to: tmp)

        var config = Configuration()
        config.readonly = true
        let sourceDB = try DatabaseQueue(path: tmp.path, configuration: config)

        // Find last imported Chrome timestamp for this browser
        let lastChrome: Int64 = try await dbPool.read { db in
            let lastDate = try Date.fetchOne(
                db,
                sql: "SELECT MAX(visitedAt) FROM browsing_visits WHERE browser = ?",
                arguments: [name]
            )
            guard let d = lastDate else {
                // First import: go back 90 days
                return toChrome(Date().addingTimeInterval(-90 * 86400))
            }
            return toChrome(d)
        }

        let rows: [Row] = try await sourceDB.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT v.visit_time, v.visit_duration, v.transition,
                       v.opener_visit, u.url, u.title
                FROM visits v JOIN urls u ON v.url = u.id
                WHERE v.visit_time > ?
                ORDER BY v.visit_time ASC
                """,
                arguments: [lastChrome]
            )
        }

        guard !rows.isEmpty else { return }

        // Extract values before entering write (Row is @unchecked Sendable)
        struct VisitRecord: Sendable {
            let visitedAt: Date
            let url: String
            let domain: String
            let title: String?
            let durationSecs: Int
            let navIntent: String
            let isNewTab: Bool
        }

        var records: [VisitRecord] = []
        for row in rows {
            let urlStr: String = row["url"]
            guard urlStr.hasPrefix("http://") || urlStr.hasPrefix("https://") else { continue }
            let chromeTime: Int64 = row["visit_time"]
            let visitedAt = fromChrome(chromeTime)
            let durationMicro: Int64 = row["visit_duration"] ?? 0
            let durationSecs = Int(durationMicro / 1_000_000)
            let transition: Int64 = row["transition"] ?? 0
            let openerVisit: Int64? = row["opener_visit"]
            let title: String? = row["title"]
            let navIntent = classifyIntent(transition)
            let isNewTab = openerVisit != nil && openerVisit != 0
            guard let domain = extractDomain(from: urlStr) else { continue }
            records.append(VisitRecord(
                visitedAt: visitedAt, url: urlStr, domain: domain, title: title,
                durationSecs: durationSecs, navIntent: navIntent, isNewTab: isNewTab
            ))
        }

        guard !records.isEmpty else { return }

        let finalRecords = records  // immutable copy for the write closure
        try await dbPool.write { db in
            for r in finalRecords {
                try db.execute(
                    sql: """
                    INSERT INTO browsing_visits
                      (visitedAt, url, domain, title, durationSeconds, navIntent, isNewTab, browser)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [r.visitedAt, r.url, r.domain, r.title, r.durationSecs, r.navIntent, r.isNewTab, name]
                )
            }
        }

        logger.info("[\(name)] imported \(records.count) visits")
    }

    // MARK: - Context snapshot (synchronous, called at override time)

    /// Read browser context for the domain currently in focus.
    /// Returns nil if no supported browser is frontmost or queries fail.
    nonisolated static func contextSnapshot(bundleId: String?, domain: String?) -> BrowserSnapshot? {
        guard let bundleId else { return nil }

        let browserName: String
        switch bundleId {
        case _ where bundleId.lowercased().contains("brave"):   browserName = "Brave"
        case _ where bundleId.lowercased().contains("chrome"):  browserName = "Chrome"
        case _ where bundleId.lowercased().contains("arc"):     browserName = "Arc"
        case _ where bundleId.lowercased().contains("edge"):    browserName = "Edge"
        default: return nil
        }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first!
        guard let path = browserPaths.first(where: { $0.name == browserName })?.relativePath else {
            return nil
        }
        let historyURL = appSupport.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: historyURL.path) else { return nil }

        do {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("staycell_snap_\(UUID().uuidString).db")
            defer { try? FileManager.default.removeItem(at: tmp) }
            try FileManager.default.copyItem(at: historyURL, to: tmp)

            var config = Configuration()
            config.readonly = true
            let db = try DatabaseQueue(path: tmp.path, configuration: config)

            return try db.read { db in
                let now = Date()
                let t30m = toChrome(now.addingTimeInterval(-30 * 60))
                let t15m = toChrome(now.addingTimeInterval(-15 * 60))
                let t60m = toChrome(now.addingTimeInterval(-60 * 60))

                // Last navIntent for this domain in last 30 min
                let lastTransition: String? = try Row.fetchOne(
                    db,
                    sql: """
                    SELECT v.transition FROM visits v JOIN urls u ON v.url = u.id
                    WHERE u.url LIKE ? AND v.visit_time > ?
                    ORDER BY v.visit_time DESC LIMIT 1
                    """,
                    arguments: ["%\(domain ?? "")%", t30m]
                ).map { classifyIntent($0["transition"] as Int64) }

                // Reload count for this domain in last 30 min
                let reloadCount: Int = try Int.fetchOne(
                    db,
                    sql: """
                    SELECT COUNT(*) FROM visits v JOIN urls u ON v.url = u.id
                    WHERE u.url LIKE ? AND (v.transition & 255) = 8 AND v.visit_time > ?
                    """,
                    arguments: ["%\(domain ?? "")%", t30m]
                ) ?? 0

                // New tabs opened in last hour
                let tabsOpened: Int = try Int.fetchOne(
                    db,
                    sql: """
                    SELECT COUNT(*) FROM visits
                    WHERE opener_visit IS NOT NULL AND opener_visit != 0 AND visit_time > ?
                    """,
                    arguments: [t60m]
                ) ?? 0

                // Back-forward ratio in last 15 min
                let totalVisits: Int = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM visits WHERE visit_time > ?",
                    arguments: [t15m]
                ) ?? 0
                let backFwdVisits: Int = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM visits WHERE (transition & 16777216) != 0 AND visit_time > ?",
                    arguments: [t15m]
                ) ?? 0
                let backNavRatio = totalVisits > 0
                    ? Double(backFwdVisits) / Double(totalVisits)
                    : 0.0

                return BrowserSnapshot(
                    navIntent: lastTransition,
                    reloadCount: reloadCount,
                    tabsOpened: tabsOpened,
                    backNavRatio: backNavRatio
                )
            }
        } catch {
            return nil
        }
    }

    // MARK: - IOKit idle time

    /// Seconds since last keyboard/mouse event using IOKit HIDIdleTime.
    /// Returns 0 if query fails. No special permissions required.
    nonisolated static func systemIdleSeconds() -> Int {
        var ioIterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOHIDSystem"),
            &ioIterator
        ) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(ioIterator) }

        let service = IOIteratorNext(ioIterator)
        guard service != IO_OBJECT_NULL else { return 0 }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            service, &properties, kCFAllocatorDefault, 0
        ) == KERN_SUCCESS else { return 0 }

        guard let dict = properties?.takeRetainedValue() as? [String: Any],
              let idleTimeNS = dict["HIDIdleTime"] as? Int64 else { return 0 }

        return Int(idleTimeNS / 1_000_000_000)
    }

    // MARK: - Helpers (nonisolated — usable from contextSnapshot and async contexts)

    nonisolated static func toChrome(_ date: Date) -> Int64 {
        // Chrome epoch = Jan 1, 1601 in microseconds
        Int64((date.timeIntervalSince1970 + 11_644_473_600.0) * 1_000_000)
    }

    nonisolated static func fromChrome(_ chromeTime: Int64) -> Date {
        Date(timeIntervalSince1970: Double(chromeTime) / 1_000_000.0 - 11_644_473_600.0)
    }

    nonisolated static func classifyIntent(_ transition: Int64) -> String {
        // Back/forward bit (0x01000000 = 16777216) takes precedence
        if transition & 16_777_216 != 0 { return "back_forward" }
        switch transition & 0xFF {
        case 1: return "typed"
        case 5: return "search"
        case 8: return "reload"
        case 0: return "link"
        default: return "other"
        }
    }

    nonisolated static func extractDomain(from urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let host = url.host else { return nil }
        // Strip www. prefix
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
