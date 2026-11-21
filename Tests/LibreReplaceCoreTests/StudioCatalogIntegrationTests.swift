import Foundation
import XCTest
@testable import LibreReplaceCore

final class StudioCatalogIntegrationTests: XCTestCase {
    private func makeApp(fresh: Bool = true, firstSupport: FeatureSupport = .full, license: AlternativeLicenseKind = .openSource, minimumMacOS: String? = "13.0") -> PaidApplication {
        let verified = fresh ? "2026-11-01" : "2025-01-01"
        let evidence = Evidence(kind: .feature, title: "Reviewed source", url: "https://example.org/source", lastVerified: verified)
        let alternative = Alternative(id: "snapzy", name: "Snapzy", license: "MIT", licenseKind: license,
            repositoryURL: "https://example.org/repo", homepageURL: "https://example.org",
            install: InstallMethod(kind: .homebrewCask, value: "snapzy"),
            support: ["capture": firstSupport, "ocr": .none], limitations: [],
            minimumMacOS: minimumMacOS, evidence: [evidence], lastVerified: verified)
        return PaidApplication(id: "cleanshot-x", name: "CleanShot X", vendor: "Vendor", bundleIdentifiers: ["test.shot"],
            nameAliases: [], pricing: Pricing(model: .subscription),
            capabilities: [Capability(id: "capture", label: "Capture", critical: true), Capability(id: "ocr", label: "OCR", critical: true)],
            alternatives: [alternative], policy: RecommendationPolicy(), evidence: [evidence], lastVerified: verified)
    }

    func testComposerConnectsExistingCatalogToBridge() throws {
        let app = makeApp()
        let now = try XCTUnwrap(CatalogDate.parse("2026-11-14"))
        let plans = StudioCatalogComposer.compose(for: app, requiredFeatureIDs: ["capture", "ocr"], macOSMajor: 14, now: now)
        let ready = try XCTUnwrap(plans.first(where: { $0.readiness == .eligibleForTrial }))
        XCTAssertEqual(Set(ready.components.map(\.id)), ["app.cleanshot-x.snapzy", "bridge.image-ocr"])
        XCTAssertFalse(ready.workflowVerified)
        XCTAssertTrue(ready.warnings.contains(where: { $0.contains("interoperability") }))
    }

    func testOldMacRequirementIsNotMistakenForIncompatibility() {
        let components = StudioCatalogComposer.components(for: makeApp(minimumMacOS: "13.0"))
        XCTAssertTrue(components.contains(where: { $0.name == "Snapzy" && $0.minimumMacOSMajor == 13 }))
    }

    func testStaleCatalogEvidenceDoesNotProduceReadyStack() throws {
        let now = try XCTUnwrap(CatalogDate.parse("2026-11-14"))
        let plans = StudioCatalogComposer.compose(for: makeApp(fresh: false), requiredFeatureIDs: ["capture", "ocr"], macOSMajor: 14, now: now)
        XCTAssertFalse(plans.contains(where: { $0.readiness == .eligibleForTrial }))
    }

    func testProprietaryFreeOptionIsNotRepresentedAsOpenSource() {
        let components = StudioCatalogComposer.components(for: makeApp(license: .proprietaryFree))
        XCTAssertFalse(components.contains(where: { $0.name == "Snapzy" }))
    }

    func testUnknownEssentialFeatureIsNotAssumedSupported() throws {
        let now = try XCTUnwrap(CatalogDate.parse("2026-11-14"))
        let plans = StudioCatalogComposer.compose(for: makeApp(firstSupport: .unknown), requiredFeatureIDs: ["capture", "ocr"], macOSMajor: 14, now: now)
        XCTAssertFalse(plans.contains(where: { $0.readiness == .eligibleForTrial }))
    }

    func testNoRequiredFeaturesDoesNotGenerateAReadyClaim() {
        let result = StudioCatalogComposer.compose(for: makeApp(), requiredFeatureIDs: [], macOSMajor: 14)
        XCTAssertTrue(result.isEmpty)
    }

    func testImageOCRNeverClaimsPDFWorkflowCompatibility() {
        let original = makeApp()
        let pdf = PaidApplication(id: "pdf-expert", name: "PDF Expert", vendor: "Vendor", bundleIdentifiers: ["test.pdf"],
            nameAliases: [], pricing: original.pricing, capabilities: original.capabilities, alternatives: original.alternatives,
            policy: original.policy, evidence: original.evidence, lastVerified: original.lastVerified)
        XCTAssertFalse(StudioCatalogComposer.components(for: pdf).contains(where: { $0.kind == .builtInBridge }))
    }
}

extension StudioCatalogIntegrationTests {
    func testAcrobatDocumentOCRBridgeIsPartialAndNotAFullReplacement() throws {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Catalog/catalog.json")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONDecoder().decode(Catalog.self, from: data)
        let app = try XCTUnwrap(catalog.apps.first(where: { $0.id == "acrobat-pro" }))
        let bridge = try XCTUnwrap(StudioCatalogComposer.components(for: app).first(where: { $0.id == "bridge.document-text-ocr" }))
        XCTAssertEqual(bridge.capabilities.first?.support, .partial)
        let plans = StudioCatalogComposer.compose(for: app, requiredFeatureIDs: ["edit", "ocr", "redact"], macOSMajor: 14)
        XCTAssertFalse(plans.contains(where: { $0.readiness == .eligibleForTrial }))
        XCTAssertTrue(plans.contains(where: { $0.components.contains(where: { $0.id == "bridge.document-text-ocr" }) }))
    }
}
