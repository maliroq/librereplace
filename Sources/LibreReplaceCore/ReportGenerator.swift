import Foundation

public struct ReportSummary: Hashable, Sendable {
    public let applicationsDetected: Int
    public let paidApplicationsDetected: Int
    public let strongReplacements: Int
    public let partialReplacements: Int
    public let keepApps: Int
    public let annualSavingsUSD: Decimal
    public let openSourceCoverageScore: Int

    public init(applicationsDetected: Int, recommendations: [AppRecommendation], annualCostOverrides: [String: Decimal] = [:]) {
        self.applicationsDetected = applicationsDetected
        self.paidApplicationsDetected = recommendations.count
        self.strongReplacements = recommendations.filter { $0.level == .strong }.count
        self.partialReplacements = recommendations.filter { $0.level == .partial }.count
        self.keepApps = recommendations.filter { $0.level == .keep }.count
        self.annualSavingsUSD = SavingsCalculator.annualSavings(for: recommendations, annualCostOverrides: annualCostOverrides)
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
            "- Potential annual recurring savings: $\(NSDecimalNumber(decimal: summary.annualSavingsUSD).stringValue)",
            "- Open-source coverage score: \(summary.openSourceCoverageScore)%",
            "",
            "> Generated locally. By default this summary does not include your complete application inventory."
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
