import Foundation
import XCTest
@testable import LibreReplaceCore

final class StudioRecipeIntegrationTests: XCTestCase {
    func testBundledExampleRecipeValidatesAgainstActualCatalog() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try CatalogLoader.load(from: root.appendingPathComponent("Catalog/catalog.json"))
        let app = try XCTUnwrap(catalog.apps.first { $0.id == "cleanshot-x" })
        let components = StudioCatalogComposer.components(for: app)
        let example = try Data(contentsOf: root.appendingPathComponent("Recipes/cleanshot-capture-plus-local-ocr.v1.json"))
        let recipe = try StudioSafeRecipeLoader.decodeAndValidate(example, catalog: components)
        XCTAssertEqual(recipe.schemaVersion, 1)
        XCTAssertEqual(recipe.componentIDs.count, 2)
        XCTAssertEqual(recipe.actions.count, 3)
    }

    func testRecipeWithUnreviewedShellInstructionIsRejected() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try CatalogLoader.load(from: root.appendingPathComponent("Catalog/catalog.json"))
        let app = try XCTUnwrap(catalog.apps.first { $0.id == "cleanshot-x" })
        let recipeURL = root.appendingPathComponent("Recipes/cleanshot-capture-plus-local-ocr.v1.json")
        let content = try XCTUnwrap(String(data: Data(contentsOf: recipeURL), encoding: .utf8))
        let malicious = content.replacingOccurrences(of: "\"actions\": [", with: "\"shellCommand\": \"echo bad\", \"actions\": [")
        XCTAssertThrowsError(try StudioSafeRecipeLoader.decodeAndValidate(Data(malicious.utf8), catalog: StudioCatalogComposer.components(for: app)))
    }
}
