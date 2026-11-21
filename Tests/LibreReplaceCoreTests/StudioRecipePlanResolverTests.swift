import XCTest
import Foundation
@testable import LibreReplaceCore

final class StudioRecipePlanResolverTests: XCTestCase {
    private func catalog() throws -> Catalog {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try CatalogLoader.load(from: root.appendingPathComponent("Catalog/catalog.json"))
    }

    func testImportedRecipeCanOpenAnExactCurrentPlanWithoutExecutingIt() throws {
        let catalog = try catalog()
        let app = try XCTUnwrap(catalog.apps.first { $0.id == "transmit" })
        let plan = try XCTUnwrap(StudioCatalogComposer.compose(for: app,
            requiredFeatureIDs: ["sftp"], macOSMajor: 27, limit: 128)
            .first { $0.readiness == .eligibleForTrial })
        let recipe = try StudioRecipeFactory.makeDraft(for: plan, workflow: "Try replacing Transmit with an SFTP client").recipe
        let matched = try XCTUnwrap(StudioRecipePlanResolver.resolve(recipe, in: catalog, macOSMajor: 27))
        XCTAssertEqual(matched.sourceApp.id, "transmit")
        XCTAssertEqual(Set(matched.plan.components.map(\.id)), Set(plan.components.map(\.id)))
        XCTAssertEqual(Set(matched.plan.coverage.filter(\.requirement.essential).map(\.requirement.id)), Set(["sftp"]))
    }

    func testBundledExampleRecipeCanBeExploredIfStillCurrent() throws {
        let catalog = try catalog()
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let input = try Data(contentsOf: root.appendingPathComponent("Recipes/cleanshot-capture-plus-local-ocr.v1.json"))
        let known = catalog.apps.flatMap { StudioCatalogComposer.components(for: $0) }
        let recipe = try StudioSafeRecipeLoader.decodeAndValidate(input, catalog: known)
        let result = try XCTUnwrap(StudioRecipePlanResolver.resolve(recipe, in: catalog, macOSMajor: 27))
        XCTAssertEqual(result.sourceApp.id, "cleanshot-x")
        XCTAssertEqual(result.plan.components.count, 2)
        let saved = StudioSavedSetup(paidAppID: result.sourceApp.id,
            requiredFeatureIDs: ["capture", "ocr"],
            componentIDs: result.plan.components.map(\.id))
        let reopened = try XCTUnwrap(StudioSavedSetupLibrary.resolve(saved,
            app: result.sourceApp, macOSMajor: 27))
        XCTAssertEqual(Set(reopened.components.map(\.id)), Set(result.plan.components.map(\.id)))
    }

    func testRecipeWithForeignRequirementsDoesNotOpenAsAnotherApp() throws {
        let catalog = try catalog()
        let app = try XCTUnwrap(catalog.apps.first { $0.id == "transmit" })
        let plan = try XCTUnwrap(StudioCatalogComposer.compose(for: app,
            requiredFeatureIDs: ["sftp"], macOSMajor: 27, limit: 128).first)
        let original = try StudioRecipeFactory.makeDraft(for: plan, workflow: "SFTP workflow").recipe
        let altered = StudioReplacementRecipe(id: original.id, sourceWorkflow: original.sourceWorkflow,
            requirements: [StudioCapabilityRequirement("photo-editing", essential: true)],
            componentIDs: original.componentIDs, actions: original.actions)
        XCTAssertNil(StudioRecipePlanResolver.resolve(altered, in: catalog, macOSMajor: 27))
    }

    func testRecipeWithChangedComponentsCannotSilentlySubstitute() throws {
        let catalog = try catalog()
        let app = try XCTUnwrap(catalog.apps.first { $0.id == "transmit" })
        let plan = try XCTUnwrap(StudioCatalogComposer.compose(for: app,
            requiredFeatureIDs: ["sftp"], macOSMajor: 27, limit: 128).first)
        let original = try StudioRecipeFactory.makeDraft(for: plan, workflow: "SFTP workflow").recipe
        let altered = StudioReplacementRecipe(id: original.id, sourceWorkflow: original.sourceWorkflow,
            requirements: original.requirements, componentIDs: ["app.transmit.deleted"], actions: [])
        XCTAssertNil(StudioRecipePlanResolver.resolve(altered, in: catalog, macOSMajor: 27))
    }
}
