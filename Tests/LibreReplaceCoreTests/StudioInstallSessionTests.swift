import XCTest
import Foundation
@testable import LibreReplaceCore

final class StudioInstallSessionTests: XCTestCase {
    private func plan(kind: StudioInstallationKind = .homebrewCask, package: String = "safe-app", required: Bool = true) throws -> StudioComposedPlan {
        let component = StudioComponent(id: "app.safe", name: "Safe app", kind: .openSourceApp,
            capabilities: [.init("capture", required ? .full : .none, evidence: .documented)],
            installation: kind, packageToken: package)
        return try XCTUnwrap(StudioFreeStackComposer.compose(components: [component],
            request: .init(requirements: [.init("capture")], macOSMajor: 14)).first)
    }
    func testReviewedAppCreatesTypedCaskArguments() throws {
        let item = try XCTUnwrap(StudioInstallApproval.proposals(for: plan()).first)
        XCTAssertEqual(item.arguments, ["install", "--cask", "safe-app"])
        XCTAssertEqual(item.installedCheckArguments, ["list", "--cask", "safe-app"])
    }
    func testFormulaUsesDistinctArguments() throws {
        let item = try XCTUnwrap(StudioInstallApproval.proposals(for: plan(kind: .homebrewFormula)).first)
        XCTAssertEqual(item.arguments, ["install", "safe-app"])
        XCTAssertEqual(item.installedCheckArguments, ["list", "--formula", "safe-app"])
    }
    func testUnknownSelectionRejectedWithoutExecuting() throws {
        XCTAssertThrowsError(try StudioInstallApproval.approve(plan: plan(), selectedIDs: ["app.evil"]))
    }
    func testEmptyApprovalRejected() throws {
        XCTAssertThrowsError(try StudioInstallApproval.approve(plan: plan(), selectedIDs: []))
    }
    func testUnsafePackageCannotProduceInstallProposal() throws {
        XCTAssertTrue(StudioInstallApproval.proposals(for: try plan(package: "x;rm -rf")).isEmpty)
        XCTAssertThrowsError(try StudioInstallApproval.approve(plan: plan(package: "x;rm -rf"), selectedIDs: ["app.safe"]))
    }
    func testApprovalContainsOnlyExplicitlySelectedPackage() throws {
        let p = try plan()
        XCTAssertEqual(try StudioInstallApproval.approve(plan: p, selectedIDs: ["app.safe"]).map(\.package), ["safe-app"])
    }
    func testJournalRoundTripKeepsExecutionStateNotLogOutput() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        var journal = StudioInstallJournal()
        journal.append(.init(componentID: "app.safe", package: "safe-app", state: .installSucceeded,
                             message: "Homebrew exited successfully; workflow unverified"))
        let url = try StudioInstallJournalStore.save(journal, in: base)
        let decoded = try JSONDecoder().decode(StudioInstallJournal.self, from: Data(contentsOf: url))
        XCTAssertEqual(decoded.events.count, 1)
        XCTAssertEqual(decoded.events[0].state, .installSucceeded)
        XCTAssertTrue(url.path.contains("Install History"))
    }
    func testExactPreflightRejectsChangedPackageKindOrID() throws {
        let item = try XCTUnwrap(StudioInstallApproval.proposals(for: plan()).first)
        let checkedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let receipt = try XCTUnwrap(StudioInstallPreflight(items: [item], checkedAt: checkedAt))
        let now = checkedAt.addingTimeInterval(30)
        XCTAssertTrue(receipt.permits([item], now: now))
        XCTAssertFalse(receipt.permits([item, item], now: now))
        XCTAssertFalse(receipt.permits([], now: now))
        XCTAssertFalse(receipt.permits([.init(componentID: item.id, name: item.name,
            package: "unexpected", kind: item.kind)], now: now))
        XCTAssertFalse(receipt.permits([.init(componentID: item.id, name: item.name,
            package: item.package, kind: .homebrewFormula)], now: now))
        XCTAssertFalse(receipt.permits([.init(componentID: "app.other", name: item.name,
            package: item.package, kind: item.kind)], now: now))
    }

    func testPreflightExpiresAndRejectsUncheckedOrUnsafeTokens() throws {
        let item = try XCTUnwrap(StudioInstallApproval.proposals(for: plan()).first)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let receipt = try XCTUnwrap(StudioInstallPreflight(items: [item], checkedAt: start))
        XCTAssertFalse(receipt.permits([item], now: start.addingTimeInterval(-1)))
        XCTAssertTrue(receipt.permits([item], now: start.addingTimeInterval(600)))
        XCTAssertFalse(receipt.permits([item], now: start.addingTimeInterval(601)))
        XCTAssertNil(StudioInstallPreflight(items: []))
        XCTAssertNil(StudioInstallPreflight(items: [item, item]))
        XCTAssertNil(StudioInstallPreflight(items: [.init(componentID: item.id, name: item.name,
            package: "bad;command", kind: item.kind)]))
    }

    func testInstallJournalDistinguishesHomebrewAndWorkflowVerification() throws {
        var journal = StudioInstallJournal()
        journal.append(.init(componentID: "app.safe", package: "safe-app", state: .installSucceeded,
                             message: "Homebrew finished"))
        journal.append(.init(componentID: "app.safe", package: "safe-app", state: .installVerified,
                             message: "Homebrew confirms installed, not app function"))
        let encoded = try JSONEncoder().encode(journal)
        let decoded = try JSONDecoder().decode(StudioInstallJournal.self, from: encoded)
        XCTAssertEqual(decoded.events.map(\.state), [.installSucceeded, .installVerified])
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("workflowVerified"))
    }

    func testReadOnlyJournalHasNoAutomaticRollback() throws {
        let journal = StudioInstallJournal()
        let encoded = String(decoding: try JSONEncoder().encode(journal), as: UTF8.self)
        XCTAssertFalse(encoded.contains("uninstall"))
        XCTAssertFalse(encoded.contains("rollbackComplete"))
    }
}
