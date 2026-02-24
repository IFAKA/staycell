import Foundation
import GRDB

/// Data package passed to ReflectionView after context is loaded.
struct ReflectionContext: Sendable {
    let systemPrompt: String
    let hasEnoughData: Bool
    let dataAge: Date?
    let overrideCount: Int
}

/// Builds the LLM system prompt from behavioral data.
/// All methods are nonisolated — must be called inside a GRDB read closure.
enum ReflectionContextBuilder {
    nonisolated static func build(db: Database, currentModeName: String) throws -> ReflectionContext {
        let insights = try BehaviorAnalyzer.loadInsights(db: db)

        guard insights.totalOverrides >= 7 else {
            return ReflectionContext(
                systemPrompt: "",
                hasEnoughData: false,
                dataAge: nil,
                overrideCount: insights.totalOverrides
            )
        }

        // Session stats: last 7 days
        let sessionRows = try Row.fetchAll(db, sql: """
            SELECT
                COUNT(*) AS total,
                SUM(CASE WHEN completed = 1 THEN 1 ELSE 0 END) AS completed,
                AVG(CASE WHEN actualDurationSeconds IS NOT NULL
                         THEN actualDurationSeconds / 60.0 ELSE NULL END) AS avgMins
            FROM sessions
            WHERE startedAt >= date('now', '-7 days')
        """)
        let sessionTotal = (sessionRows.first?["total"] as Int?) ?? 0
        let sessionCompleted = (sessionRows.first?["completed"] as Int?) ?? 0
        let sessionAvgMins = (sessionRows.first?["avgMins"] as Double?) ?? 0
        let completionRate = sessionTotal > 0
            ? Int(Double(sessionCompleted) / Double(sessionTotal) * 100)
            : 0

        // Last 5 overrides for recent context
        let recentOverrides = try Row.fetchAll(db, sql: """
            SELECT attemptedAt, foregroundApp, foregroundDomain, triggerCategory, granted
            FROM overrides
            ORDER BY attemptedAt DESC
            LIMIT 5
        """)
        let overridesText = recentOverrides.map { row -> String in
            let app = (row["foregroundApp"] as String?) ?? "unknown"
            let domain = (row["foregroundDomain"] as String?) ?? ""
            let cat = (row["triggerCategory"] as String?) ?? "unclassified"
            let granted = (row["granted"] as Bool?) ?? false
            let domainPart = domain.isEmpty ? "" : " (\(domain))"
            return "- \(granted ? "granted" : "cancelled") via \(app)\(domainPart), trigger: \(cat)"
        }.joined(separator: "\n")

        // Build system prompt
        var prompt = """
        You are a focused work coach for this user. You have access to their real behavioral \
        data from the StayCell app. Be direct, reference specific numbers and patterns you see, \
        and ask one probing question at the end. Do not moralize or lecture. Keep responses concise.

        ## Current State
        Mode: \(currentModeName)

        ## Override Patterns (\(insights.totalOverrides) total attempts)
        """

        if let peak = insights.peakGrantedHours.first {
            let h = peak.hour % 12 == 0 ? 12 : peak.hour % 12
            let period = peak.hour < 12 ? "AM" : "PM"
            prompt += "\nPeak override hour: \(h) \(period) (\(peak.count) times)"
        }
        if let topApp = insights.topTriggerApps.first {
            prompt += "\nTop trigger app: \(topApp.app) (\(topApp.count) times)"
        }
        if let topDomain = insights.topTriggerDomains.first {
            prompt += "\nTop trigger domain: \(topDomain.domain) (\(topDomain.count) times)"
        }
        if let late = insights.fatigueBuckets.first(where: { $0.bucket == "late (45+)" }) {
            let pct = Int(Double(late.count) / Double(insights.totalOverrides) * 100)
            prompt += "\nLate-session fatigue: \(pct)% of overrides at 45+ min mark"
        }
        if insights.cascadeCount > 0 {
            prompt += "\nCascade events: \(insights.cascadeCount) overrides within 30 min of prior"
        }
        if let topCat = insights.triggerCategories.first {
            prompt += "\nDominant trigger: \(topCat.category) (\(topCat.count) times)"
        }

        prompt += """


        ## Session Stats (last 7 days)
        Sessions: \(sessionTotal) total, \(completionRate)% completion rate
        Avg session: \(Int(sessionAvgMins)) min
        """

        if insights.totalBrowsingMinutes > 0 {
            let h = insights.totalBrowsingMinutes / 60
            let m = insights.totalBrowsingMinutes % 60
            prompt += "\n\n## Browsing (last 7 days)\nTotal: \(h)h \(m)m"
            if let top = insights.topDomainsByTime.first {
                prompt += "\nTop site: \(top.domain) (\(top.minutes) min)"
            }
            let topNames = insights.topDomainsByTime.prefix(3).map(\.domain).joined(separator: " · ")
            if !topNames.isEmpty { prompt += "\nTop sites: \(topNames)" }
        }

        if !overridesText.isEmpty {
            prompt += "\n\n## Recent 5 Overrides\n\(overridesText)"
        }

        return ReflectionContext(
            systemPrompt: prompt,
            hasEnoughData: true,
            dataAge: Date(),
            overrideCount: insights.totalOverrides
        )
    }
}
