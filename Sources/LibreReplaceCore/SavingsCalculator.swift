import Foundation

public enum SavingsCalculator {
    /// Counts only recurring costs the user explicitly entered for this session.
    /// Catalog pricing is informational and never treated as proof that a user
    /// currently pays a particular plan or price.
    public static func annualSavings(for recommendations: [AppRecommendation], annualCostOverrides: [String: Decimal] = [:]) -> Decimal {
        recommendations.reduce(Decimal.zero) { total, rec in
            guard rec.level != .keep else { return total }
            let appID = rec.match.catalogApp.id
            guard let amount = annualCostOverrides[appID], amount > 0 else { return total }
            return total + amount
        }
    }
}
