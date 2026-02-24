import Testing
@testable import StayCell

@Suite("FIRE Calculator")
struct FIRECalculatorTests {
    @Test("FIRE number is 25x annual expenses")
    func fireNumber() {
        let result = FIRECalculator.fireNumber(monthlyExpenses: 3000)
        #expect(result == 900_000) // 3000 * 12 * 25
    }

    @Test("Savings rate calculation")
    func savingsRate() {
        let rate = FIRECalculator.savingsRate(monthlyIncome: 5000, monthlyExpenses: 3000)
        #expect(rate == 40.0) // (5000-3000)/5000 * 100
    }

    @Test("Savings rate with zero income is zero")
    func savingsRateZeroIncome() {
        let rate = FIRECalculator.savingsRate(monthlyIncome: 0, monthlyExpenses: 1000)
        #expect(rate == 0)
    }

    @Test("Years of expenses covered")
    func yearsCovered() {
        let years = FIRECalculator.yearsOfExpensesCovered(totalInvested: 180_000, monthlyExpenses: 3000)
        #expect(years == 5.0) // 180000 / (3000*12)
    }

    @Test("Months to FIRE returns nil with zero savings")
    func monthsToFIREZeroSavings() {
        let months = FIRECalculator.monthsToFIRE(
            currentInvested: 0,
            monthlySavings: 0,
            monthlyExpenses: 3000
        )
        #expect(months == nil)
    }

    @Test("Months to FIRE is finite with positive savings")
    func monthsToFIREPositive() {
        let months = FIRECalculator.monthsToFIRE(
            currentInvested: 100_000,
            monthlySavings: 2000,
            monthlyExpenses: 3000
        )
        #expect(months != nil)
        #expect(months! > 0)
        #expect(months! < 600) // Should be reachable within 50 years
    }

    @Test("Coast FIRE number is less than FIRE number")
    func coastFIRE() {
        let full = FIRECalculator.fireNumber(monthlyExpenses: 3000)
        let coast = FIRECalculator.coastFIRENumber(monthlyExpenses: 3000, currentAge: 30)
        #expect(coast < full)
        #expect(coast > 0)
    }
}
