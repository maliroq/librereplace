import Foundation
import XCTest
@testable import LibreReplaceCore

final class ExploreDecisionTests: XCTestCase {
    private func fixture(model: Pricing.Model = .subscription, support: [String: FeatureSupport] = ["core": .full, "team": .none], verification: String = "2026-11-04") -> PaidApplication {
        let evidence = [Evidence(kind: .feature, title: "Fixture evidence", url: "https://example.org/fixture", lastVerified: verification)]
        let alt = Alternative(id: "oss", name: "OSS example", license: "GPL-3.0", licenseKind: .openSource,
                              repositoryURL: "https://example.org/source", homepageURL: "https://example.org",
                              install: InstallMethod(kind: .officialDownload, value: "https://example.org/download"),
                              support: support, limitations: [], evidence: evidence, lastVerified: verification)
        return PaidApplication(id: "paid", name: "Paid example", vendor: "Example", bundleIdentifiers: [], nameAliases: ["Paid example"],
                               pricing: Pricing(model: model), capabilities: [
                                Capability(id: "core", label: "Basic task", weight: 9, critical: true),
                                Capability(id: "team", label: "Critical team task", weight: 1, critical: false)],
                               alternatives: [alt], policy: RecommendationPolicy(strongThreshold: 0.8, partialThreshold: 0.4),
                               evidence: evidence, lastVerified: verification)
    }
    private var date: Date { CatalogDate.parse("2026-11-04")! }
    func testFreeDesktopReplacementPolicyDefaultsGIMPToZeroCost() {
        let free = Alternative(id: "gimp", name: "GIMP", license: "GPL-3.0",
            licenseKind: .openSource, repositoryURL: nil,
            homepageURL: "https://www.gimp.org/",
            install: InstallMethod(kind: .officialDownload, value: "https://www.gimp.org/downloads/"),
            support: [:], limitations: [], evidence: [], lastVerified: "2026-11-04")
        XCTAssertTrue(ReplacementCostPolicy.isFreeStandalone(free))
    }
    func testNoFreeCostAssumptionForPaidOrHostedChoices() {
        for id in ["cap-studio-mode", "nextcloud-desktop", "vikunja", "bitwarden", "joplin"] {
            let alternative = Alternative(id: id, name: id, license: "AGPL-3.0",
                licenseKind: .openSource, repositoryURL: nil,
                homepageURL: "https://example.org/",
                install: InstallMethod(kind: .officialDownload, value: "https://example.org/"),
                support: [:], limitations: [], evidence: [], lastVerified: "2026-11-04")
            XCTAssertFalse(ReplacementCostPolicy.isFreeStandalone(alternative), id)
        }
    }
    func testFreeCostDefaultNeverAppliesToProprietaryEdition() {
        let alternative = Alternative(id: "gimp", name: "Fake GIMP", license: "proprietary",
            licenseKind: .proprietaryFree, repositoryURL: nil,
            homepageURL: "https://example.org/",
            install: InstallMethod(kind: .officialDownload, value: "https://example.org/"),
            support: [:], limitations: [], evidence: [], lastVerified: "2026-11-04")
        XCTAssertFalse(ReplacementCostPolicy.isFreeStandalone(alternative))
    }
    func testManualDiscoveryNeedsNoInstalledApp() {
        let result = ExploreDecision.assess(fixture(), now: date)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].outcome, .strong)
    }
    func testHighOverallScoreCannotHideMissingRequiredFeature() {
        let result = ExploreDecision.assess(fixture(), requiredFeatureIDs: ["core", "team"], now: date)
        XCTAssertEqual(result[0].outcome, .keep)
        XCTAssertTrue(result[0].incompleteRequired.contains { $0.id == "team" })
    }
    func testUnknownRequiredFeatureIsNotTreatedAsSupported() {
        let result = ExploreDecision.assess(fixture(support: ["core": .full, "team": .unknown]),
                                            requiredFeatureIDs: ["team"], now: date)
        XCTAssertEqual(result[0].outcome, .unknown)
    }
    func testStaleEvidenceCannotProduceStrong() {
        let result = ExploreDecision.assess(fixture(verification: "2025-01-01"), now: date)
        XCTAssertEqual(result[0].outcome, .unknown)
    }
    func testSavingsRequireExplicitOptInAndConfirmedRecurringBilling() {
        let app = fixture()
        let match = AppMatch(installed: InstalledApplication(name: "Paid example", bundleIdentifier: nil,
                            version: nil, path: URL(fileURLWithPath: "/Applications/Paid example.app")),
                            catalogApp: app, confidence: .nameAlias)
        let rec = ReplacementRanker().recommendation(for: match, now: date)
        XCTAssertEqual(SavingsCalculator.annualSavings(for: [rec], annualCostOverrides: [app.id: 120]), 0)
        // Old behavior incorrectly counted the full subscription as savings,
        // without checking replacement costs or the user's ability to cancel.
        XCTAssertEqual(SavingsCalculator.annualSavings(for: [rec], annualCostOverrides: [app.id: 120],
                           selectedSwitchIDs: [app.id], confirmedRecurringIDs: [app.id], now: date), 0)
        XCTAssertEqual(SavingsCalculator.annualSavings(for: [rec], annualCostOverrides: [app.id: 120],
                           selectedSwitchIDs: [app.id], confirmedRecurringIDs: [app.id],
                           selectedAlternativeIDs: [app.id: "oss"], replacementAnnualCosts: [app.id: 0],
                           confirmedReplacementCostIDs: [app.id], confirmedCancellationIDs: [app.id], now: date), 120)
    }
    private func recommendation(for app: PaidApplication, requirements: Set<String>? = nil) -> AppRecommendation {
        let match = AppMatch(installed: InstalledApplication(
            name: "Paid example", bundleIdentifier: nil, version: nil,
            path: URL(fileURLWithPath: "/Applications/Paid example.app")),
            catalogApp: app, confidence: .nameAlias)
        return ReplacementRanker().recommendation(for: match, requiredFeatureIDs: requirements, now: date)
    }

    func testReplacementCostIsSubtractedFromProposedSavings() {
        let app = fixture()
        let rec = recommendation(for: app)
        let amount = SavingsCalculator.annualSavings(
            for: [rec], annualCostOverrides: [app.id: 240],
            selectedSwitchIDs: [app.id], confirmedRecurringIDs: [app.id],
            selectedAlternativeIDs: [app.id: "oss"], replacementAnnualCosts: [app.id: 90],
            confirmedReplacementCostIDs: [app.id], confirmedCancellationIDs: [app.id], now: date)
        XCTAssertEqual(amount, 150)
    }

    func testMissingSelectedAlternativeOrExplicitCostNeverCounts() {
        let app = fixture()
        let rec = recommendation(for: app)
        let common: [String: Decimal] = [app.id: 120]
        XCTAssertEqual(SavingsCalculator.annualSavings(
            for: [rec], annualCostOverrides: common, selectedSwitchIDs: [app.id],
            confirmedRecurringIDs: [app.id], selectedAlternativeIDs: [app.id: "not-an-option"],
            replacementAnnualCosts: [app.id: 0], confirmedReplacementCostIDs: [app.id],
            confirmedCancellationIDs: [app.id], now: date), 0)
        XCTAssertEqual(SavingsCalculator.annualSavings(
            for: [rec], annualCostOverrides: common, selectedSwitchIDs: [app.id],
            confirmedRecurringIDs: [app.id], selectedAlternativeIDs: [app.id: "oss"],
            confirmedReplacementCostIDs: [app.id], confirmedCancellationIDs: [app.id], now: date), 0)
    }

    func testPartialRequiredFeatureCannotCountAsSavings() {
        let app = fixture(support: ["core": .partial, "team": .full])
        let requirements: Set<String> = ["core", "team"]
        let rec = recommendation(for: app, requirements: requirements)
        XCTAssertEqual(rec.level, .partial)
        XCTAssertEqual(SavingsCalculator.annualSavings(
            for: [rec], annualCostOverrides: [app.id: 120],
            selectedSwitchIDs: [app.id], confirmedRecurringIDs: [app.id],
            requirementsByApp: [app.id: requirements], selectedAlternativeIDs: [app.id: "oss"],
            replacementAnnualCosts: [app.id: 0], confirmedReplacementCostIDs: [app.id],
            confirmedCancellationIDs: [app.id], now: date), 0)
    }

    func testReplacementMoreExpensiveCannotProducePositiveSavings() {
        let app = fixture()
        let rec = recommendation(for: app)
        XCTAssertEqual(SavingsCalculator.annualSavings(
            for: [rec], annualCostOverrides: [app.id: 40],
            selectedSwitchIDs: [app.id], confirmedRecurringIDs: [app.id],
            selectedAlternativeIDs: [app.id: "oss"], replacementAnnualCosts: [app.id: 70],
            confirmedReplacementCostIDs: [app.id], confirmedCancellationIDs: [app.id], now: date), 0)
    }

    func testCancellationConfirmationRequiredEvenWithZeroCost() {
        let app = fixture()
        let rec = recommendation(for: app)
        XCTAssertEqual(SavingsCalculator.annualSavings(
            for: [rec], annualCostOverrides: [app.id: 120],
            selectedSwitchIDs: [app.id], confirmedRecurringIDs: [app.id],
            selectedAlternativeIDs: [app.id: "oss"], replacementAnnualCosts: [app.id: 0],
            confirmedReplacementCostIDs: [app.id], now: date), 0)
    }

    func testStaleEvidenceCannotBeIncludedInSavings() {
        let app = fixture(verification: "2025-01-01")
        let match = AppMatch(installed: InstalledApplication(name: "Paid example", bundleIdentifier: nil,
                            version: nil, path: URL(fileURLWithPath: "/Applications/Paid example.app")),
                            catalogApp: app, confidence: .nameAlias)
        let rec = ReplacementRanker().recommendation(for: match, now: date)
        XCTAssertEqual(SavingsCalculator.annualSavings(for: [rec], annualCostOverrides: [app.id: 120],
                           selectedSwitchIDs: [app.id], confirmedRecurringIDs: [app.id]), 0)
    }
    func testSelectedFeaturesControlCoverage() {
        let app = fixture(support: ["core": .partial, "team": .full])
        let selected = ExploreDecision.assess(
            app, requiredFeatureIDs: ["team"], now: date
        )
        XCTAssertEqual(selected[0].ranked.coverage, 1.0, accuracy: 0.0001)
        XCTAssertEqual(selected[0].outcome, .strong)

        let both = ExploreDecision.assess(
            app, requiredFeatureIDs: ["core", "team"], now: date
        )
        XCTAssertEqual(both[0].ranked.coverage, 0.55, accuracy: 0.0001)
        XCTAssertEqual(both[0].outcome, .partial)
    }

    func testPartialOptionRanksAheadOfIncompatibleOptionAtSameNumericScore() {
        let base = fixture(support: ["core": .partial, "team": .partial])
        let incompatible = Alternative(
            id: "incompatible", name: "AAA Incompatible", license: "MIT", licenseKind: .openSource,
            repositoryURL: "https://example.org/source", homepageURL: "https://example.org",
            install: InstallMethod(kind: .officialDownload, value: "https://example.org/download"),
            support: ["core": .full, "team": .none], limitations: [],
            evidence: base.evidence, lastVerified: "2026-11-04"
        )
        let app = PaidApplication(
            id: base.id, name: base.name, vendor: base.vendor,
            bundleIdentifiers: base.bundleIdentifiers, nameAliases: base.nameAliases,
            pricing: base.pricing, capabilities: base.capabilities,
            alternatives: [incompatible, base.alternatives[0]],
            policy: base.policy, evidence: base.evidence, lastVerified: base.lastVerified
        )
        let results = ExploreDecision.assess(app, requiredFeatureIDs: ["core", "team"], now: date)
        XCTAssertEqual(results.first?.outcome, .partial)
        XCTAssertEqual(results.first?.ranked.alternative.id, "oss")
    }

    func testNoSelectedRequirementsCannotBeStrong() {
        let result = ExploreDecision.assess(fixture(), requiredFeatureIDs: [], now: date)
        XCTAssertEqual(result[0].outcome, .unknown)
        XCTAssertEqual(result[0].ranked.coverage, 0)
    }
    func testSavingsFollowSelectedRequirements() {
        let app = fixture()
        let match = AppMatch(installed: InstalledApplication(name: "Paid example", bundleIdentifier: nil,
                             version: nil, path: URL(fileURLWithPath: "/Applications/Paid example.app")),
                             catalogApp: app, confidence: .nameAlias)
        let rec = ReplacementRanker().recommendation(for: match, requiredFeatureIDs: ["core", "team"], now: date)
        XCTAssertEqual(rec.level, .keep)
        let amount = SavingsCalculator.annualSavings(for: [rec], annualCostOverrides: [app.id: 120],
                                                     selectedSwitchIDs: [app.id], confirmedRecurringIDs: [app.id],
                                                     requirementsByApp: [app.id: ["core", "team"]])
        XCTAssertEqual(amount, 0)
    }
    func testOneTimePurchaseCannotCountAsAnnualSavings() {
        let app = fixture(model: .oneTime)
        let match = AppMatch(installed: InstalledApplication(name: "Paid example", bundleIdentifier: nil,
                            version: nil, path: URL(fileURLWithPath: "/Applications/Paid example.app")),
                            catalogApp: app, confidence: .nameAlias)
        let rec = ReplacementRanker().recommendation(for: match, now: date)
        XCTAssertEqual(SavingsCalculator.annualSavings(for: [rec], annualCostOverrides: [app.id: 120],
                           selectedSwitchIDs: [app.id], confirmedRecurringIDs: [app.id]), 0)
    }
}
