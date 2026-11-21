import Foundation
import CoreFoundation

public struct SublimeToZedMigration: MigrationAdapter {
    public let id = "sublime-to-zed-settings-v1"
    public let displayName = "Sublime Text → Zed editor settings"

    private static let supportedTargetKeys: Set<String> = [
        "buffer_font_size",
        "buffer_font_family",
        "tab_size",
        "hard_tabs", "base_keymap", "soft_wrap", "show_whitespaces",
        "remove_trailing_whitespace_on_save", "preferred_line_length", "autosave"
    ]

    public init() {}

    public func detect(home: URL, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: sourceURL(home: home).path)
    }

    public func preview(home: URL, fileManager: FileManager = .default) throws -> MigrationPlan {
        let source = sourceURL(home: home)
        let target = targetURL(home: home)
        try validateMigrationPath(source, home: home, fileManager: fileManager)
        try validateMigrationPath(target, home: home, fileManager: fileManager)
        guard let data = fileManager.contents(atPath: source.path) else { throw MigrationError.sourceMissing(source.path) }
        guard let sourceObject = try? JSONSerialization.jsonObject(with: JSONC.stripComments(data)), let sourceDict = sourceObject as? [String: Any] else {
            throw MigrationError.invalidSource(source.path)
        }
        let targetDict = try readTargetDictionary(target, fileManager: fileManager)
        var changes: [MigrationChange] = []
        func append(_ sourceKey: String, _ targetKey: String, transform: (Any) -> Any? = { $0 }) {
            guard let raw = sourceDict[sourceKey], let value = transform(raw) else { return }
            let newValue = Self.stringValue(value)
            let oldValue = targetDict[targetKey].map(Self.stringValue)
            if newValue != oldValue { changes.append(MigrationChange(key: targetKey, fromValue: oldValue, toValue: newValue)) }
        }
        func appendBoolean(_ sourceKey: String, _ targetKey: String) {
            append(sourceKey, targetKey) { raw in raw as? Bool }
        }
        append("font_size", "buffer_font_size") { raw in
            guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
                  value.doubleValue.isFinite, value.doubleValue > 0 else { return nil }
            return value
        }
        append("font_face", "buffer_font_family") { raw in
            guard let font = raw as? String, !font.isEmpty else { return nil }
            return font
        }
        append("tab_size", "tab_size") { raw in
            guard let size = raw as? Int, size > 0 else { return nil }
            return size
        }
        append("translate_tabs_to_spaces", "hard_tabs") { raw in
            guard let b = raw as? Bool else { return nil }
            return !b
        }

        // Zed has a built-in Sublime keymap; do not assume arbitrary custom
        // Sublime key bindings or plugins can be translated.
        if targetDict["base_keymap"] == nil {
            changes.append(.init(key: "base_keymap", fromValue: nil, toValue: "SublimeText"))
        }
        append("draw_white_space", "show_whitespaces") { raw in
            guard let value = raw as? String, ["all", "selection", "none"].contains(value) else { return nil }
            return value
        }
        appendBoolean("trim_trailing_white_space_on_save", "remove_trailing_whitespace_on_save")
        append("word_wrap", "soft_wrap") { raw in
            guard let enabled = raw as? Bool else { return nil }
            return enabled ? "editor_width" : "none"
        }
        append("wrap_width", "preferred_line_length") { raw in
            guard let width = raw as? Int, width > 0 else { return nil }
            return width
        }
        append("save_on_focus_lost", "autosave") { raw in
            guard let enabled = raw as? Bool else { return nil }
            return enabled ? "on_focus_change" : "off"
        }

        return MigrationPlan(
            adapterID: id,
            sourcePath: source,
            targetPath: target,
            changes: changes,
            warnings: [
                "Selected editor preferences and Zed’s built-in Sublime keymap are mapped; not all Sublime behavior is equivalent.",
                "User snippets can be migrated separately when their scopes and placeholders are supported. Plugins, projects, custom keybindings, themes, recent files and document contents are not migrated.",
                "Existing Zed settings are backed up and preserved; only reviewed top-level keys are changed, including JSON comments and unrelated settings."
            ]
        )
    }

    public func apply(plan: MigrationPlan, home: URL, backupRoot: URL, fileManager: FileManager = .default) throws -> MigrationReceipt {
        let source = sourceURL(home: home)
        let target = targetURL(home: home)
        guard plan.adapterID == id,
              plan.sourcePath.standardizedFileURL == source.standardizedFileURL,
              plan.targetPath.standardizedFileURL == target.standardizedFileURL else {
            throw MigrationError.stalePlan(plan.targetPath.path)
        }

        try validateMigrationPath(source, home: home, fileManager: fileManager)
        try validateMigrationPath(target, home: home, fileManager: fileManager)
        try PathSafety.requireWithin(backupRoot, allowedRoots: [home])
        try PathSafety.requireNoSymlinkTraversal(backupRoot, allowedRoot: home, fileManager: fileManager)
        try validateChanges(plan.changes, target: target)
        // Prevent a stale or fabricated plan from applying unreviewed changes.
        let freshPlan = try preview(home: home, fileManager: fileManager)
        guard freshPlan.changes == plan.changes else { throw MigrationError.stalePlan(source.path) }

        let targetExisted = fileManager.fileExists(atPath: target.path)
        let targetBytesBeforeBackup: Data?
        if targetExisted {
            guard let data = fileManager.contents(atPath: target.path) else { throw MigrationError.invalidTarget(target.path) }
            targetBytesBeforeBackup = data
        } else {
            targetBytesBeforeBackup = nil
        }
        let dict = try parseTargetDictionary(targetBytesBeforeBackup, path: target.path)
        for change in plan.changes {
            let current = dict[change.key].map(Self.stringValue)
            guard current == change.fromValue else { throw MigrationError.stalePlan(target.path) }
        }

        let backup = try MigrationBackup.backup(target: target, backupRoot: backupRoot, fileManager: fileManager)
        if let expected = targetBytesBeforeBackup, let backup {
            guard (try? Data(contentsOf: target)) == expected,
                  (try? Data(contentsOf: backup)) == expected else {
                throw MigrationError.stalePlan(target.path)
            }
        }

        let values = Dictionary(uniqueKeysWithValues: plan.changes.map { ($0.key, Self.parseScalar($0.toValue)) })
        let proposedData = try StudioJSONCEditor.merge(targetBytesBeforeBackup, reviewedValues: values)
        let receipt = MigrationReceipt(
            adapterID: id,
            targetPath: target,
            backupPath: backup,
            targetExistedBeforeApply: targetExisted,
            writtenFingerprint: StudioDataFingerprint.of(proposedData)
        )

        do {
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PathSafety.requireNoSymlinkTraversal(target, allowedRoot: home, fileManager: fileManager)
            try proposedData.write(to: target, options: .atomic)

            let verified = try readTargetDictionary(target, fileManager: fileManager)
            for change in plan.changes {
                guard verified[change.key].map(Self.stringValue) == change.toValue else {
                    throw MigrationError.verificationFailed(target.path)
                }
            }
            return receipt
        } catch {
            do {
                try MigrationBackup.restore(receipt: receipt, fileManager: fileManager)
            } catch {
                throw MigrationError.rollbackFailed(target.path)
            }
            if let migrationError = error as? MigrationError { throw migrationError }
            throw MigrationError.applyFailed(target.path)
        }
    }

    public func rollback(receipt: MigrationReceipt, home: URL, fileManager: FileManager = .default) throws {
        let target = targetURL(home: home)
        guard receipt.adapterID == id, receipt.targetPath.standardizedFileURL == target.standardizedFileURL else {
            throw MigrationError.rollbackFailed(receipt.targetPath.path)
        }
        try validateMigrationPath(target, home: home, fileManager: fileManager)
        if let backup = receipt.backupPath {
            try PathSafety.requireWithin(backup, allowedRoots: [home])
            try PathSafety.requireNoSymlinkTraversal(backup, allowedRoot: home, fileManager: fileManager)
        }
        // A user may have edited Zed since our migration. Never silently
        // overwrite those later edits, even if the backup still exists.
        if let fingerprint = receipt.writtenFingerprint {
            guard let current = fileManager.contents(atPath: target.path),
                  StudioDataFingerprint.of(current) == fingerprint else {
                throw MigrationError.stalePlan(target.path)
            }
        } else {
            // Older receipts were not bound to a written state. Refuse unsafe rollback.
            throw MigrationError.stalePlan(target.path)
        }
        try MigrationBackup.restore(receipt: receipt, fileManager: fileManager)
    }

    private func sourceURL(home: URL) -> URL {
        let fm = FileManager.default
        let primary = home.appendingPathComponent("Library/Application Support/Sublime Text/Packages/User/Preferences.sublime-settings")
        if fm.fileExists(atPath: primary.path) { return primary }
        let legacy = home.appendingPathComponent("Library/Application Support/Sublime Text 3/Packages/User/Preferences.sublime-settings")
        return fm.fileExists(atPath: legacy.path) ? legacy : primary
    }

    private func targetURL(home: URL) -> URL {
        home.appendingPathComponent(".config/zed/settings.json")
    }

    private func validateMigrationPath(_ url: URL, home: URL, fileManager: FileManager) throws {
        try PathSafety.requireWithin(url, allowedRoots: [home])
        try PathSafety.requireNoSymlinkTraversal(url, allowedRoot: home, fileManager: fileManager)
    }

    private func validateChanges(_ changes: [MigrationChange], target: URL) throws {
        let keys = changes.map(\.key)
        guard Set(keys).count == keys.count, Set(keys).isSubset(of: Self.supportedTargetKeys) else {
            throw MigrationError.stalePlan(target.path)
        }
    }

    private func readTargetDictionary(_ url: URL, fileManager: FileManager) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        guard let data = fileManager.contents(atPath: url.path) else { throw MigrationError.invalidTarget(url.path) }
        return try parseTargetDictionary(data, path: url.path)
    }

    private func parseTargetDictionary(_ data: Data?, path: String) throws -> [String: Any] {
        guard let data else { return [:] }
        do { return try StudioJSONCEditor.topLevelDictionary(data) }
        catch { throw MigrationError.invalidTarget(path) }
    }

    private static func stringValue(_ value: Any) -> String {
        if let b = value as? Bool { return b ? "true" : "false" }
        if let n = value as? NSNumber { return n.stringValue }
        return String(describing: value)
    }

    private static func parseScalar(_ value: String) -> Any {
        if value == "true" { return true }
        if value == "false" { return false }
        if let i = Int(value) { return i }
        if let d = Double(value) { return d }
        return value
    }
}

