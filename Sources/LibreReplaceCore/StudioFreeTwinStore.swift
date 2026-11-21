import Foundation

public enum StudioFreeTwinState: String, Codable, Sendable {
    case partiallyPrepared, prepared
}

/// Saved *local configuration* only. No note contents, document names,
/// snippets, transcripts, or inventory are persisted in this record.
public struct StudioFreeTwinRecord: Codable, Sendable {
    public let id: String
    public let sourceAppID: String
    public let targetBundleID: String
    public let createdAt: Date
    public let state: StudioFreeTwinState
    public let settingsReceipt: MigrationReceipt?
    public let snippetsReceipt: StudioSnippetReceipt?
    public let userVisibleLimitations: [String]

    public init(id: String, sourceAppID: String, targetBundleID: String,
                createdAt: Date = Date(), state: StudioFreeTwinState,
                settingsReceipt: MigrationReceipt? = nil, snippetsReceipt: StudioSnippetReceipt? = nil,
                userVisibleLimitations: [String] = []) {
        self.id = id; self.sourceAppID = sourceAppID; self.targetBundleID = targetBundleID
        self.createdAt = createdAt; self.state = state
        self.settingsReceipt = settingsReceipt; self.snippetsReceipt = snippetsReceipt
        self.userVisibleLimitations = userVisibleLimitations
    }
}

public enum StudioFreeTwinStoreError: Error, LocalizedError {
    case invalidData, unsafeLocation
    public var errorDescription: String? {
        switch self {
        case .invalidData: "Saved free setups could not be read. Existing information was not overwritten."
        case .unsafeLocation: "Free setup storage was redirected by a symbolic link. No changes were made."
        }
    }
}

public struct StudioFreeTwinStore {
    public init() {}
    private struct Envelope: Codable {
        var version: Int
        var items: [StudioFreeTwinRecord]
    }
    private func destination(_ root: URL) -> URL {
        root.appendingPathComponent("LibreReplace", isDirectory: true)
            .appendingPathComponent("Free Twins", isDirectory: true)
            .appendingPathComponent("state-v1.json")
    }
    private func validate(_ root: URL, fm: FileManager) throws -> URL {
        let dest = destination(root)
        let dirs = [dest.deletingLastPathComponent().deletingLastPathComponent(), dest.deletingLastPathComponent(), dest]
        for path in dirs {
            if (try? fm.attributesOfItem(atPath: path.path)[.type] as? FileAttributeType) == .typeSymbolicLink {
                throw StudioFreeTwinStoreError.unsafeLocation
            }
        }
        return dest
    }
    public func load(in applicationSupport: URL, fileManager fm: FileManager = .default) throws -> [StudioFreeTwinRecord] {
        let dest = try validate(applicationSupport, fm: fm)
        guard fm.fileExists(atPath: dest.path) else { return [] }
        guard let data = fm.contents(atPath: dest.path),
              let decoded = try? JSONDecoder().decode(Envelope.self, from: data),
              decoded.version == 1 else { throw StudioFreeTwinStoreError.invalidData }
        return decoded.items
    }
    public func upsert(_ item: StudioFreeTwinRecord, in applicationSupport: URL, fileManager fm: FileManager = .default) throws {
        var items = try load(in: applicationSupport, fileManager: fm)
        items.removeAll { $0.id == item.id }
        items.append(item)
        try save(items, in: applicationSupport, fm: fm)
    }
    public func remove(id: String, in applicationSupport: URL, fileManager fm: FileManager = .default) throws {
        var items = try load(in: applicationSupport, fileManager: fm)
        items.removeAll { $0.id == id }
        try save(items, in: applicationSupport, fm: fm)
    }
    private func save(_ items: [StudioFreeTwinRecord], in applicationSupport: URL, fm: FileManager) throws {
        let dest = try validate(applicationSupport, fm: fm)
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(Envelope(version: 1, items: items))
        try data.write(to: dest, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)
        guard fm.contents(atPath: dest.path) == data else { throw CocoaError(.fileWriteUnknown) }
    }
}
