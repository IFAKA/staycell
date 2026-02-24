import Foundation
import GRDB

/// Monthly financial snapshot for FIRE tracking.
struct FIRESnapshot: Codable, Sendable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var date: String              // "2026-02"
    var monthlyIncome: Double
    var monthlyExpenses: Double
    var totalInvested: Double
    var totalNetWorth: Double

    static let databaseTableName = "fire_snapshots"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var savingsRate: Double {
        guard monthlyIncome > 0 else { return 0 }
        return (monthlyIncome - monthlyExpenses) / monthlyIncome
    }

    var monthlySavings: Double {
        monthlyIncome - monthlyExpenses
    }
}
