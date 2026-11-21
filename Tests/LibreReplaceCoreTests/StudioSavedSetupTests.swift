import XCTest
import Foundation
@testable import LibreReplaceCore

final class StudioSavedSetupTests: XCTestCase {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lr-shelf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func sample() -> StudioSavedSetup {
        StudioSavedSetup(paidAppID: "cleanshot-x", requiredFeatureIDs: ["screenshots"],
                         componentIDs: ["app.cleanshot-x.snapzy"])
    }
    func testAddLoadDedupeRemovePreservesOtherFiles() throws {
        let dir = try root(); defer { try? FileManager.default.removeItem(at: dir) }
        let extra = dir.appendingPathComponent("personal.txt")
        try Data("user data".utf8).write(to: extra)
        let entry = sample()
        try StudioSavedSetupLibrary.add(entry, in: dir)
        try StudioSavedSetupLibrary.add(entry, in: dir)
        XCTAssertEqual(try StudioSavedSetupLibrary.load(in: dir).count, 1)
        try StudioSavedSetupLibrary.remove(id: entry.id, in: dir)
        XCTAssertTrue(try StudioSavedSetupLibrary.load(in: dir).isEmpty)
        XCTAssertEqual(try String(contentsOf: extra, encoding: .utf8), "user data")
    }
    func testDifferentRequirementsRemainSeparateAndSurviveReload() throws {
        let dir = try root(); defer { try? FileManager.default.removeItem(at: dir) }
        let first = sample()
        let second = StudioSavedSetup(paidAppID: first.paidAppID,
            requiredFeatureIDs: ["screenshots", "ocr"], componentIDs: first.componentIDs)
        try StudioSavedSetupLibrary.add(first, in: dir)
        try StudioSavedSetupLibrary.add(second, in: dir)
        let saved = try StudioSavedSetupLibrary.load(in: dir)
        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(Set(saved.map(\.id)), Set([first.id, second.id]))
        try StudioSavedSetupLibrary.remove(id: first.id, in: dir)
        XCTAssertEqual(try StudioSavedSetupLibrary.load(in: dir), [second])
    }
    func testInvalidSavedDataIsNeverOverwritten() throws {
        let dir = try root(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("LibreReplace/Saved Setups/state-v1.json")
        try FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data("malformed".utf8)
        try data.write(to: f)
        XCTAssertThrowsError(try StudioSavedSetupLibrary.add(sample(), in: dir))
        XCTAssertEqual(try Data(contentsOf: f), data)
    }
    func testSymlinkedLibraryIsBlocked() throws {
        let dir = try root(); defer { try? FileManager.default.removeItem(at: dir) }
        let redirect = dir.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: redirect, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("LibreReplace"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("LibreReplace/Saved Setups"), withDestinationURL: redirect)
        XCTAssertThrowsError(try StudioSavedSetupLibrary.add(sample(), in: dir))
    }
    func testInvalidSelectionNotSaved() throws {
        let dir = try root(); defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertThrowsError(try StudioSavedSetupLibrary.add(StudioSavedSetup(paidAppID: "x",
            requiredFeatureIDs: [], componentIDs: []), in: dir))
    }
}
