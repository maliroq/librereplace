import XCTest
@testable import LibreReplaceCore

final class StudioFoundationTests: XCTestCase {
    private let ocr = StudioComponent(id: "ocr-bridge", name: "OCR bridge", kind: .builtInBridge,
        capabilities: [.init("ocr", .full, evidence: .documented)])
    private let notes = StudioComponent(id: "notes-app", name: "Notes tool", kind: .openSourceApp,
        capabilities: [.init("notes", .full, evidence: .documented)])
    private let converter = StudioComponent(id: "converter", name: "Converter", kind: .externalEngine,
        capabilities: [.init("convert", .full, evidence: .documented)],
        installation: .homebrewFormula, packageToken: "converter")

    private func compose(_ reqs: [StudioCapabilityRequirement], from components: [StudioComponent]) -> [StudioComposedPlan] {
        StudioFreeStackComposer.compose(components: components, request: .init(requirements: reqs, macOSMajor: 14))
    }

    func testMultiComponentCompositionSatisfiesEssentials() throws {
        let result = compose([.init("ocr"), .init("notes")], from: [ocr, notes])
        let complete = try XCTUnwrap(result.first { $0.readiness == .eligibleForTrial })
        XCTAssertEqual(complete.components.map(\.id), ["notes-app", "ocr-bridge"])
        XCTAssertFalse(complete.workflowVerified)
        XCTAssertTrue(complete.warnings.contains { $0.contains("interoperability") })
    }

    func testUnknownIsNotFullParity() {
        let suspect = StudioComponent(id: "guess", name: "Guess", kind: .openSourceApp,
            capabilities: [.init("ocr", .full, evidence: .unverified)])
        let result = compose([.init("ocr")], from: [suspect])
        XCTAssertEqual(result.first?.coverage.first?.state, .unverified)
        XCTAssertEqual(result.first?.readiness, .incomplete)
    }

    func testCriticalRequirementBlocksReadyStatus() {
        let result = compose([.init("ocr"), .init("transcribe")], from: [ocr])
        XCTAssertEqual(result.first?.readiness, .incomplete)
    }

    func testOptionalMissingDoesNotBlockTrial() {
        let result = compose([.init("ocr"), .init("transcribe", essential: false)], from: [ocr])
        XCTAssertEqual(result.first?.readiness, .eligibleForTrial)
    }

    func testConflictPreventsPair() {
        let conflicting = StudioComponent(id: "other", name: "Other", kind: .openSourceApp,
            capabilities: [.init("notes", .full, evidence: .documented)], conflictsWith: ["ocr-bridge"])
        let result = compose([.init("ocr"), .init("notes")], from: [ocr, conflicting])
        XCTAssertFalse(result.contains { $0.components.count == 2 })
    }

    func testDependencyRequiresAnotherComponentOrInstalled() {
        let dependent = StudioComponent(id: "needs-converter", name: "Dependent", kind: .openSourceApp,
            capabilities: [.init("notes", .full, evidence: .documented)], requires: ["converter"])
        let results = compose([.init("notes")], from: [dependent, converter])
        XCTAssertFalse(results.contains { $0.components.map(\.id) == ["needs-converter"] })
        XCTAssertTrue(results.contains { Set($0.components.map(\.id)) == Set(["needs-converter", "converter"]) })
    }

    func testOldMacExcludesNewComponent() {
        let modern = StudioComponent(id: "modern", name: "Modern", kind: .openSourceApp, minimumMacOSMajor: 15,
            capabilities: [.init("ocr", .full, evidence: .documented)])
        XCTAssertTrue(compose([.init("ocr")], from: [modern]).isEmpty)
    }

    func testDeterministicSortAcrossInputOrder() {
        let reqs: [StudioCapabilityRequirement] = [.init("ocr"), .init("notes")]
        let first = compose(reqs, from: [ocr, notes]).map { $0.components.map(\.id).joined(separator: ",") }
        let second = compose(reqs, from: [notes, ocr]).map { $0.components.map(\.id).joined(separator: ",") }
        XCTAssertEqual(first, second)
    }

    func testNoRuntimeVerificationClaim() {
        XCTAssertTrue(compose([.init("ocr")], from: [ocr]).allSatisfy { !$0.workflowVerified })
    }

    private func recipeData(extraActionFields: String = "", kind: String = "invokeBuiltInBridge", target: String = "ocr-bridge", extraRoot: String = "") -> Data {
        let json = """
        {"schemaVersion":1,"id":"ocr-demo","sourceWorkflow":"Try OCR",
         "requirements":[{"id":"ocr","essential":true}],
         "componentIDs":["ocr-bridge"],
         "actions":[{"kind":"\(kind)","targetID":"\(target)"\(extraActionFields)}]\(extraRoot)}
        """
        return Data(json.utf8)
    }

    func testRecipeValidatesTypedBridge() throws {
        let recipe = try StudioSafeRecipeLoader.decodeAndValidate(recipeData(), catalog: [ocr])
        XCTAssertEqual(recipe.id, "ocr-demo")
    }

    func testRecipeRejectsArbitraryShellField() {
        XCTAssertThrowsError(try StudioSafeRecipeLoader.decodeAndValidate(recipeData(extraActionFields: ",\"shell\":\"rm -rf /\""), catalog: [ocr]))
    }

    func testRecipeRejectsUnknownTopLevelFields() {
        XCTAssertThrowsError(try StudioSafeRecipeLoader.decodeAndValidate(recipeData(extraRoot: ",\"downloadAndExecute\":true"), catalog: [ocr]))
    }

    func testRecipeRejectsInstallOnBridge() {
        XCTAssertThrowsError(try StudioSafeRecipeLoader.decodeAndValidate(recipeData(kind: "installHomebrewCask"), catalog: [ocr]))
    }

    func testRecipeRejectsUnknownComponent() {
        XCTAssertThrowsError(try StudioSafeRecipeLoader.decodeAndValidate(recipeData(target: "unknown"), catalog: [ocr]))
    }

    func testRecipeRejectsUnsupportedOperation() {
        XCTAssertThrowsError(try StudioSafeRecipeLoader.decodeAndValidate(recipeData(kind: "runShell"), catalog: [ocr]))
    }

    func testUnrelatedLargeCatalogIsScopedBeforeSearch() {
        let noise = (0..<40).map { index in
            StudioComponent(id: "noise-\(index)", name: "Unrelated", kind: .openSourceApp,
                      capabilities: [.init("irrelevant", .full, evidence: .documented)])
        }
        let results = compose([.init("ocr")], from: noise + [ocr])
        XCTAssertEqual(results.first?.readiness, .eligibleForTrial)
    }

    func testRecipeRejectsOversizedData() {
        let data = Data(repeating: UInt8(ascii: "a"), count: 256 * 1024 + 1)
        XCTAssertThrowsError(try StudioSafeRecipeLoader.decodeAndValidate(data, catalog: [ocr]))
    }

    func testRecipeRejectsDuplicateCatalogIDs() {
        XCTAssertThrowsError(try StudioSafeRecipeLoader.decodeAndValidate(recipeData(), catalog: [ocr, ocr]))
    }

    func testInvalidOrEmptyRequirementsAreNotPlans() {
        XCTAssertTrue(compose([], from: [ocr]).isEmpty)
    }
}
