import Foundation
import XCTest
@testable import LibreReplaceCore

final class StudioFreeTwinTests: XCTestCase {
    private func fixture() throws -> (FileManager, URL, URL) {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("lr-free-twin-" + UUID().uuidString)
        let user = home.appendingPathComponent("Library/Application Support/Sublime Text/Packages/User")
        try fm.createDirectory(at: user, withIntermediateDirectories: true)
        return (fm, home, user)
    }
    private func snippet(_ body: String, trigger: String, scope: String = "") -> String {
        "<snippet><content><![CDATA[\(body)]]></content><tabTrigger>\(trigger)</tabTrigger><scope>\(scope)</scope><description>Example snippet</description></snippet>"
    }
    func testBulkSnippetMigrationAndCommentPreservation() throws {
        let (fm, home, user) = try fixture(); defer { try? fm.removeItem(at: home) }
        let nested = user.appendingPathComponent("nested")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        for i in 0..<640 { // No 5-page/2-snippet style arbitrary cutoff.
            try snippet("let x = ${1:value\(i)};\n$0", trigger: "my\(i)", scope: "source.js")
                .write(to: nested.appendingPathComponent("test\(i).sublime-snippet"), atomically: true, encoding: .utf8)
        }
        let destination = home.appendingPathComponent(".config/zed/snippets/javascript.json")
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = "{\n // Preserve this comment exactly\n \"Existing\": {\"prefix\":\"existing\", \"body\": [\"ok\"]}\n}\n"
        try original.write(to: destination, atomically: true, encoding: .utf8)
        let sourceBefore = try Data(contentsOf: nested.appendingPathComponent("test0.sublime-snippet"))
        let bridge = StudioSnippetBridge()
        let plan = try bridge.preview(home: home)
        XCTAssertEqual(plan.scanned, 640)
        XCTAssertEqual(plan.ready, 640, "Not all snippets were imported: \(plan.issues.prefix(5).map(\.explanation))")
        XCTAssertEqual(plan.files.count, 1, "Unexpected output files: \(plan.files.map(\.target.path))")
        let finalSnippetName = "LibreReplace: nested/test639.sublime-snippet"
        XCTAssertTrue(plan.files[0].expectedNames.contains(finalSnippetName),
            "Missing nested snippet in plan. Example generated names: \(plan.files[0].expectedNames.suffix(8))")
        XCTAssertEqual(plan.files[0].expectedNames.count, 640)
        XCTAssertTrue(plan.issues.isEmpty, "Snippet issues: \(plan.issues.prefix(10).map { $0.filename + ": " + $0.explanation })")
        let receipt = try bridge.apply(plan, home: home, backupRoot: home.appendingPathComponent("Backups"))
        XCTAssertTrue(bridge.verify(receipt, home: home))
        let changed = try String(contentsOf: destination, encoding: .utf8)
        XCTAssertTrue(changed.contains("// Preserve this comment exactly"))
        XCTAssertTrue(changed.contains("\"Existing\""))
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONC.stripComments(Data(changed.utf8))) as? [String: Any])
        XCTAssertEqual(decoded.count, 641, "Unexpected number of snippets in the merged file")
        XCTAssertNotNil(decoded[finalSnippetName],
            "Imported snippet missing. Closest keys: \(decoded.keys.filter { $0.contains("test639") }.sorted())")
        XCTAssertEqual(try Data(contentsOf: nested.appendingPathComponent("test0.sublime-snippet")), sourceBefore)
        let secondPreview = try bridge.preview(home: home)
        XCTAssertEqual(secondPreview.ready, 0)
        XCTAssertFalse(secondPreview.needsChanges)
        try bridge.rollback(receipt, home: home)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), original)
    }

    func testConservativeCompatibilityAndPartialFailures() throws {
        let (fm, home, user) = try fixture(); defer { try? fm.removeItem(at: home) }
        try snippet("print(${1:value})", trigger: "p", scope: "source.python")
            .write(to: user.appendingPathComponent("good.sublime-snippet"), atomically: true, encoding: .utf8)
        try snippet("$TM_FILENAME", trigger: "f", scope: "source.python")
            .write(to: user.appendingPathComponent("variable.sublime-snippet"), atomically: true, encoding: .utf8)
        try snippet("plain", trigger: "s", scope: "source.unknown")
            .write(to: user.appendingPathComponent("unknown.sublime-snippet"), atomically: true, encoding: .utf8)
        try "<!DOCTYPE foo [<!ENTITY xx SYSTEM 'file:///etc/passwd'>]><snippet><content>&xx;</content></snippet>"
            .write(to: user.appendingPathComponent("external.sublime-snippet"), atomically: true, encoding: .utf8)
        let plan = try StudioSnippetBridge().preview(home: home)
        XCTAssertEqual(plan.scanned, 4)
        XCTAssertEqual(plan.ready, 1)
        XCTAssertEqual(plan.issues.count, 3)
        XCTAssertTrue(plan.files.allSatisfy { $0.target.lastPathComponent == "python.json" })
    }

    func testSnippetStalePreviewAndRecoveryConflictProtectChanges() throws {
        let (fm, home, user) = try fixture(); defer { try? fm.removeItem(at: home) }
        let src = user.appendingPathComponent("test.sublime-snippet")
        try snippet("hello $1", trigger: "hello").write(to: src, atomically: true, encoding: .utf8)
        let bridge = StudioSnippetBridge()
        let plan = try bridge.preview(home: home)
        try snippet("changed $1", trigger: "hello").write(to: src, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try bridge.apply(plan, home: home, backupRoot: home.appendingPathComponent("Backups")))
        let updatedPlan = try bridge.preview(home: home)
        let receipt = try bridge.apply(updatedPlan, home: home, backupRoot: home.appendingPathComponent("Backups"))
        let target = try XCTUnwrap(receipt.changes.first?.target)
        try "{\"my later edits\":{}}".write(to: target, atomically: true, encoding: .utf8)
        XCTAssertFalse(bridge.verify(receipt, home: home))
        XCTAssertThrowsError(try bridge.rollback(receipt, home: home))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "{\"my later edits\":{}}")
    }

    func testSnippetSymlinkAndPrefixConflictNotImported() throws {
        let (fm, home, user) = try fixture(); defer { try? fm.removeItem(at: home) }
        try snippet("ok", trigger: "a").write(to: user.appendingPathComponent("ok.sublime-snippet"), atomically: true, encoding: .utf8)
        let outside = home.appendingPathComponent("private.sublime-snippet")
        try snippet("not read", trigger: "secret").write(to: outside, atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(at: user.appendingPathComponent("symlink.sublime-snippet"), withDestinationURL: outside)
        let zed = home.appendingPathComponent(".config/zed/snippets/snippets.json")
        try fm.createDirectory(at: zed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{\"existing\":{\"prefix\":\"a\",\"body\":[\"existing\"]}}".write(to: zed, atomically: true, encoding: .utf8)
        let plan = try StudioSnippetBridge().preview(home: home)
        XCTAssertEqual(plan.ready, 0)
        XCTAssertEqual(plan.scanned, 2)
        XCTAssertEqual(plan.issues.count, 2)
        XCTAssertFalse(plan.needsChanges)
    }

    func testFreeTwinStorePersistsManyRecordsAndRejectsCorruptState() throws {
        let (fm, home, _) = try fixture(); defer { try? fm.removeItem(at: home) }
        let support = home.appendingPathComponent("Support")
        let store = StudioFreeTwinStore()
        for i in 0..<320 {
            let item = StudioFreeTwinRecord(id: "demo-\(i)", sourceAppID: "paid-\(i)",
                targetBundleID: "free-\(i)", state: .prepared)
            try store.upsert(item, in: support)
        }
        XCTAssertEqual(try store.load(in: support).count, 320)
        try store.remove(id: "demo-150", in: support)
        XCTAssertEqual(try store.load(in: support).count, 319)
        let destination = support.appendingPathComponent("LibreReplace/Free Twins/state-v1.json")
        try "invalid".write(to: destination, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.load(in: support))
        XCTAssertThrowsError(try store.upsert(.init(id: "new", sourceAppID: "a", targetBundleID: "b", state: .prepared), in: support))
    }

    func testLegacySublimeFolderAndSafeRollbackForSettings() throws {
        let (fm, home, _) = try fixture(); defer { try? fm.removeItem(at: home) }
        let legacy = home.appendingPathComponent("Library/Application Support/Sublime Text 3/Packages/User/Preferences.sublime-settings")
        try fm.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"font_size": 13, "word_wrap": true, "draw_white_space": "all", "trim_trailing_white_space_on_save": true}"#
            .write(to: legacy, atomically: true, encoding: .utf8)
        let adapter = SublimeToZedMigration()
        let plan = try adapter.preview(home: home)
        XCTAssertEqual(plan.sourcePath, legacy)
        XCTAssertTrue(plan.changes.contains(where: { $0.key == "soft_wrap" && $0.toValue == "editor_width" }))
        XCTAssertTrue(plan.changes.contains(where: { $0.key == "show_whitespaces" && $0.toValue == "all" }))
        XCTAssertTrue(plan.changes.contains(where: { $0.key == "base_keymap" && $0.toValue == "SublimeText" }))
        let receipt = try adapter.apply(plan: plan, home: home, backupRoot: home.appendingPathComponent("Backups"))
        let target = receipt.targetPath
        try #"{"my":"later change"}"#.write(to: target, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try adapter.rollback(receipt: receipt, home: home))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), #"{"my":"later change"}"#)
    }
    func testJSONCEditingPreservesUnrelatedSettingsAndComments() throws {
        let existing = """
        {
          // user-made comment
          "buffer_font_size": 14, // inline note
          "features": {"nested": [true, {"path": "a}b"}]},
          "message": "braces } and // are literal"
        }
        """
        let changed = try StudioJSONCEditor.merge(Data(existing.utf8), reviewedValues: [
            "buffer_font_size": 18, "base_keymap": "SublimeText", "soft_wrap": "editor_width"
        ])
        let text = try XCTUnwrap(String(data: changed, encoding: .utf8))
        XCTAssertTrue(text.contains("// user-made comment"))
        XCTAssertTrue(text.contains("// inline note"))
        XCTAssertTrue(text.contains("\"features\": {\"nested\": [true, {\"path\": \"a}b\"}]}"))
        let parsed = try StudioJSONCEditor.topLevelDictionary(changed)
        XCTAssertEqual(parsed["base_keymap"] as? String, "SublimeText")
        XCTAssertEqual(parsed["soft_wrap"] as? String, "editor_width")
        XCTAssertEqual(parsed["buffer_font_size"] as? Int, 18)
        XCTAssertEqual(parsed["message"] as? String, "braces } and // are literal")
    }

    func testSettingsRejectSourceChangedAfterPreviewAndPreserveJSONCComments() throws {
        let (fm, home, user) = try fixture(); defer { try? fm.removeItem(at: home) }
        let source = user.appendingPathComponent("Preferences.sublime-settings")
        try #"{"font_size": 16, "tab_size": 2}"#.write(to: source, atomically: true, encoding: .utf8)
        let target = home.appendingPathComponent(".config/zed/settings.json")
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = "{ // my comment\n \"tab_size\": 4, \"custom\": [1,2,3]\n}\n"
        try original.write(to: target, atomically: true, encoding: .utf8)
        let adapter = SublimeToZedMigration()
        let stale = try adapter.preview(home: home)
        try #"{"font_size": 22, "tab_size": 2}"#.write(to: source, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try adapter.apply(plan: stale, home: home, backupRoot: home.appendingPathComponent("Backups")))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), original)
        let fresh = try adapter.preview(home: home)
        let receipt = try adapter.apply(plan: fresh, home: home, backupRoot: home.appendingPathComponent("Backups"))
        let contents = try String(contentsOf: target, encoding: .utf8)
        XCTAssertTrue(contents.contains("// my comment"))
        XCTAssertTrue(contents.contains("\"custom\": [1,2,3]"))
        XCTAssertEqual(try StudioJSONCEditor.topLevelDictionary(Data(contents.utf8))["buffer_font_size"] as? Int, 22)
        try adapter.rollback(receipt: receipt, home: home)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), original)
    }

    func testBothSublimeEditionsAndTSXScope() throws {
        let (fm, home, user) = try fixture(); defer { try? fm.removeItem(at: home) }
        let legacy = home.appendingPathComponent("Library/Application Support/Sublime Text 3/Packages/User")
        try fm.createDirectory(at: legacy, withIntermediateDirectories: true)
        try snippet("hello $1", trigger: "old", scope: "source.tsx")
            .write(to: legacy.appendingPathComponent("legacy.sublime-snippet"), atomically: true, encoding: .utf8)
        try snippet("hello $1", trigger: "new", scope: "source.tsx")
            .write(to: user.appendingPathComponent("new.sublime-snippet"), atomically: true, encoding: .utf8)
        let preview = try StudioSnippetBridge().preview(home: home)
        XCTAssertEqual(preview.scanned, 2)
        XCTAssertEqual(preview.ready, 2)
        XCTAssertEqual(preview.files.map { $0.target.lastPathComponent }, ["tsx.json"])
    }

    func testFreeTwinStoreRefusesSymlinkedStorage() throws {
        let (fm, home, _) = try fixture(); defer { try? fm.removeItem(at: home) }
        let support = home.appendingPathComponent("Support")
        try fm.createDirectory(at: support.appendingPathComponent("LibreReplace"), withIntermediateDirectories: true)
        let outside = home.appendingPathComponent("outside")
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: support.appendingPathComponent("LibreReplace/Free Twins"), withDestinationURL: outside)
        XCTAssertThrowsError(try StudioFreeTwinStore().upsert(.init(id: "test", sourceAppID: "s", targetBundleID: "t", state: .prepared), in: support))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: outside.path).count, 0)
    }

    func testFreeTwinEngineEndToEndPrepareVerifyRepeatAndRecovery() throws {
        let (fm, home, user) = try fixture(); defer { try? fm.removeItem(at: home) }
        let source = user.appendingPathComponent("Preferences.sublime-settings")
        try #"{"font_size":17,"tab_size":4,"translate_tabs_to_spaces":true}"#.write(to: source, atomically: true, encoding: .utf8)
        for i in 0..<30 {
            try snippet("result ${1:x\(i)}", trigger: "key\(i)", scope: "source.python")
                .write(to: user.appendingPathComponent("snippet\(i).sublime-snippet"), atomically: true, encoding: .utf8)
        }
        let support = home.appendingPathComponent("Support")
        let engine = StudioFreeTwinEngine()
        let id = "sublime-zed-workstyle-v1"
        let preview = try engine.preview(id: id, home: home)
        XCTAssertTrue(preview.hasOperations)
        XCTAssertEqual(preview.snippets.ready, 30)
        XCTAssertThrowsError(try engine.prepare(preview, approved: false, home: home, applicationSupport: support))
        XCTAssertFalse(fm.fileExists(atPath: home.appendingPathComponent(".config/zed/settings.json").path))
        let record = try engine.prepare(preview, approved: true, home: home, applicationSupport: support)
        XCTAssertEqual(record.state, .prepared)
        XCTAssertEqual(try StudioFreeTwinStore().load(in: support).count, 1)
        XCTAssertEqual(engine.verifyLocalChanges(record, home: home).count, 2)
        XCTAssertThrowsError(try engine.prepare(preview, approved: true, home: home, applicationSupport: support))
        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent(".config/zed/snippets/python.json").path))
        let sourceAfter = try String(contentsOf: source, encoding: .utf8)
        XCTAssertTrue(sourceAfter.contains("font_size"))
        try engine.rollback(record, home: home, applicationSupport: support)
        XCTAssertTrue(try StudioFreeTwinStore().load(in: support).isEmpty)
        XCTAssertFalse(fm.fileExists(atPath: home.appendingPathComponent(".config/zed/settings.json").path))
        XCTAssertFalse(fm.fileExists(atPath: home.appendingPathComponent(".config/zed/snippets/python.json").path))
        let repeated = try engine.preview(id: id, home: home)
        XCTAssertEqual(repeated.snippets.ready, 30)
        XCTAssertTrue(repeated.hasOperations)
    }

    func testFreeTwinEngineCannotRollbackOverNewEdits() throws {
        let (fm, home, user) = try fixture(); defer { try? fm.removeItem(at: home) }
        let source = user.appendingPathComponent("Preferences.sublime-settings")
        try #"{"font_size":17}"#.write(to: source, atomically: true, encoding: .utf8)
        try snippet("hello", trigger: "a").write(to: user.appendingPathComponent("a.sublime-snippet"), atomically: true, encoding: .utf8)
        let support = home.appendingPathComponent("Support")
        let engine = StudioFreeTwinEngine()
        let record = try engine.prepare(engine.preview(id: "sublime-zed-workstyle-v1", home: home),
                                        approved: true, home: home, applicationSupport: support)
        let changed = home.appendingPathComponent(".config/zed/snippets/snippets.json")
        try #"{"my own edit":{"prefix":"mine","body":["mine"]}}"#.write(to: changed, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try engine.rollback(record, home: home, applicationSupport: support))
        XCTAssertEqual(try StudioFreeTwinStore().load(in: support).count, 1)
        XCTAssertNotNil(fm.contents(atPath: record.settingsReceipt!.targetPath.path))
    }


    func testCommonJSONCTrailingCommasPreservedAcrossSettingsAndSnippets() throws {
        let settings = """
        {
          // Keep user notes
          "tab_size": 2,
          "custom": {"nested": [1,2,],},
        }
        """
        let result = try StudioJSONCEditor.merge(Data(settings.utf8), reviewedValues: [
            "buffer_font_size": 17, "tab_size": 3
        ])
        let updated = try XCTUnwrap(String(data: result, encoding: .utf8))
        XCTAssertTrue(updated.contains("// Keep user notes"))
        XCTAssertTrue(updated.contains("[1,2,]"))
        XCTAssertEqual(try StudioJSONCEditor.topLevelDictionary(result)["tab_size"] as? Int, 3)
        XCTAssertEqual(try StudioJSONCEditor.topLevelDictionary(result)["buffer_font_size"] as? Int, 17)

        let (fm, home, user) = try fixture(); defer { try? fm.removeItem(at: home) }
        try snippet("$1", trigger: "fresh", scope: "source.python")
            .write(to: user.appendingPathComponent("fresh.sublime-snippet"), atomically: true, encoding: .utf8)
        let target = home.appendingPathComponent(".config/zed/snippets/python.json")
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = "{\n // Keep this comment\n \"existing\": {\"prefix\":\"old\",\"body\":[\"value\",],},\n}\n"
        try original.write(to: target, atomically: true, encoding: .utf8)
        let plan = try StudioSnippetBridge().preview(home: home)
        XCTAssertEqual(plan.ready, 1)
        let receipt = try StudioSnippetBridge().apply(plan, home: home, backupRoot: home.appendingPathComponent("Backups"))
        XCTAssertTrue(StudioSnippetBridge().verify(receipt, home: home))
        try StudioSnippetBridge().rollback(receipt, home: home)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), original)
    }

    func testRecoveryRefusesMissingOriginalSettingsBackup() throws {
        let (fm, home, user) = try fixture(); defer { try? fm.removeItem(at: home) }
        try #"{"font_size":14}"#.write(to: user.appendingPathComponent("Preferences.sublime-settings"), atomically: true, encoding: .utf8)
        let destination = home.appendingPathComponent(".config/zed/settings.json")
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"user_setting":true}"#.write(to: destination, atomically: true, encoding: .utf8)
        try snippet("snippet $1", trigger: "a").write(to: user.appendingPathComponent("a.sublime-snippet"), atomically: true, encoding: .utf8)
        let support = home.appendingPathComponent("Support")
        let engine = StudioFreeTwinEngine()
        let record = try engine.prepare(engine.preview(id: "sublime-zed-workstyle-v1", home: home),
                                        approved: true, home: home, applicationSupport: support)
        let backup = try XCTUnwrap(record.settingsReceipt?.backupPath)
        try fm.removeItem(at: backup)
        try fm.removeItem(at: destination)
        XCTAssertThrowsError(try engine.rollback(record, home: home, applicationSupport: support))
        XCTAssertEqual(try StudioFreeTwinStore().load(in: support).count, 1)
        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent(".config/zed/snippets/snippets.json").path))
    }

}
