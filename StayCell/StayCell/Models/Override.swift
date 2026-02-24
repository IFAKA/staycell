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

    // MARK: - Phase 1: Behavioral context fields (migration v6)

    /// Minutes elapsed in the current timer session when the attempt fired.
    /// nil if no session was running.
    var minutesIntoSession: Int?

    /// Frontmost app at the time of the attempt (e.g. "Brave", "VSCode").
    var foregroundApp: String?

    /// Hour of day 0–23, derived from attemptedAt.
    var hourOfDay: Int = 0

    /// Day of week 1 (Sun) – 7 (Sat), derived from attemptedAt.
    var dayOfWeek: Int = 0

    /// Number of app activations in the 10 minutes before this attempt.
    /// High values indicate analysis paralysis / frantic switching.
    var appSwitchesLast10Min: Int?

    /// Seconds since the previous override attempt. nil if this is the first.
    var timeSinceLastOverrideSecs: Int?

    /// Inferred trigger category from measurable signals.
    /// Values: "fatigue" | "analysisParalysis" | "avoidance" | "noondayAcedia" |
    ///         "autopilot" | "cascade" | "lateNight" | "boredom"
    var triggerCategory: String?

    // MARK: - Phase 1b: Browser URL context (migration v8)

    /// Full URL in the frontmost browser tab at attempt time.
    /// nil if foreground app is not a supported browser or query fails.
    var foregroundURL: String?

    /// Extracted domain from foregroundURL (e.g. "reddit.com").
    /// Stored separately for fast SQL grouping without string parsing.
    var foregroundDomain: String?

    // MARK: - Phase 2: Pre-override browser context (migration v10)

    /// Last navigation intent in browser for this domain before the override ("typed"/"reload"/etc.).
    var preOverrideNavIntent: String?

    /// Reloads of current domain in last 30 minutes before override.
    var preOverrideReloadCount: Int?

    /// New tabs opened in last hour (tab proliferation signal).
    var preOverrideTabsOpened: Int?

    /// Seconds of system idle time immediately before the override attempt.
    var preOverrideIdleSeconds: Int?

    /// Fraction of FORWARD_BACK transitions in last 15 minutes (0.0–1.0).
    var preOverrideBackNavRatio: Double?

    static let databaseTableName = "overrides"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension Override {
    /// Create a new override attempt record (base fields only; context fields set at call site).
    static func attempt(mode: Mode, level: Int, phrase: String, intention: String?) -> Override {
        let now = Date()
        let cal = Calendar.current
        return Override(
            attemptedAt: now,
            mode: mode.rawValue,
            overrideLevel: level,
            granted: false,
            cancelled: false,
            phraseUsed: phrase,
            sessionIntention: intention,
            hourOfDay: cal.component(.hour, from: now),
            dayOfWeek: cal.component(.weekday, from: now)
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

    /// Fetch the most recent override before now (for cascade detection).
    static func lastOverride(db: Database) throws -> Override? {
        try Override
            .order(Column("attemptedAt").desc)
            .fetchOne(db)
    }
}

// MARK: - Trigger category inference

extension Override {
    /// Infer a trigger category from the context fields.
    /// Call this after all context fields are set.
    func inferredTriggerCategory(sessionIntention: String?) -> String? {
        // Refresh anxiety: compulsive checking (3+ reloads of same domain in 30 min)
        if let reloads = preOverrideReloadCount, reloads >= 3 {
            return "refreshAnxiety"
        }
        // Rabbit hole: deep link-chain pull (>40% back-nav on social domain)
        if let ratio = preOverrideBackNavRatio, ratio > 0.4 {
            return "rabbitHole"
        }
        // Zone-out: idle 90+ seconds while session was running
        if let idle = preOverrideIdleSeconds, idle >= 90,
           let mins = minutesIntoSession, mins > 0 {
            return "zoneOut"
        }
        // Analysis paralysis: frantic app switching
        if let switches = appSwitchesLast10Min, switches >= 5 {
            return "analysisParalysis"
        }
        // Cascade: another override within 30 min
        if let secs = timeSinceLastOverrideSecs, secs < 1800 {
            return "cascade"
        }
        if let mins = minutesIntoSession {
            // Fatigue: late in session
            if mins >= 45 {
                return "fatigue"
            }
            // Autopilot: habit firing before conscious thought
            if mins < 5 && overrideLevel == 1 {
                return "autopilot"
            }
            // Avoidance: bailing early on a known hard task
            if mins < 10 {
                let hardKeywords = ["debug", "fix", "bug", "auth", "test", "refactor", "review", "migrate", "deploy"]
                let intention = (sessionIntention ?? "").lowercased()
                if hardKeywords.contains(where: { intention.contains($0) }) {
                    return "avoidance"
                }
            }
            // Boredom: long shallow session
            if mode == Mode.shallowWork.rawValue && mins > 30 {
                return "boredom"
            }
        }
        // Late-night
        if hourOfDay >= 22 {
            return "lateNight"
        }
        // Noonday acedia
        if hourOfDay >= 12 && hourOfDay <= 14 {
            return "noondayAcedia"
        }
        return nil
    }
}
