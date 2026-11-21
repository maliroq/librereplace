import XCTest
import Foundation
@testable import LibreReplaceCore

final class StudioCommunityReviewNotesTests: XCTestCase {
    private func plan() throws -> StudioComposedPlan {
        let editor = StudioComponent(id: "free.editor", name: "Editor", kind: .openSourceApp,
            capabilities: [.init("edit", .full, evidence: .documented)])
        let export = StudioComponent(id: "bridge.export", name: "Export bridge", kind: .builtInBridge,
            capabilities: [.init("export", .full, evidence: .documented)])
        return try XCTUnwrap(StudioFreeStackComposer.compose(components: [editor, export],
            request: .init(requirements: [.init("edit"), .init("export")], macOSMajor: 14))
            .first(where: { $0.components.count == 2 && $0.readiness == .eligibleForTrial }))
    }

    func testOnlyExactCompletedTrialCanCreateReviewNotes() throws {
        let plan = try plan()
        let receipt = StudioWorkflowTrial(planIdentity: StudioWorkflowTrialStore.identity(for: plan),
            testedRequirementIDs: ["edit", "export"], macOSMajor: 14, interoperabilityConfirmed: true)
        let notes = try StudioCommunityReviewNotes.render(plan: plan, trial: receipt, sourceAppName: "Paid Editor")
        XCTAssertTrue(notes.contains("user-reported trial"))
        XCTAssertTrue(notes.contains("Multi-tool file/result handoff personally tested: Yes"))
        XCTAssertTrue(notes.contains("- edit: user marked successful"))
        XCTAssertTrue(notes.contains("- export: user marked successful"))
        XCTAssertFalse(notes.contains("home/"))
        XCTAssertFalse(notes.contains("Automatically verified"))
    }

    func testMissingHandoffAndChangedIdentityCannotExport() throws {
        let plan = try plan()
        let noHandoff = StudioWorkflowTrial(planIdentity: StudioWorkflowTrialStore.identity(for: plan),
            testedRequirementIDs: ["edit", "export"], macOSMajor: 14)
        XCTAssertThrowsError(try StudioCommunityReviewNotes.render(plan: plan, trial: noHandoff, sourceAppName: "Paid Editor"))
        let stale = StudioWorkflowTrial(planIdentity: "old-components",
            testedRequirementIDs: ["edit", "export"], macOSMajor: 14, interoperabilityConfirmed: true)
        XCTAssertThrowsError(try StudioCommunityReviewNotes.render(plan: plan, trial: stale, sourceAppName: "Paid Editor"))
    }
}
