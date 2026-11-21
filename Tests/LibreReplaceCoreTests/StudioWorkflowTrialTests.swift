import Foundation
import XCTest
@testable import LibreReplaceCore

final class StudioWorkflowTrialTests: XCTestCase {
    private let ocr = StudioComponent(id: "local-ocr", name: "OCR", kind: .builtInBridge,
        capabilities: [.init("ocr", .full, evidence: .documented)])
    private let pdf = StudioComponent(id: "pdf-editor", name: "PDF Editor", kind: .openSourceApp,
        capabilities: [.init("edit", .full, evidence: .documented)])

    private func plan(_ features: [StudioCapabilityRequirement]) throws -> StudioComposedPlan {
        try XCTUnwrap(StudioFreeStackComposer.compose(components: [ocr, pdf],
            request: .init(requirements: features, macOSMajor: 14)).first(where: {
                $0.components.count == 2 && $0.readiness == .eligibleForTrial
            }))
    }

    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lr-trials-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testRecordsOnlySuccessfulTrialOfAllRequiredFeatures() throws {
        let folder = try root(); defer { try? FileManager.default.removeItem(at: folder) }
        let plan = try plan([.init("ocr"), .init("edit")])
        XCTAssertThrowsError(try StudioWorkflowTrialStore.recordSuccessfulTrial(
            for: plan, testedRequirementIDs: ["ocr"], macOSMajor: 14, in: folder))
        XCTAssertTrue(try StudioWorkflowTrialStore.load(in: folder).isEmpty)
        XCTAssertThrowsError(try StudioWorkflowTrialStore.recordSuccessfulTrial(
            for: plan, testedRequirementIDs: ["ocr", "edit"], macOSMajor: 14, in: folder))
        let receipt = try StudioWorkflowTrialStore.recordSuccessfulTrial(
            for: plan, testedRequirementIDs: ["ocr", "edit"], macOSMajor: 14,
            interoperabilityConfirmed: true, in: folder)
        XCTAssertEqual(Set(receipt.testedRequirementIDs), ["ocr", "edit"])
        XCTAssertEqual(receipt.interoperabilityConfirmed, true)
        XCTAssertNotNil(try StudioWorkflowTrialStore.matching(plan, macOSMajor: 14, in: folder))
        XCTAssertNil(try StudioWorkflowTrialStore.matching(plan, macOSMajor: 15, in: folder))
        XCTAssertEqual(try StudioWorkflowTrialStore.load(in: folder).count, 1)
        _ = try StudioWorkflowTrialStore.recordSuccessfulTrial(
            for: plan, testedRequirementIDs: ["ocr", "edit"], macOSMajor: 14,
            interoperabilityConfirmed: true, in: folder)
        XCTAssertEqual(try StudioWorkflowTrialStore.load(in: folder).count, 1)
    }

    func testEditedRequirementsCannotReuseTrialReceipt() throws {
        let folder = try root(); defer { try? FileManager.default.removeItem(at: folder) }
        let first = try plan([.init("ocr"), .init("edit")])
        let changed = try plan([.init("ocr"), .init("edit", essential: false)])
        _ = try StudioWorkflowTrialStore.recordSuccessfulTrial(
            for: first, testedRequirementIDs: ["ocr", "edit"], macOSMajor: 14,
            interoperabilityConfirmed: true, in: folder)
        XCTAssertNil(try StudioWorkflowTrialStore.matching(changed, macOSMajor: 14, in: folder))
    }

    func testBrokenHistoryAndSymlinkRemainUntouched() throws {
        let folder = try root(); defer { try? FileManager.default.removeItem(at: folder) }
        let parent = folder.appendingPathComponent("LibreReplace/Workflow Trials")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let file = parent.appendingPathComponent("state-v1.json")
        let malformed = Data("not valid JSON".utf8)
        try malformed.write(to: file)
        let plan = try plan([.init("ocr"), .init("edit")])
        XCTAssertThrowsError(try StudioWorkflowTrialStore.recordSuccessfulTrial(
            for: plan, testedRequirementIDs: ["ocr", "edit"], macOSMajor: 14, in: folder))
        XCTAssertEqual(try Data(contentsOf: file), malformed)
        try FileManager.default.removeItem(at: file)
        let elsewhere = folder.appendingPathComponent("elsewhere.json")
        try Data("keep".utf8).write(to: elsewhere)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: elsewhere)
        XCTAssertThrowsError(try StudioWorkflowTrialStore.recordSuccessfulTrial(
            for: plan, testedRequirementIDs: ["ocr", "edit"], macOSMajor: 14, in: folder))
        XCTAssertEqual(try Data(contentsOf: elsewhere), Data("keep".utf8))
    }

    func testChangedPackageInvalidatesEarlierUserTrial() throws {
        let folder = try root(); defer { try? FileManager.default.removeItem(at: folder) }
        func planned(_ package: String) throws -> StudioComposedPlan {
            let component = StudioComponent(id: "app.editor", name: "Editor", kind: .openSourceApp,
                capabilities: [.init("edit", .full, evidence: .documented)],
                installation: .homebrewCask, packageToken: package)
            return try XCTUnwrap(StudioFreeStackComposer.compose(components: [component],
                request: .init(requirements: [.init("edit")], macOSMajor: 14)).first)
        }
        let original = try planned("safe-editor")
        let changed = try planned("different-editor")
        _ = try StudioWorkflowTrialStore.recordSuccessfulTrial(
            for: original, testedRequirementIDs: ["edit"], macOSMajor: 14, in: folder)
        XCTAssertNotNil(try StudioWorkflowTrialStore.matching(original, macOSMajor: 14, in: folder))
        XCTAssertNil(try StudioWorkflowTrialStore.matching(changed, macOSMajor: 14, in: folder))
    }

    func testEarlierMultiToolReceiptsDoNotClaimInteroperability() throws {
        let folder = try root(); defer { try? FileManager.default.removeItem(at: folder) }
        let combination = try plan([.init("ocr"), .init("edit")])
        let raw = StudioWorkflowTrial(planIdentity: StudioWorkflowTrialStore.identity(for: combination),
            testedRequirementIDs: ["ocr", "edit"], macOSMajor: 14)
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(raw)) as! [String: Any]
        old.removeValue(forKey: "interoperabilityConfirmed")
        let envelope: [String: Any] = ["schemaVersion": 1, "trials": [old]]
        let destination = folder.appendingPathComponent("LibreReplace/Workflow Trials/state-v1.json")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                               withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: envelope).write(to: destination)
        XCTAssertEqual(try StudioWorkflowTrialStore.load(in: folder).count, 1)
        XCTAssertNil(try StudioWorkflowTrialStore.matching(combination, macOSMajor: 14, in: folder))
    }

    func testDifferentEssentialFeaturesProduceDifferentRecipeIDs() throws {
        let allRequired = try plan([.init("ocr"), .init("edit")])
        let oneOptional = try plan([.init("ocr"), .init("edit", essential: false)])
        let first = try StudioRecipeFactory.makeDraft(for: allRequired, workflow: "Try a PDF setup")
        let second = try StudioRecipeFactory.makeDraft(for: oneOptional, workflow: "Try a PDF setup")
        XCTAssertNotEqual(first.recipe.id, second.recipe.id)
        XCTAssertEqual(first.recipe.componentIDs, second.recipe.componentIDs)
    }
}
