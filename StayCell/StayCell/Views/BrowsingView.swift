import SwiftUI
import GRDB

/// Browsing history dashboard — top domains by time with intentionality scores.
struct BrowsingView: View {
    let dbPool: DatabasePool?

    @State private var period: BrowsingPeriod = .week
    @State private var rows: [DomainRow] = []
    @State private var totalMinutes: Int = 0
    @State private var totalVisits: Int = 0
    @State private var intentBreakdown: [(intent: String, pct: Int)] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if rows.isEmpty {
                    emptyState
                } else {
                    domainList
                    Divider()
                    intentRow
                    totalsRow
                }
            }
            .padding(20)
        }
        .onAppear { loadData() }
        .onChange(of: period) { _, _ in loadData() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Browsing History")
                .font(.title2.weight(.semibold))
            Spacer()
            Picker("Period", selection: $period) {
                ForEach(BrowsingPeriod.allCases, id: \.self) { p in
                    Text(p.label).tag(p)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)
        }
    }

    // MARK: - Domain list

    private var domainList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows) { row in
                DomainRowView(row: row, maxMinutes: rows.first?.minutes ?? 1)
            }
        }
    }

    // MARK: - Intent breakdown row

    private var intentRow: some View {
        HStack(spacing: 6) {
            Text("Navigation:")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(intentBreakdown.prefix(4), id: \.intent) { item in
                Text("\(item.pct)% \(intentLabel(item.intent))")
                    .font(.caption)
                    .foregroundStyle(intentColor(item.intent))
            }
        }
    }

    // MARK: - Totals

    private var totalsRow: some View {
        HStack(spacing: 6) {
            Text("Total:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(formatMinutes(totalMinutes))
                .font(.caption)
            Text("browsing")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("·")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(totalVisits) visits")
                .font(.caption)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No browsing history yet.")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Imported once per day at launch from Brave, Chrome, Arc, or Edge.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Data loading

    private func loadData() {
        guard let dbPool else { return }
        do {
            try dbPool.read { db in
                let since = period.sinceDate
                let topRows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT domain,
                           SUM(durationSeconds) / 60 AS mins,
                           COUNT(*) AS visits,
                           SUM(CASE WHEN navIntent = 'typed' THEN 1 ELSE 0 END) * 100 / COUNT(*) AS typedPct
                    FROM browsing_visits
                    WHERE visitedAt >= ? AND durationSeconds > 0
                    GROUP BY domain ORDER BY mins DESC LIMIT 10
                    """,
                    arguments: [since]
                )
                rows = topRows.compactMap { row -> DomainRow? in
                    guard let domain = row["domain"] as String?,
                          let mins = row["mins"] as Int? else { return nil }
                    let visits = row["visits"] as Int? ?? 0
                    let typedPct = row["typedPct"] as Int? ?? 0
                    return DomainRow(domain: domain, minutes: mins, visits: visits, typedPct: typedPct)
                }

                totalMinutes = try Int.fetchOne(
                    db,
                    sql: "SELECT COALESCE(SUM(durationSeconds) / 60, 0) FROM browsing_visits WHERE visitedAt >= ?",
                    arguments: [since]
                ) ?? 0

                totalVisits = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM browsing_visits WHERE visitedAt >= ?",
                    arguments: [since]
                ) ?? 0

                let intentRows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT navIntent, COUNT(*) AS cnt
                    FROM browsing_visits WHERE visitedAt >= ?
                    GROUP BY navIntent ORDER BY cnt DESC
                    """,
                    arguments: [since]
                )
                let total = max(totalVisits, 1)
                intentBreakdown = intentRows.compactMap { row -> (intent: String, pct: Int)? in
                    guard let intent = row["navIntent"] as String?,
                          let cnt = row["cnt"] as Int? else { return nil }
                    return (intent: intent, pct: Int(Double(cnt) / Double(total) * 100))
                }
            }
        } catch {
            // Silently fail — data just won't show
        }
    }

    // MARK: - Helpers

    private func formatMinutes(_ mins: Int) -> String {
        let h = mins / 60
        let m = mins % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func intentLabel(_ intent: String) -> String {
        switch intent {
        case "typed": return "typed"
        case "link": return "link"
        case "reload": return "reload"
        case "back_forward": return "back/fwd"
        case "search": return "search"
        default: return intent
        }
    }

    private func intentColor(_ intent: String) -> Color {
        switch intent {
        case "typed": return .green
        case "link": return .orange
        case "reload": return .red
        case "back_forward": return .purple
        default: return .secondary
        }
    }
}

// MARK: - Domain row view

private struct DomainRowView: View {
    let row: DomainRow
    let maxMinutes: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(row.domain)
                .font(.caption.weight(.medium))
                .frame(width: 140, alignment: .leading)
                .lineLimit(1)

            GeometryReader { geo in
                let barWidth = maxMinutes > 0
                    ? CGFloat(row.minutes) / CGFloat(maxMinutes) * geo.size.width
                    : 0
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.blue.opacity(0.25))
                    .frame(width: max(barWidth, 2))
            }
            .frame(height: 14)

            Text(formatMinutes(row.minutes))
                .font(.caption)
                .foregroundStyle(.primary)
                .frame(width: 55, alignment: .trailing)

            Text("typed \(row.typedPct)%")
                .font(.caption2)
                .foregroundStyle(row.typedPct >= 50 ? .green : .secondary)
                .frame(width: 70, alignment: .trailing)
        }
        .frame(height: 20)
    }

    private func formatMinutes(_ mins: Int) -> String {
        let h = mins / 60
        let m = mins % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

// MARK: - Supporting types

private struct DomainRow: Identifiable {
    let id = UUID()
    let domain: String
    let minutes: Int
    let visits: Int
    let typedPct: Int
}

private enum BrowsingPeriod: String, CaseIterable {
    case today
    case week

    var label: String {
        switch self {
        case .today: "Today"
        case .week: "This week"
        }
    }

    var sinceDate: Date {
        switch self {
        case .today:
            return Calendar.current.startOfDay(for: Date())
        case .week:
            return Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        }
    }
}
