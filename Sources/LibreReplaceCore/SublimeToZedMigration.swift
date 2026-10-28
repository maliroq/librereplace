import Foundation

public struct SublimeToZedMigration: MigrationAdapter {
    public let id = "sublime-to-zed-settings-v1"
    public let displayName = "Sublime Text → Zed editor settings"

    private static let supportedTargetKeys: Set<String> = [
        "buffer_font_size",
        "buffer_font_family",
        "tab_size",
        "hard_tabs"
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
        append("font_size", "buffer_font_size")
        append("font_face", "buffer_font_family")
        append("tab_size", "tab_size")
        append("translate_tabs_to_spaces", "hard_tabs") { raw in
            guard let b = raw as? Bool else { return nil }
            return !b
        }

        return MigrationPlan(
            adapterID: id,
            sourcePath: source,
            targetPath: target,
            changes: changes,
            warnings: [
                "Only font family, font size, tab size, and hard-tabs preference are mapped.",
                "Plugins, projects, snippets, keybindings, themes, recent files, and file contents are not migrated.",
                "Existing Zed settings are backed up before modification. JSON comments in the target settings file may be lost because the file is re-serialized."
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

        let targetExisted = fileManager.fileExists(atPath: target.path)
        let targetBytesBeforeBackup: Data?
        if targetExisted {
            guard let data = fileManager.contents(atPath: target.path) else { throw MigrationError.invalidTarget(target.path) }
            targetBytesBeforeBackup = data
        } else {
            targetBytesBeforeBackup = nil
        }
        var dict = try parseTargetDictionary(targetBytesBeforeBackup, path: target.path)
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

        let receipt = MigrationReceipt(
            adapterID: id,
            targetPath: target,
            backupPath: backup,
            targetExistedBeforeApply: targetExisted
        )

        do {
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PathSafety.requireNoSymlinkTraversal(target, allowedRoot: home, fileManager: fileManager)
            for change in plan.changes {
                dict[change.key] = Self.parseScalar(change.toValue)
            }
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: target, options: .atomic)

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
        try MigrationBackup.restore(receipt: receipt, fileManager: fileManager)
    }

    private func sourceURL(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Sublime Text/Packages/User/Preferences.sublime-settings")
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
        guard let object = try? JSONSerialization.jsonObject(with: JSONC.stripComments(data)),
              let dict = object as? [String: Any] else {
            throw MigrationError.invalidTarget(path)
        }
        return dict
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
        return Data(output.utf8)
    }
}
