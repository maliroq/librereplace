import Foundation
import XCTest
@testable import LibreReplaceCore

final class StudioCommunityRegistryTests: XCTestCase {
    private func make(_ ids: [String]) -> Data {
        let builds = ids.map {
            StudioCommunityBuild(id: $0, title: "Reliable free alternative", summary: "A reviewed declaration of a supported free replacement setup.",
                paidApp: "Sample Paid App", freeApps: ["Example Free App"], category: "Productivity", contributor: "Example contributor",
                recipePath: "Community/recipes/\($0).json", recipeSHA256: String(repeating: "a", count: 64), lastReviewed: "2026-11-16")
        }
        return try! JSONEncoder().encode(StudioCommunityIndex(schemaVersion: 1, builds: builds))
    }
    func testEmptyIndexIsValidForPreLaunchRegistry() throws {
        XCTAssertEqual(try StudioCommunityRegistry.read(make([])).count, 0)
    }
    func testValidBuildAndScopedURL() throws {
        let b = try XCTUnwrap(StudioCommunityRegistry.read(make(["sample-build"])).first)
        XCTAssertEqual(StudioCommunityRegistry.recipeURL(for: b).host, "raw.githubusercontent.com")
        XCTAssertTrue(StudioCommunityRegistry.recipeURL(for: b).path.hasSuffix("/Community/recipes/sample-build.json"))
    }
    func testRejectsDuplicateIDs() {
        XCTAssertThrowsError(try StudioCommunityRegistry.read(make(["sample-build", "sample-build"])))
    }
    func testRejectsTraversalAndWrongPath() {
        var encoded = make(["sample-build"])
        var json = try! JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        var builds = json["builds"] as! [[String: Any]]
        builds[0]["recipePath"] = "../../private.json"
        json["builds"] = builds
        encoded = try! JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try StudioCommunityRegistry.read(encoded))
    }
    func testRejectsChecksumWithUppercaseOrWrongLength() {
        var json = try! JSONSerialization.jsonObject(with: make(["sample-build"])) as! [String: Any]
        var builds = json["builds"] as! [[String: Any]]
        builds[0]["recipeSHA256"] = "ABCD"
        json["builds"] = builds
        XCTAssertThrowsError(try StudioCommunityRegistry.read(try! JSONSerialization.data(withJSONObject: json)))
    }
    func testRejectsOversizedIndex() {
        XCTAssertThrowsError(try StudioCommunityRegistry.read(Data(repeating: 0, count: 129 * 1024)))
    }
    func testRejectsUnsupportedVersion() {
        let index = StudioCommunityIndex(schemaVersion: 2, builds: [])
        XCTAssertThrowsError(try StudioCommunityRegistry.read(try! JSONEncoder().encode(index)))
    }
}
