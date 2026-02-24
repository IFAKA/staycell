import SwiftUI
import Charts
import GRDB

/// Weekly stats summary view — shows patterns and insights.
struct WeeklyStatsView: View {
    let dbPool: DatabasePool?

    @State private var weeklyStats: [DailyStats] = []
    @State private var totalDeepWork: Int = 0
    @State private var totalSessions: Int = 0
    @State private var totalOverrides: Int = 0
    @State private var avgDeepWorkPerDay: Int = 0
    @State private var completionRate: Double = 0
    @State private var overridesByDay: [(day: String, count: Int)] = []
    @State private var insights: BehaviorInsights?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Weekly Summary")
                    .font(.title2.weight(.semibold))

                if !weeklyStats.isEmpty {
                    summaryCards
                    Divider()
                    deepWorkChart
                    Divider()
                    overrideChart
                    Divider()
                    dailyBreakdown
                    if let insights, !insights.sentences.isEmpty {
                        Divider()
                        insightsSection(insights)
                    }
                } else {
                    Text("No data yet. Complete some sessions to see your weekly summary.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .onAppear { loadWeeklyData() }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        HStack(spacing: 16) {
            summaryCard(
                title: "Deep Work",
                value: "\(totalDeepWork / 60)h \(totalDeepWork % 60)m",
                subtitle: "avg \(avgDeepWorkPerDay)m/day"
            )
            summaryCard(
                title: "Sessions",
                value: "\(totalSessions)",
                subtitle: "\(Int(completionRate))% completion"
            )
            summaryCard(
                title: "Overrides",
                value: "\(totalOverrides)",
                subtitle: totalOverrides == 0 ? "Clean week" : "\(totalOverrides) granted"
            )
        }
    }

    private func summaryCard(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Charts

    private var deepWorkChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Deep Work by Day")
                .font(.headline)

            Chart(weeklyStats, id: \.date) { stat in
                BarMark(
                    x: .value("Day", shortDay(stat.date)),
                    y: .value("Minutes", stat.deepWorkMinutes)
                )
                .foregroundStyle(.red.opacity(0.8))

                BarMark(
                    x: .value("Day", shortDay(stat.date)),
                    y: .value("Minutes", stat.shallowWorkMinutes)
                )
                .foregroundStyle(.orange.opacity(0.6))
            }
            .chartYAxisLabel("Minutes")
            .frame(height: 180)

            HStack(spacing: 16) {
                Label("Deep Work", systemImage: "circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                Label("Shallow Work", systemImage: "circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var overrideChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Override Attempts")
                .font(.headline)

            if overridesByDay.allSatisfy({ $0.count == 0 }) {
                Text("No overrides this week.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Chart(overridesByDay, id: \.day) { item in
                    BarMark(
                        x: .value("Day", item.day),
                        y: .value("Count", item.count)
                    )
                    .foregroundStyle(.orange.opacity(0.7))
                }
                .frame(height: 120)
            }
        }
    }

    // MARK: - Breakdown

    private var dailyBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily Breakdown")
                .font(.headline)

            ForEach(weeklyStats, id: \.date) { stat in
                HStack {
                    Text(shortDay(stat.date))
                        .font(.caption.weight(.medium))
                        .frame(width: 40, alignment: .leading)
                    Text("\(stat.deepWorkMinutes)m deep")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Text("\(stat.shallowWorkMinutes)m shallow")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Spacer()
                    Text("\(stat.sessionsCompleted) done")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text("\(stat.sessionsAbandoned) quit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(stat.overridesGranted) overrides")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Insights Section

    @ViewBuilder
    private func insightsSection(_ insights: BehaviorInsights) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Behavioral Patterns")
                .font(.headline)
            Text("Based on \(insights.totalOverrides) override attempts")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(insights.sentences, id: \.self) { sentence in
                HStack(alignment: .top, spacing: 8) {
                    Text("·")
                        .foregroundStyle(.orange)
                        .font(.body.weight(.bold))
                    Text(sentence)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadWeeklyData() {
        guard let dbPool else { return }
        do {
            let calendar = Calendar.current
            weeklyStats = try dbPool.read { db in
                var stats: [DailyStats] = []
                for dayOffset in (0..<7).reversed() {
                    let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date())!
                    let stat = try DailyStats.compute(for: date, in: db)
                    stats.append(stat)
                }
                return stats
            }

            totalDeepWork = weeklyStats.reduce(0) { $0 + $1.deepWorkMinutes }
            totalSessions = weeklyStats.reduce(0) { $0 + $1.sessionsCompleted + $1.sessionsAbandoned }
            totalOverrides = weeklyStats.reduce(0) { $0 + $1.overridesGranted }
            let activeDays = weeklyStats.filter { $0.deepWorkMinutes > 0 }.count
            avgDeepWorkPerDay = activeDays > 0 ? totalDeepWork / activeDays : 0

            let completed = weeklyStats.reduce(0) { $0 + $1.sessionsCompleted }
            completionRate = totalSessions > 0 ? Double(completed) / Double(totalSessions) * 100 : 0

            overridesByDay = weeklyStats.map { (shortDay($0.date), $0.overridesGranted) }

            insights = try dbPool.read { db in
                try BehaviorAnalyzer.loadInsights(db: db)
            }
        } catch {
            // Silently fail
        }
    }

    private func shortDay(_ isoDate: String) -> String {
        // "2026-02-24" → "Mon"
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: isoDate) else { return String(isoDate.suffix(5)) }
        f.dateFormat = "EEE"
        return f.string(from: date)
    }
}
