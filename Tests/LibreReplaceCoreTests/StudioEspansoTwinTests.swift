import XCTest
import Foundation
@testable import LibreReplaceCore

final class StudioEspansoTwinTests: XCTestCase {
    private func fixture() throws -> (URL, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lr11-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (root, root.appendingPathComponent("espanso", isDirectory: true),
                root.appendingPathComponent("support", isDirectory: true))
    }
    private func sample() -> Data {
        Data("abbreviation,snippet,label\n:hi,Hello there,Greeting\n:multi,\"Line one\nLine two\",Multiline\n:date,%date%,Dynamic\n:hi,conflict,Duplicate\n:thanks,Thank you,Thanks\n".utf8)
    }

    func testBulkConversionWithLargeLibraryAndEscaping() throws {
        var csv = "abbreviation,snippet,label\n"
        for i in 0..<6_000 { csv += ":key\(i),\"Text \(i) with a comma, quote \"\"inside\"\"\",Row \(i)\n" }
        let trial = try StudioSnippetSwitch.audit(data: Data(csv.utf8))
        XCTAssertEqual(trial.readyCount, 6_000)
        XCTAssertEqual(trial.blockedCount, 0)
        let output = try StudioSnippetSwitch.export(trial, as: .espanso)
        XCTAssertTrue(String(decoding: output, as: UTF8.self).contains("Text 5999"))
    }

