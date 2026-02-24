import SwiftUI
import Charts
import GRDB

/// Main dashboard window with sidebar navigation.
struct DashboardView: View {
    let appState: AppState
    let modeEngine: ModeEngine
    let scheduleEngine: ScheduleEngine
    let dbPool: DatabasePool?

    @State private var selectedTab: DashboardTab = .today

    var body: some View {
        NavigationSplitView {
            List(DashboardTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.title, systemImage: tab.icon)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 140, ideal: 160, max: 200)
        } detail: {
            switch selectedTab {
            case .today:
                TodayView(appState: appState, modeEngine: modeEngine, scheduleEngine: scheduleEngine, dbPool: dbPool)
            case .history:
                HistoryView(dbPool: dbPool)
            case .weekly:
                WeeklyStatsView(dbPool: dbPool)
            case .fire:
                FIREView(dbPool: dbPool)
            case .settings:
                SettingsView(appState: appState, dbPool: dbPool)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

enum DashboardTab: String, CaseIterable {
    case today
    case history
    case weekly
    case fire
    case settings

    var title: String {
        switch self {
        case .today: "Today"
        case .history: "History"
        case .weekly: "Weekly"
        case .fire: "FIRE"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .today: "sun.max"
        case .history: "chart.bar"
        case .weekly: "calendar"
        case .fire: "flame"
        case .settings: "gear"
        }
    }
}

// MARK: - Today View

struct TodayView: View {
    let appState: AppState
    let modeEngine: ModeEngine
    let scheduleEngine: ScheduleEngine
    let dbPool: DatabasePool?

    @State private var todaySessions: [Session] = []
    @State private var todayOverrides: [Override] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Current status
                currentStatusSection

                Divider()

                // Schedule
                scheduleSection

                Divider()

                // Today's sessions
                sessionsSection

                // Overrides
                if !todayOverrides.isEmpty {
                    Divider()
                    overridesSection
                }
            }
            .padding(20)
        }
        .onAppear { loadTodayData() }
    }

    private var currentStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(colorForMode(appState.currentMode))
                    .frame(width: 12, height: 12)
                Text(appState.currentMode.displayName)
                    .font(.title2.weight(.semibold))

                Spacer()

                if appState.timerIsRunning {
                    Text(formatTime(appState.timerRemainingSeconds))
                        .font(.system(.title, design: .monospaced).weight(.medium))
                }
            }

            if let intention = appState.currentSessionIntention, !intention.isEmpty {
                Text(intention)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Label("\(appState.sessionsCompletedToday) sessions", systemImage: "flame")
                Label("\(totalFocusMinutesToday) min focused", systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Schedule")
                .font(.headline)

            if scheduleEngine.blocks.isEmpty {
                Text("No schedule generated yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(scheduleEngine.blocks) { block in
                    HStack {
                        Circle()
                            .fill(colorForMode(block.mode))
                            .frame(width: 6, height: 6)
                        Text(block.label)
                            .font(.caption)
                        Spacer()
                        Text("\(formatHourMinute(block.startTime)) - \(formatHourMinute(block.endTime))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .opacity(block.endTime < Date() ? 0.5 : 1.0)
                }
            }
        }
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sessions")
                .font(.headline)

            if todaySessions.isEmpty {
                Text("No sessions yet today.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(todaySessions, id: \.id) { session in
                    HStack {
                        Image(systemName: session.completed ? "checkmark.circle.fill" : (session.abandoned ? "xmark.circle" : "circle"))
                            .foregroundStyle(session.completed ? .green : (session.abandoned ? .red : .secondary))
                            .font(.caption)
                        Text(session.mode.capitalized)
                            .font(.caption.weight(.medium))
                        if let intention = session.intention {
                            Text("— \(intention)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if let duration = session.actualDurationSeconds {
                            Text("\(duration / 60) min")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var overridesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overrides")
                .font(.headline)

            ForEach(todayOverrides, id: \.id) { override_ in
                HStack {
                    Image(systemName: override_.granted ? "lock.open" : "lock")
                        .foregroundStyle(override_.granted ? .orange : .secondary)
                        .font(.caption)
                    Text("Level \(override_.overrideLevel)")
                        .font(.caption.weight(.medium))
                    Text(override_.granted ? "Granted" : "Cancelled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatHourMinute(override_.attemptedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private var totalFocusMinutesToday: Int {
        todaySessions
            .filter(\.completed)
            .compactMap(\.actualDurationSeconds)
            .reduce(0, +) / 60
    }

    private func loadTodayData() {
        guard let dbPool else { return }
        do {
            let startOfDay = Calendar.current.startOfDay(for: Date())
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!

            todaySessions = try dbPool.read { db in
                try Session
                    .filter(Column("startedAt") >= startOfDay && Column("startedAt") < endOfDay)
                    .order(Column("startedAt").desc)
                    .fetchAll(db)
            }

            todayOverrides = try dbPool.read { db in
                try Override
                    .filter(Column("attemptedAt") >= startOfDay && Column("attemptedAt") < endOfDay)
                    .order(Column("attemptedAt").desc)
                    .fetchAll(db)
            }
        } catch {
            // Silently fail — data just won't show
        }
    }

    private func colorForMode(_ mode: Mode) -> Color {
        switch mode {
        case .deepWork: .red
        case .shallowWork: .orange
        case .personalTime: .green
        case .offline: .purple
        }
    }

    private func formatTime(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formatHourMinute(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

// MARK: - History View

struct HistoryView: View {
    let dbPool: DatabasePool?

    @State private var weeklyStats: [DailyStats] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("History")
                    .font(.title2.weight(.semibold))

                if !weeklyStats.isEmpty {
                    focusTimeChart
                    Divider()
                    statsTable
                } else {
                    Text("No data yet. Complete some sessions to see your history.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .onAppear { loadWeeklyStats() }
    }

    private var focusTimeChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily Focus Time")
                .font(.headline)

            Chart(weeklyStats, id: \.date) { stat in
                BarMark(
                    x: .value("Date", shortDate(stat.date)),
                    y: .value("Deep Work", stat.deepWorkMinutes)
                )
                .foregroundStyle(.red.opacity(0.8))

                BarMark(
                    x: .value("Date", shortDate(stat.date)),
                    y: .value("Shallow Work", stat.shallowWorkMinutes)
                )
                .foregroundStyle(.orange.opacity(0.8))
            }
            .chartYAxisLabel("Minutes")
            .frame(height: 200)
        }
    }

    private var statsTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily Breakdown")
                .font(.headline)

            ForEach(weeklyStats, id: \.date) { stat in
                HStack {
                    Text(stat.date)
                        .font(.caption.weight(.medium))
                    Spacer()
                    Text("\(stat.deepWorkMinutes)m deep")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Text("\(stat.sessionsCompleted) done")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text("\(stat.overridesGranted) overrides")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func loadWeeklyStats() {
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
        } catch {
            // Silently fail
        }
    }

    private func shortDate(_ isoDate: String) -> String {
        String(isoDate.suffix(5)) // "02-24"
    }
}
