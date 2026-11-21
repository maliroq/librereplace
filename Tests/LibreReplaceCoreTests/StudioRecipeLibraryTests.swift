import XCTest
import Foundation
@testable import LibreReplaceCore

final class StudioRecipeLibraryTests: XCTestCase {
    private var catalog: [StudioComponent] {
        [.init(id: "app.test", name: "Example", kind: .openSourceApp,
               capabilities: [.init("capture", .full, evidence: .documented)],
               installation: .homebrewCask, packageToken: "example")]
    }
    private func recipe(id: String = "community-test") -> Data {
        let content = StudioReplacementRecipe(id: id, sourceWorkflow: "Capture screenshots",
            requirements: [.init("capture")], componentIDs: ["app.test"],
            actions: [.init(kind: .installHomebrewCask, targetID: "app.test")])
        return try! JSONEncoder().encode(content)
    }
    private func temporary() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testImportThenReloadPersistsVersionedRecipe() throws {
        let dir = try temporary()
        defer { try? FileManager.default.removeItem(at: dir) }
        let result = try StudioRecipeLibrary.store(recipe(), catalog: catalog, in: dir)
        XCTAssertEqual(result.recipe.id, "community-test")
        let loaded = try StudioRecipeLibrary.load(catalog: catalog, in: dir)
        XCTAssertEqual(loaded.recipes.map(\.recipe.id), ["community-test"])
        XCTAssertEqual(loaded.skipped.count, 0)
    }
    func testDuplicateDoesNotOverwriteSavedRecipe() throws {
        let dir = try temporary()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = try StudioRecipeLibrary.store(recipe(), catalog: catalog, in: dir)
        let before = try Data(contentsOf: first.url)
        XCTAssertThrowsError(try StudioRecipeLibrary.store(recipe(), catalog: catalog, in: dir))
        XCTAssertEqual(try Data(contentsOf: first.url), before)
    }
    func testRecipeWithUnapprovedShellActionCannotBeSaved() throws {
        let dir = try temporary()
        defer { try? FileManager.default.removeItem(at: dir) }
        var text = String(decoding: recipe(), as: UTF8.self)
        text = text.replacingOccurrences(of: "\"actions\":", with: "\"shell\":\"rm -rf /\",\"actions\":")
        XCTAssertThrowsError(try StudioRecipeLibrary.store(Data(text.utf8), catalog: catalog, in: dir))
        XCTAssertEqual(try StudioRecipeLibrary.load(catalog: catalog, in: dir).recipes.count, 0)
    }
    func testSymlinkRecipeFolderIsRejected() throws {
        let dir = try temporary()
        let outside = try temporary()
        defer { try? FileManager.default.removeItem(at: dir); try? FileManager.default.removeItem(at: outside) }
        let parent = dir.appendingPathComponent("LibreReplace")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: parent.appendingPathComponent("Community Recipes"), withDestinationURL: outside)
        XCTAssertThrowsError(try StudioRecipeLibrary.store(recipe(), catalog: catalog, in: dir))
    }
    func testCorruptedSavedRecipeIsIgnoredDuringLoad() throws {
        let dir = try temporary()
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = StudioRecipeLibrary.directory(in: dir)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not valid json".utf8).write(to: folder.appendingPathComponent("bad.json"))
        let loaded = try StudioRecipeLibrary.load(catalog: catalog, in: dir)
        XCTAssertTrue(loaded.recipes.isEmpty)
        XCTAssertEqual(loaded.skipped, ["bad.json"])
    }
    func testUnknownComponentCannotBeImported() throws {
        let dir = try temporary()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertThrowsError(try StudioRecipeLibrary.store(recipe(), catalog: [], in: dir))
    }
    func testPageLimitAllowsLongPDFs() throws {
        XCTAssertNoThrow(try StudioDocumentLimits.checkPDF(pages: 18, bytes: 1024))
        XCTAssertNoThrow(try StudioDocumentLimits.checkPDF(pages: 500, bytes: StudioDocumentLimits.maximumPDFBytes))
        XCTAssertThrowsError(try StudioDocumentLimits.checkPDF(pages: 501, bytes: 1024))
        XCTAssertThrowsError(try StudioDocumentLimits.checkPDF(pages: 0, bytes: 1024))
        XCTAssertThrowsError(try StudioDocumentLimits.checkPDF(pages: 1, bytes: StudioDocumentLimits.maximumPDFBytes + 1))
        XCTAssertThrowsError(try StudioDocumentLimits.checkPDF(pages: 1, bytes: 0))
    }
}

extension StudioRecipeLibraryTests {
    func testRemovingImportedRecipeDoesNotTouchUnrelatedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lr-import-removal-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let recipes = StudioRecipeLibrary.directory(in: root)
        try FileManager.default.createDirectory(at: recipes, withIntermediateDirectories: true)
        let recipe = recipes.appendingPathComponent("studio-test.json")
        let keep = recipes.appendingPathComponent("another.json")
        try Data("one".utf8).write(to: recipe)
        try Data("two".utf8).write(to: keep)
        try StudioRecipeLibrary.remove(id: "studio-test", in: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recipe.path))
        XCTAssertEqual(try Data(contentsOf: keep), Data("two".utf8))
        XCTAssertThrowsError(try StudioRecipeLibrary.remove(id: "../another", in: root))
    }
    func testImportedRecipeRemovalRefusesSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lr-import-link-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = StudioRecipeLibrary.directory(in: root)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let protected = root.appendingPathComponent("protected.txt")
        try Data("keep".utf8).write(to: protected)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("studio-linked.json"), withDestinationURL: protected)
        XCTAssertThrowsError(try StudioRecipeLibrary.remove(id: "studio-linked", in: root))
        XCTAssertEqual(try Data(contentsOf: protected), Data("keep".utf8))
    }
}