    func testApprovedSetupPersistsAndUndoRemovesOnlyItsOwnFile() throws {
        let (root, config, support) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let csv = root.appendingPathComponent("export.csv")
        try Data("abbreviation,snippet\n:hello,Hello world\n:welcome,Welcome back\n".utf8).write(to: csv)
        let external = config.appendingPathComponent("match/base.yml")
        try FileManager.default.createDirectory(at: external.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("matches:\n  - trigger: :old\n    replace: old\n".utf8)
        try original.write(to: external)
        let plan = try StudioEspansoTwin.preview(csv: csv, configRoot: config)
        XCTAssertEqual(plan.ready, 2)
        XCTAssertThrowsError(try StudioEspansoTwin.prepare(plan, approved: false, applicationSupport: support))
        let receipt = try StudioEspansoTwin.prepare(plan, approved: true, applicationSupport: support)
        XCTAssertTrue(try StudioEspansoTwin.verify(receipt))
        XCTAssertEqual(try Data(contentsOf: external), original)
        XCTAssertEqual(try StudioEspansoTwin.load(in: support)?.id, receipt.id)
        XCTAssertThrowsError(try StudioEspansoTwin.prepare(plan, approved: true, applicationSupport: support))
        try StudioEspansoTwin.undo(receipt, applicationSupport: support)
        XCTAssertFalse(FileManager.default.fileExists(atPath: receipt.generatedFile.path))
        XCTAssertNil(try StudioEspansoTwin.load(in: support))
        XCTAssertEqual(try Data(contentsOf: external), original)
        XCTAssertEqual(try Data(contentsOf: csv), Data("abbreviation,snippet\n:hello,Hello world\n:welcome,Welcome back\n".utf8))
    }

    func testEditedGeneratedFileCannotBeRolledBack() throws {
        let (root, config, support) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let csv = root.appendingPathComponent("export.csv")
        try Data("abbreviation,snippet\n:one,Text\n".utf8).write(to: csv)
        let plan = try StudioEspansoTwin.preview(csv: csv, configRoot: config)
        let receipt = try StudioEspansoTwin.prepare(plan, approved: true, applicationSupport: support)
        try Data("matches:\n  - trigger: :mine\n    replace: user edit\n".utf8).write(to: receipt.generatedFile)
        XCTAssertFalse(try StudioEspansoTwin.verify(receipt))
        XCTAssertThrowsError(try StudioEspansoTwin.undo(receipt, applicationSupport: support))
        XCTAssertTrue(FileManager.default.fileExists(atPath: receipt.generatedFile.path))
        XCTAssertNotNil(try StudioEspansoTwin.load(in: support))
    }

    func testMissingGeneratedFileCanClearSavedReceipt() throws {
        let (root, config, support) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let csv = root.appendingPathComponent("export.csv")
        try Data("abbreviation,snippet\n:one,Text\n".utf8).write(to: csv)
        let receipt = try StudioEspansoTwin.prepare(StudioEspansoTwin.preview(csv: csv, configRoot: config),
            approved: true, applicationSupport: support)
        try FileManager.default.removeItem(at: receipt.generatedFile)
        try StudioEspansoTwin.undo(receipt, applicationSupport: support)
        XCTAssertNil(try StudioEspansoTwin.load(in: support))
    }

    func testSymlinkMatchFolderRejectedWithoutWriting() throws {
        let (root, config, support) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let other = root.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: config.appendingPathComponent("match"), withDestinationURL: other)
        let csv = root.appendingPathComponent("export.csv")
        try Data("abbreviation,snippet\n:one,Text\n".utf8).write(to: csv)
        let plan = try StudioEspansoTwin.preview(csv: csv, configRoot: config)
        XCTAssertThrowsError(try StudioEspansoTwin.prepare(plan, approved: true, applicationSupport: support))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: other.path).isEmpty)
    }

    func testUnsupportedAndDuplicateSnippetsNeverExport() throws {
        let trial = try StudioSnippetSwitch.audit(data: sample())
        XCTAssertEqual(trial.readyCount, 2) // :multi and :thanks
        XCTAssertEqual(trial.needsReviewCount, 1)
        XCTAssertEqual(trial.blockedCount, 2)
        let output = String(decoding: try StudioSnippetSwitch.export(trial, as: .espanso), as: UTF8.self)
        XCTAssertTrue(output.contains(":multi"))
        XCTAssertFalse(output.contains("%date%"))
        XCTAssertFalse(output.contains(":hi"))
    }

    func testClipboardAndCursorBridgesRemainExecutableWithoutShell() throws {
        let csv = "abbreviation,snippet\n:clip,Before %clipboard after\n:cursor,Hello %|world\n:script,%filltext:name=Name%\n"
        let audit = try StudioSnippetSwitch.audit(data: Data(csv.utf8))
        XCTAssertEqual(audit.readyCount, 2)
        XCTAssertEqual(audit.needsReviewCount, 1)
        let output = String(decoding: try StudioSnippetSwitch.export(audit, as: .espanso), as: UTF8.self)
        XCTAssertTrue(output.contains("{{lr_clipboard}}"))
        XCTAssertTrue(output.contains("type: clipboard"))
        XCTAssertTrue(output.contains("$|$"))
        XCTAssertFalse(output.contains("type: shell"))
        XCTAssertFalse(output.contains("%filltext"))
        XCTAssertThrowsError(try StudioSnippetSwitch.export(audit, as: .macTextReplacements))
    }

    func testCommonDateFormatsProduceEspansoDateVariables() throws {
        let csv = "abbreviation,snippet\n:iso,Today %Y-%m-%d\n:time,At %H:%M\n:math,%date:yyyy%\n"
        let audit = try StudioSnippetSwitch.audit(data: Data(csv.utf8))
        XCTAssertEqual(audit.readyCount, 2)
        XCTAssertEqual(audit.needsReviewCount, 1)
        let yaml = String(decoding: try StudioSnippetSwitch.export(audit, as: .espanso), as: UTF8.self)
        XCTAssertTrue(yaml.contains("name: lr_date_iso"))
        XCTAssertTrue(yaml.contains("name: lr_time_hm"))
        XCTAssertTrue(yaml.contains("format: \"%Y-%m-%d\""))
        XCTAssertTrue(yaml.contains("type: date"))
        XCTAssertFalse(yaml.contains("%date:yyyy%"))
    }

    func testSeveralExportGroupsDetectConflictingShortcuts() throws {
        let (root, _, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("GroupA.csv")
        let second = root.appendingPathComponent("GroupB.csv")
        try Data("abbreviation,snippet\n:same,Group A\n:unique,Only A\n".utf8).write(to: first)
        try Data("abbreviation,snippet\n:SAME,Group B\n:unique2,Only B\n".utf8).write(to: second)
        let trial = try StudioSnippetSwitch.audit(files: [first, second])
        XCTAssertEqual(trial.readyCount, 2)
        XCTAssertEqual(trial.blockedCount, 2)
        XCTAssertThrowsError(try StudioSnippetSwitch.audit(files: [first, first]))
    }

    func testMalformedCsvDoesNotTouchFilesystem() throws {
        XCTAssertThrowsError(try StudioSnippetSwitch.audit(data: Data("abbreviation,snippet\n:bad,\"broken".utf8)))
        let duplicate = try StudioSnippetSwitch.audit(data: Data("abbreviation,snippet\n:one,ok\n:ONE,no\n".utf8))
        XCTAssertEqual(duplicate.readyCount, 0)
        XCTAssertEqual(duplicate.blockedCount, 2)
    }
}
