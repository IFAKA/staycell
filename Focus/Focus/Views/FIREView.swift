import SwiftUI
import Charts
import GRDB

/// FIRE tracking dashboard tab.
struct FIREView: View {
    let dbPool: DatabasePool?

    @State private var snapshots: [FIRESnapshot] = []
    @State private var showEntrySheet = false

    // Entry form state
    @State private var income = ""
    @State private var expenses = ""
    @State private var invested = ""
    @State private var netWorth = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("FIRE Tracker")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button("Add Monthly Data") {
                        showEntrySheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                if let latest = snapshots.last {
                    metricsGrid(latest)
                    Divider()
                }

                if snapshots.count >= 2 {
                    savingsRateChart
                    Divider()
                    netWorthChart
                }

                snapshotsList
            }
            .padding(20)
        }
        .onAppear { loadSnapshots() }
        .sheet(isPresented: $showEntrySheet) {
            entryForm
        }
    }

    // MARK: - Metrics

    private func metricsGrid(_ latest: FIRESnapshot) -> some View {
        let fireNum = FIRECalculator.fireNumber(monthlyExpenses: latest.monthlyExpenses)
        let monthsToFire = FIRECalculator.monthsToFIRE(
            currentInvested: latest.totalInvested,
            monthlySavings: latest.monthlySavings,
            monthlyExpenses: latest.monthlyExpenses
        )
        let yearsCovered = FIRECalculator.yearsOfExpensesCovered(
            totalInvested: latest.totalInvested,
            monthlyExpenses: latest.monthlyExpenses
        )

        return VStack(spacing: 12) {
            HStack(spacing: 16) {
                metricCard(
                    title: "Savings Rate",
                    value: String(format: "%.0f%%", latest.savingsRate * 100)
                )
                metricCard(
                    title: "FIRE Number",
                    value: formatCurrency(fireNum)
                )
                metricCard(
                    title: "Months to FIRE",
                    value: monthsToFire.map { "\($0)" } ?? "N/A"
                )
                metricCard(
                    title: "Years Covered",
                    value: String(format: "%.1f", yearsCovered)
                )
            }

            HStack(spacing: 16) {
                metricCard(
                    title: "Net Worth",
                    value: formatCurrency(latest.totalNetWorth)
                )
                metricCard(
                    title: "Invested",
                    value: formatCurrency(latest.totalInvested)
                )
                metricCard(
                    title: "Monthly Savings",
                    value: formatCurrency(latest.monthlySavings)
                )
                if let date = FIRECalculator.projectedFIREDate(
                    currentInvested: latest.totalInvested,
                    monthlySavings: latest.monthlySavings,
                    monthlyExpenses: latest.monthlyExpenses
                ) {
                    let f = DateFormatter()
                    let _ = f.dateFormat = "MMM yyyy"
                    metricCard(
                        title: "Projected FIRE",
                        value: f.string(from: date)
                    )
                }
            }
        }
    }

    private func metricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Charts

    private var savingsRateChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Savings Rate")
                .font(.headline)

            Chart(snapshots) { snapshot in
                LineMark(
                    x: .value("Month", snapshot.date),
                    y: .value("Rate", snapshot.savingsRate * 100)
                )
                .foregroundStyle(.green)

                PointMark(
                    x: .value("Month", snapshot.date),
                    y: .value("Rate", snapshot.savingsRate * 100)
                )
                .foregroundStyle(.green)
            }
            .chartYAxisLabel("%")
            .frame(height: 150)
        }
    }

    private var netWorthChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Net Worth")
                .font(.headline)

            Chart(snapshots) { snapshot in
                BarMark(
                    x: .value("Month", snapshot.date),
                    y: .value("Net Worth", snapshot.totalNetWorth)
                )
                .foregroundStyle(.blue.opacity(0.7))
            }
            .frame(height: 150)
        }
    }

    // MARK: - List

    private var snapshotsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Monthly Data")
                .font(.headline)

            ForEach(snapshots.reversed()) { snapshot in
                HStack {
                    Text(snapshot.date)
                        .font(.caption.weight(.medium))
                    Spacer()
                    Text(formatCurrency(snapshot.monthlyIncome))
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text(formatCurrency(snapshot.monthlyExpenses))
                        .font(.caption)
                        .foregroundStyle(.red)
                    Text(String(format: "%.0f%%", snapshot.savingsRate * 100))
                        .font(.caption.weight(.medium))
                }
            }
        }
    }

    // MARK: - Entry Form

    private var entryForm: some View {
        VStack(spacing: 16) {
            Text("Monthly Financial Data")
                .font(.headline)

            let currentMonth: String = {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM"
                return f.string(from: Date())
            }()

            Text(currentMonth)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Group {
                TextField("Monthly Income", text: $income)
                TextField("Monthly Expenses", text: $expenses)
                TextField("Total Invested", text: $invested)
                TextField("Total Net Worth", text: $netWorth)
            }
            .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    showEntrySheet = false
                }
                Spacer()
                Button("Save") {
                    saveSnapshot()
                    showEntrySheet = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 300)
    }

    // MARK: - Helpers

    private func loadSnapshots() {
        guard let dbPool else { return }
        do {
            snapshots = try dbPool.read { db in
                try FIRESnapshot
                    .order(Column("date").asc)
                    .fetchAll(db)
            }
        } catch {
            // Silently fail
        }
    }

    private func saveSnapshot() {
        guard let dbPool,
              let inc = Double(income),
              let exp = Double(expenses),
              let inv = Double(invested),
              let nw = Double(netWorth)
        else { return }

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"

        var snapshot = FIRESnapshot(
            date: f.string(from: Date()),
            monthlyIncome: inc,
            monthlyExpenses: exp,
            totalInvested: inv,
            totalNetWorth: nw
        )

        do {
            try dbPool.write { db in
                try snapshot.save(db)
            }
            loadSnapshots()
        } catch {
            // Silently fail
        }

        income = ""
        expenses = ""
        invested = ""
        netWorth = ""
    }

    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }
}
