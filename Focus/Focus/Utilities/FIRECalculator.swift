import Foundation

/// Pure functions for FIRE (Financial Independence, Retire Early) calculations.
enum FIRECalculator {
    /// FIRE number: the investment amount needed to sustain expenses indefinitely.
    /// Uses the 4% rule (25x annual expenses).
    static func fireNumber(monthlyExpenses: Double) -> Double {
        monthlyExpenses * 12 * 25
    }

    /// Months to FIRE from current state.
    /// Assumes constant savings rate and annual return.
    static func monthsToFIRE(
        currentInvested: Double,
        monthlySavings: Double,
        monthlyExpenses: Double,
        annualReturnRate: Double = 0.07
    ) -> Int? {
        let target = fireNumber(monthlyExpenses: monthlyExpenses)
        guard monthlySavings > 0 else { return nil }

        let monthlyReturn = annualReturnRate / 12
        var portfolio = currentInvested
        var months = 0
        let maxMonths = 12 * 100 // Cap at 100 years

        while portfolio < target && months < maxMonths {
            portfolio = portfolio * (1 + monthlyReturn) + monthlySavings
            months += 1
        }

        return months < maxMonths ? months : nil
    }

    /// Coast FIRE: the amount needed now so that with zero additional savings,
    /// compound growth alone reaches FIRE number by target age.
    static func coastFIRENumber(
        monthlyExpenses: Double,
        currentAge: Int,
        targetAge: Int = 65,
        annualReturnRate: Double = 0.07
    ) -> Double {
        let target = fireNumber(monthlyExpenses: monthlyExpenses)
        let years = Double(targetAge - currentAge)
        guard years > 0 else { return target }

        // PV = FV / (1 + r)^n
        return target / pow(1 + annualReturnRate, years)
    }

    /// Savings rate as a percentage.
    static func savingsRate(monthlyIncome: Double, monthlyExpenses: Double) -> Double {
        guard monthlyIncome > 0 else { return 0 }
        return (monthlyIncome - monthlyExpenses) / monthlyIncome * 100
    }

    /// Years of living expenses covered by current investments.
    static func yearsOfExpensesCovered(totalInvested: Double, monthlyExpenses: Double) -> Double {
        guard monthlyExpenses > 0 else { return 0 }
        return totalInvested / (monthlyExpenses * 12)
    }

    /// Projected FIRE date.
    static func projectedFIREDate(
        currentInvested: Double,
        monthlySavings: Double,
        monthlyExpenses: Double
    ) -> Date? {
        guard let months = monthsToFIRE(
            currentInvested: currentInvested,
            monthlySavings: monthlySavings,
            monthlyExpenses: monthlyExpenses
        ) else { return nil }

        return Calendar.current.date(byAdding: .month, value: months, to: Date())
    }
}
