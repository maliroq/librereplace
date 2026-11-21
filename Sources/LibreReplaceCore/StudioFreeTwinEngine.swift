import Foundation

public struct StudioFreeTwinDefinition: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let sourceAppID: String
    public let targetAppID: String
    public let targetBundleID: String
    public let approvedOperations: [String]
    public let limitations: [String]
}

/// A typed, bundled operation allowlist. Community JSON cannot add an
/// executable operation or replace one of these IDs with a shell command.
public enum StudioFreeTwinRegistry {
    public static let supported: [StudioFreeTwinDefinition] = [
        .init(id: "sublime-zed-workstyle-v1", sourceAppID: "sublime-text",
              targetAppID: "zed", targetBundleID: "dev.zed.Zed",
              approvedOperations: ["sublime-preferences-to-zed-v1", "sublime-snippets-to-zed-v1"],
              limitations: [
                "Only selected editor preferences and compatible user snippets are transferred.",
                "Projects, plugins, custom keybindings, theme files and account data are not transferred."
              ])
    ]

    public static func definition(id: String) -> StudioFreeTwinDefinition? {
        supported.first { $0.id == id }
    }
}

public struct StudioFreeTwinPreview: Sendable {
    public let id: String
    public let settings: MigrationPlan?
    public let snippets: StudioSnippetPreview
    public var hasOperations: Bool { (settings?.changes.isEmpty == false) || snippets.needsChanges }
    public init(id: String, settings: MigrationPlan?, snippets: StudioSnippetPreview) {
        self.id = id; self.settings = settings; self.snippets = snippets
    }
}

public enum StudioFreeTwinEngineError: Error, LocalizedError {
    case notApproved, notRegistered, alreadyConfigured, noSupportedChanges
    case recoveryIncomplete(String)
    public var errorDescription: String? {
        switch self {
        case .notApproved: "The requested free setup was not approved. Nothing changed."
        case .notRegistered: "This free setup does not have a reviewed executor."
        case .alreadyConfigured: "This free setup already exists. Review or undo it before making changes."
        case .noSupportedChanges: "Nothing compatible needs to be transferred."
        case .recoveryIncomplete(let note): "Automatic recovery could not finish: \(note)"
        }
    }
}

public struct StudioFreeTwinEngine {
    public init() {}

    public func preview(id: String, home: URL, fileManager fm: FileManager = .default) throws -> StudioFreeTwinPreview {
        guard StudioFreeTwinRegistry.definition(id: id) != nil else { throw StudioFreeTwinEngineError.notRegistered }
        let adapter = SublimeToZedMigration()
        let settings = adapter.detect(home: home, fileManager: fm) ? try adapter.preview(home: home, fileManager: fm) : nil
        let snippets = try StudioSnippetBridge().preview(home: home, fileManager: fm)
        return .init(id: id, settings: settings, snippets: snippets)
    }

