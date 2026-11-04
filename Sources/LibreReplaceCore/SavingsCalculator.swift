import Foundation

public enum SavingsCalculator {
    /// Conservative *planning* estimate, never proof that a subscription was cancelled.
    /// A selected replacement must be Strong for the user's chosen requirements,
    /// the user must confirm the source can be cancelled, and the replacement's
    /// recurring cost must be known (including curated $0 desktop editions).
    /// Partial/unknown options, missing cost data and stale evidence yield $0.
    public static func annualSavings(
        for recommendations: [AppRecommendation],
        annualCostOverrides: [String: Decimal] = [:],
        selectedSwitchIDs: Set<String> = [],
        confirmedRecurringIDs: Set<String> = [],
        requirementsByApp: [String: Set<String>] = [:],
        selectedAlternativeIDs: [String: String] = [:],
        replacementAnnualCosts: [String: Decimal] = [:],
        confirmedReplacementCostIDs: Set<String> = [],
        confirmedCancellationIDs: Set<String> = [],
        now: Date = Date()
    ) -> Decimal {
        recommendations.reduce(Decimal.zero) { total, recommendation in
            let app = recommendation.match.catalogApp
            guard selectedSwitchIDs.contains(app.id),
                  confirmedRecurringIDs.contains(app.id),
                  confirmedReplacementCostIDs.contains(app.id),
                  confirmedCancellationIDs.contains(app.id),
                  app.pricing.model != .oneTime,
                  app.pricing.model != .paidUpgrade,
                  recommendation.level == .strong,
                  let original = annualCostOverrides[app.id], original > 0,
                  let replacement = replacementAnnualCosts[app.id], replacement >= 0,
                  let chosenID = selectedAlternativeIDs[app.id],
                  let assessment = ExploreDecision.assess(
                    app, requiredFeatureIDs: requirementsByApp[app.id], now: now
                  ).first(where: { $0.ranked.alternative.id == chosenID }),
                  assessment.outcome == .strong
            else { return total }
            let reduction = original - replacement
            // Never call a cost increase a saving. It is still shown in the UI
            // via the user's entered original and replacement costs.
            return reduction > 0 ? total + reduction : total
        }
    }
}
