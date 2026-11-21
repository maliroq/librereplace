import Foundation

/// A saved intent, never a claim that the underlying application is installed
/// or the entire replacement workflow has been verified.
public struct StudioSavedSetup: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let paidAppID: String
    public let requiredFeatureIDs: Set<String>
    public let componentIDs: [String]
    public let requiresLocalOCR: Bool
    public let createdAt: Date
    public init(id: UUID = UUID(), paidAppID: String, requiredFeatureIDs: Set<String>,
                componentIDs: [String], requiresLocalOCR: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.paidAppID = paidAppID
        self.requiredFeatureIDs = requiredFeatureIDs
        self.componentIDs = componentIDs
        self.requiresLocalOCR = requiresLocalOCR
        self.createdAt = createdAt
    }
}

public enum StudioSavedSetupError: LocalizedError {
    case unsafeFile, invalidFile, noComponents, tooMany, unknownApplication
    public var errorDescription: String? {
        switch self {
        case .unsafeFile: "The saved setup library contains a symbolic link. No files were changed."
        case .invalidFile: "The saved setup library is damaged. Its existing contents were preserved."
        case .noComponents: "Choose at least one valid free component for this setup."
        case .tooMany: "The saved setup library is full. Remove an unused setup first."
        case .unknownApplication: "This paid application is no longer in the current catalog."
        }
    }
}

public enum StudioSavedSetupLibrary {
    private struct Envelope: Codable { let schemaVersion: Int; let items: [StudioSavedSetup] }
    private static func location(_ support: URL) -> URL {
        support.appendingPathComponent("LibreReplace/Saved Setups/state-v1.json")
    }
    private static func check(_ support: URL, fm: FileManager) throws -> URL {
        let path = location(support)
        let parent = path.deletingLastPathComponent()
        var current = parent
        while current.path != "/" {
            if let type = (try? fm.attributesOfItem(atPath: current.path)[.type]) as? FileAttributeType,
               type == .typeSymbolicLink, current.path != "/var", current.path != "/tmp" {
                throw StudioSavedSetupError.unsafeFile
            }
            current = current.deletingLastPathComponent()
        }
        if let type = (try? fm.attributesOfItem(atPath: path.path)[.type]) as? FileAttributeType,
           type == .typeSymbolicLink { throw StudioSavedSetupError.unsafeFile }
        return path
    }
    public static func load(in applicationSupport: URL, fm: FileManager = .default) throws -> [StudioSavedSetup] {
        let url = try check(applicationSupport, fm: fm)
        guard fm.fileExists(atPath: url.path) else { return [] }
        guard let bytes = fm.contents(atPath: url.path), bytes.count < 2_000_000,
              let payload = try? JSONDecoder().decode(Envelope.self, from: bytes),
              payload.schemaVersion == 1, payload.items.count <= 500,
              Set(payload.items.map(\.id)).count == payload.items.count else { throw StudioSavedSetupError.invalidFile }
        return payload.items
    }
    public static func add(_ item: StudioSavedSetup, in applicationSupport: URL,
                           fm: FileManager = .default) throws {
        guard !item.componentIDs.isEmpty, !item.requiredFeatureIDs.isEmpty,
              item.componentIDs.count <= 8 else { throw StudioSavedSetupError.noComponents }
        var items = try load(in: applicationSupport, fm: fm)
        // Repeated clicks on Save do not produce duplicate cards.
        if items.contains(where: { $0.paidAppID == item.paidAppID &&
            $0.componentIDs == item.componentIDs && $0.requiredFeatureIDs == item.requiredFeatureIDs &&
            $0.requiresLocalOCR == item.requiresLocalOCR }) { return }
        guard items.count < 500 else { throw StudioSavedSetupError.tooMany }
        items.append(item)
        try persist(items, to: applicationSupport, fm: fm)
    }
    public static func remove(id: UUID, in applicationSupport: URL, fm: FileManager = .default) throws {
        var items = try load(in: applicationSupport, fm: fm)
        items.removeAll { $0.id == id }
        try persist(items, to: applicationSupport, fm: fm)
    }
    /// Always recomposes using current catalog evidence, not stale serialized
    /// app objects. A changed or missing component invalidates the saved setup.
    public static func resolve(_ saved: StudioSavedSetup, app: PaidApplication, macOSMajor: Int,
                               now: Date = Date()) -> StudioComposedPlan? {
        guard saved.paidAppID == app.id,
              !saved.requiredFeatureIDs.isEmpty,
              saved.requiredFeatureIDs.isSubset(of: Set(app.capabilities.map(\.id))),
              !saved.componentIDs.isEmpty, saved.componentIDs.count <= 4,
              Set(saved.componentIDs).count == saved.componentIDs.count,
              (!saved.requiresLocalOCR || (app.id == "cleanshot-x" && saved.requiredFeatureIDs.contains("ocr")))
        else { return nil }
        // Review exactly the saved combination, even if a new automatic
        // shortlist would now omit it as redundant. Never swap its components.
        let wanted = Set(saved.componentIDs)
        let components = StudioCatalogComposer.components(for: app, now: now)
            .filter { wanted.contains($0.id) }
        guard components.count == saved.componentIDs.count else { return nil }
        let requirements = app.capabilities.map {
            StudioCapabilityRequirement($0.id, essential: saved.requiredFeatureIDs.contains($0.id))
        } + (saved.requiresLocalOCR ? [StudioCapabilityRequirement("local-image-ocr")] : [])
        return StudioFreeStackComposer.assessExact(components: components,
            request: StudioComposeRequest(requirements: requirements, macOSMajor: macOSMajor))
    }
    private static func persist(_ items: [StudioSavedSetup], to support: URL, fm: FileManager) throws {
        let url = try check(support, fm: fm)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let bytes = try JSONEncoder().encode(Envelope(schemaVersion: 1, items: items))
        try bytes.write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        guard fm.contents(atPath: url.path) == bytes else { throw StudioSavedSetupError.invalidFile }
    }
}