public enum JSONC {
    public static func stripComments(_ data: Data) -> Data {
        guard let string = String(data: data, encoding: .utf8) else { return data }
        var output = ""
        var index = string.startIndex
        var inString = false
        var escaped = false
        while index < string.endIndex {
            let ch = string[index]
            let next = string.index(after: index)
            let nextChar: Character? = next < string.endIndex ? string[next] : nil
            if inString {
                output.append(ch)
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
                index = next
                continue
            }
            if ch == "\"" {
                inString = true
                output.append(ch)
                index = next
                continue
            }
            if ch == "/", nextChar == "/" {
                var cursor = string.index(after: next)
                while cursor < string.endIndex && string[cursor] != "\n" { cursor = string.index(after: cursor) }
                index = cursor
                continue
            }
            if ch == "/", nextChar == "*" {
                var cursor = string.index(after: next)
                while cursor < string.endIndex {
                    let after = string.index(after: cursor)
                    if string[cursor] == "*", after < string.endIndex, string[after] == "/" {
                        cursor = string.index(after: after)
                        break
                    }
                    cursor = after
                }
                index = cursor
                continue
            }
            output.append(ch)
            index = next
        }
        // Zed and Sublime both accept JSON with trailing commas. Keep every
        // original byte in source files; normalize only the in-memory copy
        // passed to strict JSONSerialization for validation.
        var normalized = Array(output.utf8)
        var quoted = false
        var jsonEscaped = false
        for index in normalized.indices {
            let byte = normalized[index]
            if quoted {
                if jsonEscaped { jsonEscaped = false }
                else if byte == 92 { jsonEscaped = true }
                else if byte == 34 { quoted = false }
                continue
            }
            if byte == 34 { quoted = true; continue }
            if byte == 44 {
                var next = index + 1
                while next < normalized.count && [UInt8(32), 9, 10, 13].contains(normalized[next]) {
                    next += 1
                }
                if next < normalized.count && (normalized[next] == 125 || normalized[next] == 93) {
                    normalized[index] = 32
                }
            }
        }
        return Data(normalized)
    }
}
