import Foundation
import GRDB
import os.log

// MARK: - Output types

/// Pattern insights derived from accumulated override data.
struct BehaviorInsights: Sendable {
    /// Top hours of day for granted overrides (hour 0–23).
    var peakGrantedHours: [(hour: Int, count: Int)]
    /// Apps most present at override attempt time.
    var topTriggerApps: [(app: String, count: Int)]
    /// Domains most present at override attempt time (browser only).
    var topTriggerDomains: [(domain: String, count: Int)]
    /// Override attempts bucketed by session depth.
    var fatigueBuckets: [(bucket: String, count: Int)]
    /// Count of overrides within 30 min of a previous one (cascade).
    var cascadeCount: Int
    /// Distribution of inferred trigger categories.
    var triggerCategories: [(category: String, count: Int)]
    /// Total override attempts across all time (used for gating the section).
    var totalOverrides: Int
    /// Overrides where a browser domain was captured (for rate calculations).
    var overridesWithDomain: Int

    // MARK: - Browsing data (from browsing_visits, populated once daily)

    /// Top domains by total time this week (domain, minutes).
    var topDomainsByTime: [(domain: String, minutes: Int)]
    /// Total browsing minutes this week.
    var totalBrowsingMinutes: Int
    /// Navigation intent breakdown this week (intent, percentage).
    var navIntentBreakdown: [(intent: String, pct: Int)]

    /// Human-readable insight sentences. Non-empty only when data is meaningful.
    var sentences: [String] {
        guard totalOverrides >= 7 else { return [] }
        var result: [String] = []

        // Peak hour insight
        if let top = peakGrantedHours.first {
            let formatted = hourLabel(top.hour)
            if peakGrantedHours.count > 1 {
                let second = hourLabel(peakGrantedHours[1].hour)
                result.append("Most override attempts happen around \(formatted) and \(second).")
            } else {
                result.append("Most override attempts happen around \(formatted).")
            }
        }

        // Domain insight (richer than app name when browser is dominant)
        if let topDomain = topTriggerDomains.first, overridesWithDomain > 0 {
            let pct = Int(Double(topDomain.count) / Double(totalOverrides) * 100)
            if pct >= 20 {
                result.append("\(topDomain.domain) is present in \(pct)% of your override attempts.")
            } else {
                result.append("Most common site at override time: \(topDomain.domain).")
            }
            // Show second domain if meaningful
            if topTriggerDomains.count > 1 {
                let second = topTriggerDomains[1]
                result.append("Other frequent site: \(second.domain) (\(second.count) times).")
            }
        } else if let topApp = topTriggerApps.first {
            // Fall back to app name when no domain data yet
            result.append("You most often attempt overrides while \(topApp.app) is in the foreground.")
        }

        // Fatigue insight
        let lateCount = fatigueBuckets.first(where: { $0.bucket == "late (45+)" })?.count ?? 0
        if lateCount > 0 {
            let pct = Int(Double(lateCount) / Double(totalOverrides) * 100)
            if pct >= 30 {
                result.append("\(pct)% of your overrides happen 45+ minutes into a session — a fatigue pattern.")
            }
        }

        // Cascade insight
        if cascadeCount > 0 {
            result.append("\(cascadeCount) override\(cascadeCount == 1 ? "" : "s") happened within 30 minutes of a previous one — cascade pressure.")
        }

        // Dominant trigger category
        if let top = triggerCategories.first {
            result.append("Most common trigger: \(triggerCategoryLabel(top.category)) (\(top.count) times).")
        }

        // Browsing time insights (only if we have data)
        if totalBrowsingMinutes > 30 {
            let h = totalBrowsingMinutes / 60
            let m = totalBrowsingMinutes % 60
            let timeStr = h > 0 ? "\(h)h \(m)m" : "\(m)m"

            if let topSite = topDomainsByTime.first {
                let siteMins = topSite.minutes
                let siteStr = siteMins >= 60
                    ? "\(siteMins / 60)h \(siteMins % 60)m"
                    : "\(siteMins)m"
                let pctOfBrowsing = totalBrowsingMinutes > 0
                    ? Int(Double(topSite.minutes) / Double(totalBrowsingMinutes) * 100)
                    : 0
                result.append("You spent \(siteStr) on \(topSite.domain) this week (\(pctOfBrowsing)% of browsing time).")
            }

            if topDomainsByTime.count > 1 {
                let topNames = topDomainsByTime.prefix(3).map(\.domain).joined(separator: " · ")
                result.append("Top sites: \(topNames)")
            }

            // Intent breakdown: highlight if link-following dominates
            if let linkIntent = navIntentBreakdown.first(where: { $0.intent == "link" }),
               let typedIntent = navIntentBreakdown.first(where: { $0.intent == "typed" }),
               linkIntent.pct >= 50 {
                result.append("\(linkIntent.pct)% of your browsing this week was link-following — vs \(typedIntent.pct)% intentional typed access.")
            }

            // Cross-signal: domain in both override list and top browsed
            if let topOverrideDomain = topTriggerDomains.first,
               let browsedMatch = topDomainsByTime.first(where: { $0.domain == topOverrideDomain.domain }) {
                let overridePct = Int(Double(topOverrideDomain.count) / Double(max(totalOverrides, 1)) * 100)
                let siteStr = browsedMatch.minutes >= 60
                    ? "\(browsedMatch.minutes / 60)h \(browsedMatch.minutes % 60)m"
                    : "\(browsedMatch.minutes)m"
                result.append("\(topOverrideDomain.domain) is both your most visited site (\(siteStr)) and present in \(overridePct)% of override attempts.")
            }

            _ = timeStr // suppress unused warning if all branches above fire
        }

        return result
    }