    public func prepare(_ preview: StudioFreeTwinPreview, approved: Bool,
                        home: URL, applicationSupport: URL,
                        fileManager fm: FileManager = .default) throws -> StudioFreeTwinRecord {
        guard approved else { throw StudioFreeTwinEngineError.notApproved }
        guard let definition = StudioFreeTwinRegistry.definition(id: preview.id) else { throw StudioFreeTwinEngineError.notRegistered }
        guard preview.hasOperations else { throw StudioFreeTwinEngineError.noSupportedChanges }
        let store = StudioFreeTwinStore()
        guard try store.load(in: applicationSupport, fileManager: fm).first(where: { $0.id == definition.id }) == nil else {
            throw StudioFreeTwinEngineError.alreadyConfigured
        }
        let backup = home.appendingPathComponent("Library/Application Support/LibreReplace/Backups", isDirectory: true)
        var settingsReceipt: MigrationReceipt?
        var snippetReceipt: StudioSnippetReceipt?
        do {
            if let settings = preview.settings, !settings.changes.isEmpty {
                settingsReceipt = try SublimeToZedMigration().apply(plan: settings, home: home, backupRoot: backup, fileManager: fm)
                // Fail closed if we cannot record the completed first stage.
                let partial = StudioFreeTwinRecord(id: definition.id, sourceAppID: definition.sourceAppID,
                    targetBundleID: definition.targetBundleID, state: .partiallyPrepared,
                    settingsReceipt: settingsReceipt, userVisibleLimitations: definition.limitations)
                try store.upsert(partial, in: applicationSupport, fileManager: fm)
            }
            if preview.snippets.needsChanges {
                snippetReceipt = try StudioSnippetBridge().apply(preview.snippets, home: home,
                    backupRoot: backup.appendingPathComponent("Zed Snippet Backups"), fileManager: fm)
            }
            let complete = StudioFreeTwinRecord(id: definition.id, sourceAppID: definition.sourceAppID,
                targetBundleID: definition.targetBundleID, state: .prepared,
                settingsReceipt: settingsReceipt, snippetsReceipt: snippetReceipt,
                userVisibleLimitations: definition.limitations)
            try store.upsert(complete, in: applicationSupport, fileManager: fm)
            return complete
        } catch {
            var problems: [String] = []
            if let receipt = snippetReceipt {
                do { try StudioSnippetBridge().rollback(receipt, home: home, fileManager: fm) }
                catch { problems.append("Snippets: \(error.localizedDescription)") }
            }
            if let receipt = settingsReceipt {
                do { try SublimeToZedMigration().rollback(receipt: receipt, home: home, fileManager: fm) }
                catch { problems.append("Settings: \(error.localizedDescription)") }
            }
            if problems.isEmpty {
                do { try store.remove(id: definition.id, in: applicationSupport, fileManager: fm) }
                catch { problems.append("Saved record: \(error.localizedDescription)") }
            }
            if problems.isEmpty { throw error }
            throw StudioFreeTwinEngineError.recoveryIncomplete(error.localizedDescription + "; " + problems.joined(separator: "; "))
        }
    }

    public func rollback(_ record: StudioFreeTwinRecord, home: URL, applicationSupport: URL,
                         fileManager fm: FileManager = .default) throws {
        guard StudioFreeTwinRegistry.definition(id: record.id) != nil else { throw StudioFreeTwinEngineError.notRegistered }
        var settingNeedsRollback = false
        if let settings = record.settingsReceipt {
            try PathSafety.requireNoSymlinkTraversal(settings.targetPath, allowedRoot: home, fileManager: fm)
            let current = fm.contents(atPath: settings.targetPath.path)
            let isApplied = current.map { settings.writtenFingerprint == StudioDataFingerprint.of($0) } == true
            let isOriginal: Bool
            if settings.targetExistedBeforeApply {
                if let backup = settings.backupPath,
                   let original = fm.contents(atPath: backup.path),
                   let current {
                    isOriginal = original == current
                } else {
                    isOriginal = false
                }
            } else {
                isOriginal = current == nil && !fm.fileExists(atPath: settings.targetPath.path)
            }
            guard isApplied || isOriginal else {
                throw StudioSnippetBridgeError.recoveryConflict(settings.targetPath.path)
            }
            settingNeedsRollback = isApplied
        }
        let bridge = StudioSnippetBridge()
        if let snippets = record.snippetsReceipt, !bridge.canSafelyRollback(snippets, home: home, fileManager: fm) {
            throw StudioSnippetBridgeError.recoveryConflict("Zed snippet files")
        }
        if let snippets = record.snippetsReceipt { try bridge.rollback(snippets, home: home, fileManager: fm) }
        if settingNeedsRollback, let settings = record.settingsReceipt {
            try SublimeToZedMigration().rollback(receipt: settings, home: home, fileManager: fm)
        }
        try StudioFreeTwinStore().remove(id: record.id, in: applicationSupport, fileManager: fm)
    }

    public func verifyLocalChanges(_ record: StudioFreeTwinRecord, home: URL,
                                   fileManager fm: FileManager = .default) -> [String] {
        var results: [String] = []
        if let settings = record.settingsReceipt {
            let matches = fm.contents(atPath: settings.targetPath.path).map {
                settings.writtenFingerprint == StudioDataFingerprint.of($0)
            } == true
            results.append(matches ? "Editor settings match the prepared version" : "Editor settings differ from the prepared version")
        }
        if let snippets = record.snippetsReceipt {
            results.append(StudioSnippetBridge().verify(snippets, home: home, fileManager: fm) ?
                "Imported snippets match the prepared version" : "Imported snippets have changed")
        }
        return results
    }
}
