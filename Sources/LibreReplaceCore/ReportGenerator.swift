import Foundation

public struct ReportSummary: Hashable, Sendable {
    public let applicationsDetected: Int
    public let paidApplicationsDetected: Int
    public let strongReplacements: Int
    public let partialReplacements: Int
    public let keepApps: Int
    public let annualSavingsUSD: Decimal
    public let openSourceCoverageScore: Int
    public init(
        applicationsDetected: Int,
        recommendations: [AppRecommendation],
        annualCostOverrides: [String: Decimal] = [:],
        selectedSwitchIDs: Set<String> = [],
        confirmedRecurringIDs: Set<String> = [],
        requirementsByApp: [String: Set<String>] = [:],
        selectedAlternativeIDs: [String: String] = [:],
        replacementAnnualCosts: [String: Decimal] = [:],
        confirmedReplacementCostIDs: Set<String> = [],
        confirmedCancellationIDs: Set<String> = []
    ) {
        self.applicationsDetected = applicationsDetected
        self.paidApplicationsDetected = recommendations.count
        self.strongReplacements = recommendations.filter { $0.level == .strong }.count
        self.partialReplacements = recommendations.filter { $0.level == .partial }.count
        self.keepApps = recommendations.filter { $0.level == .keep }.count
        self.annualSavingsUSD = SavingsCalculator.annualSavings(
            for: recommendations,
            annualCostOverrides: annualCostOverrides,
            selectedSwitchIDs: selectedSwitchIDs,
            confirmedRecurringIDs: confirmedRecurringIDs,
            requirementsByApp: requirementsByApp,
            selectedAlternativeIDs: selectedAlternativeIDs,
            replacementAnnualCosts: replacementAnnualCosts,
            confirmedReplacementCostIDs: confirmedReplacementCostIDs,
            confirmedCancellationIDs: confirmedCancellationIDs
        )
        let coverageValues = recommendations.compactMap { $0.bestAlternative?.coverage }
        self.openSourceCoverageScore = coverageValues.isEmpty ? 0 : Int((coverageValues.reduce(0, +) / Double(coverageValues.count) * 100).rounded())
    }
}

public enum ReportGenerator {
    public static func markdown(summary: ReportSummary, includeApplicationNames: Bool = false, recommendations: [AppRecommendation] = []) -> String {
        var lines = [
            "# LibreReplace report",
            "",
            "- Applications detected: \(summary.applicationsDetected)",
            "- Supported commercial applications recognized: \(summary.paidApplicationsDetected)",
            "- Strong replacements: \(summary.strongReplacements)",
            "- Partial replacements: \(summary.partialReplacements)",
            "- Keep current app: \(summary.keepApps)",
            "- Estimated annual net reduction for selected switches (not realized savings): $\(NSDecimalNumber(decimal: summary.annualSavingsUSD).stringValue)",
            "- Open-source coverage score: \(summary.openSourceCoverageScore)%",
            "",
            "> Generated locally. Estimate includes a Strong selected alternative, confirmed original recurring expense, a curated no-cost replacement, and confirmation the original can be cancelled. One-time migration costs, taxes and future pricing are not included. Do not cancel anything until you have migrated and checked your workflows. By default this summary omits your application inventory."
        ]
        if includeApplicationNames {
            lines.append(contentsOf: ["", "## Recognized applications", ""])
            for rec in recommendations.sorted(by: { $0.match.catalogApp.name < $1.match.catalogApp.name }) {
                let best = rec.bestAlternative?.alternative.name ?? "No recommendation"
                lines.append("- \(rec.match.catalogApp.name): \(rec.level.rawValue) — \(best)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