    private func hourLabel(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        let period = hour < 12 ? "AM" : "PM"
        return "\(h) \(period)"
    }

    private func triggerCategoryLabel(_ key: String) -> String {
        switch key {
        case "fatigue":           return "fatigue (late session)"
        case "analysisParalysis": return "analysis paralysis (frantic switching)"
        case "avoidance":         return "avoidance (early bail on hard task)"
        case "noondayAcedia":     return "noonday slump (12–2 PM)"
        case "autopilot":         return "autopilot (habit before intent)"
        case "cascade":           return "cascade (multiple in 30 min)"
        case "lateNight":         return "late-night (10 PM+)"
        case "boredom":           return "boredom (long shallow session)"
        case "refreshAnxiety":    return "refresh anxiety (compulsive checking)"
        case "rabbitHole":        return "rabbit hole (deep link-chain pull)"
        case "zoneOut":           return "zone-out (idle before override)"
        default:                  return key
        }
    }
}

// MARK: - Analyzer

/// Runs read-only SQL queries against accumulated override data.
/// No ML — pure GROUP BY pattern detection.
enum BehaviorAnalyzer {
    private static let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "behaviorAnalyzer")

    /// Load insights from the database.
    static func loadInsights(db: Database) throws -> BehaviorInsights {
        let totalOverrides = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM overrides"
        ) ?? 0

        // Peak granted hours (top 3)
        let hourRows = try Row.fetchAll(
            db,
            sql: """
            SELECT hourOfDay, COUNT(*) AS cnt
            FROM overrides
            WHERE granted = 1
            GROUP BY hourOfDay
            ORDER BY cnt DESC
            LIMIT 3
            """
        )
        let peakHours: [(hour: Int, count: Int)] = hourRows.map {
            (hour: $0["hourOfDay"] as Int, count: $0["cnt"] as Int)
        }

        // Top trigger apps (top 5)
        let appRows = try Row.fetchAll(
            db,
            sql: """
            SELECT foregroundApp, COUNT(*) AS cnt
            FROM overrides
            WHERE foregroundApp IS NOT NULL
            GROUP BY foregroundApp
            ORDER BY cnt DESC
            LIMIT 5
            """
        )
        let topApps: [(app: String, count: Int)] = appRows.compactMap {
            guard let app = $0["foregroundApp"] as String? else { return nil }
            return (app: app, count: $0["cnt"] as Int)
        }

        // Top trigger domains (top 5) — browser-only signal
        let domainRows = try Row.fetchAll(
            db,
            sql: """
            SELECT foregroundDomain, COUNT(*) AS cnt
            FROM overrides
            WHERE foregroundDomain IS NOT NULL
            GROUP BY foregroundDomain
            ORDER BY cnt DESC
            LIMIT 5
            """
        )
        let topDomains: [(domain: String, count: Int)] = domainRows.compactMap {
            guard let domain = $0["foregroundDomain"] as String? else { return nil }
            return (domain: domain, count: $0["cnt"] as Int)
        }

        let overridesWithDomain = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM overrides WHERE foregroundDomain IS NOT NULL"
        ) ?? 0

        // Fatigue buckets by session depth
        let bucketRows = try Row.fetchAll(
            db,
            sql: """
            SELECT
              CASE
                WHEN minutesIntoSession IS NULL THEN 'no session'
                WHEN minutesIntoSession < 15 THEN 'early (0-15)'
                WHEN minutesIntoSession < 45 THEN 'mid (15-45)'
                ELSE 'late (45+)'
              END AS bucket,
              COUNT(*) AS cnt
            FROM overrides
            GROUP BY bucket
            ORDER BY cnt DESC
            """
        )
        let fatigueBuckets: [(bucket: String, count: Int)] = bucketRows.map {
            (bucket: $0["bucket"] as String, count: $0["cnt"] as Int)
        }

        // Cascade count: overrides within 30 min of previous
        let cascadeCount = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM overrides WHERE timeSinceLastOverrideSecs IS NOT NULL AND timeSinceLastOverrideSecs < 1800"
        ) ?? 0

        // Trigger category distribution
        let categoryRows = try Row.fetchAll(
            db,
            sql: """
            SELECT triggerCategory, COUNT(*) AS cnt
            FROM overrides
            WHERE triggerCategory IS NOT NULL
            GROUP BY triggerCategory
            ORDER BY cnt DESC
            """
        )
        let triggerCategories: [(category: String, count: Int)] = categoryRows.compactMap {
            guard let cat = $0["triggerCategory"] as String? else { return nil }
            return (category: cat, count: $0["cnt"] as Int)
        }

        // Top domains by time this week
        let domainTimeRows = try Row.fetchAll(
            db,
            sql: """
            SELECT domain, SUM(durationSeconds) / 60 AS mins
            FROM browsing_visits
            WHERE visitedAt >= date('now', '-7 days') AND durationSeconds > 0
            GROUP BY domain ORDER BY mins DESC LIMIT 5
            """
        )
        let topDomainsByTime: [(domain: String, minutes: Int)] = domainTimeRows.compactMap {
            guard let domain = $0["domain"] as String?, let mins = $0["mins"] as Int? else { return nil }
            return (domain: domain, minutes: mins)
        }

        // Total browsing minutes this week
        let totalBrowsingMinutes = try Int.fetchOne(
            db,
            sql: "SELECT COALESCE(SUM(durationSeconds) / 60, 0) FROM browsing_visits WHERE visitedAt >= date('now', '-7 days')"
        ) ?? 0

        // Navigation intent breakdown this week
        let totalVisitsThisWeek = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM browsing_visits WHERE visitedAt >= date('now', '-7 days')"
        ) ?? 0
        let intentRows = try Row.fetchAll(
            db,
            sql: """
            SELECT navIntent, COUNT(*) AS cnt
            FROM browsing_visits WHERE visitedAt >= date('now', '-7 days')
            GROUP BY navIntent ORDER BY cnt DESC
            """
        )
        let navIntentBreakdown: [(intent: String, pct: Int)] = intentRows.compactMap {
            guard let intent = $0["navIntent"] as String?, let cnt = $0["cnt"] as Int? else { return nil }
            let pct = totalVisitsThisWeek > 0 ? Int(Double(cnt) / Double(totalVisitsThisWeek) * 100) : 0
            return (intent: intent, pct: pct)
        }

        return BehaviorInsights(
            peakGrantedHours: peakHours,
            topTriggerApps: topApps,
            topTriggerDomains: topDomains,
            fatigueBuckets: fatigueBuckets,
            cascadeCount: cascadeCount,
            triggerCategories: triggerCategories,
            totalOverrides: totalOverrides,
            overridesWithDomain: overridesWithDomain,
            topDomainsByTime: topDomainsByTime,
            totalBrowsingMinutes: totalBrowsingMinutes,
            navIntentBreakdown: navIntentBreakdown
        )
    }
}
