import Foundation

/// Only reviewed composer components can produce an install action. Imported
/// community recipe JSON is never an execution source.
public struct StudioApprovedInstall: Codable, Sendable, Equatable, Identifiable {
    public let componentID: String
    public let name: String
    public let package: String
    public let kind: StudioInstallationKind
    public var id: String { componentID }
    public init(componentID: String, name: String, package: String, kind: StudioInstallationKind) {
        self.componentID = componentID
        self.name = name
        self.package = package
        self.kind = kind
    }
    public var arguments: [String] {
        kind == .homebrewCask ? ["install", "--cask", package] : ["install", package]
    }
    public var installedCheckArguments: [String] {
        kind == .homebrewCask ? ["list", "--cask", package] : ["list", "--formula", package]
    }
    public var displayCommand: String { "brew " + arguments.joined(separator: " ") }
}

/// Short-lived proof that the *exact* approved packages were checked on this Mac.
/// A changed component ID, package, or install kind requires a new check.
/// It is in-memory only, so reopening the app never reuses a stale preflight.
public struct StudioInstallPreflight: Sendable {
    private let reviewed: [String: StudioApprovedInstall]
    public let checkedAt: Date
    public static let lifetime: TimeInterval = 10 * 60

    public init?(items: [StudioApprovedInstall], checkedAt: Date = Date()) {
        guard !items.isEmpty, items.count <= 32, Set(items.map(\.id)).count == items.count,
              items.allSatisfy({
                  ($0.kind == .homebrewCask || $0.kind == .homebrewFormula) &&
                  StudioSafeRecipeLoader.isSupportedPackageToken($0.package)
              }) else { return nil }
        reviewed = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        self.checkedAt = checkedAt
    }

    public func permits(_ selection: [StudioApprovedInstall], now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(checkedAt)
        guard age >= 0, age <= Self.lifetime, !selection.isEmpty,
              Set(selection.map(\.id)).count == selection.count else { return false }
        return selection.allSatisfy { reviewed[$0.id] == $0 }
    }
}

public enum StudioInstallApprovalError: LocalizedError, Sendable {
    case incompletePlan, emptySelection, unknownComponent, unsafePackage
    public var errorDescription: String? {
        switch self {
        case .incompletePlan: "The setup is incomplete. Fix the missing requirements before installing."
        case .emptySelection: "Select at least one application to install."
        case .unknownComponent: "An installation was requested for a component outside this reviewed setup."
        case .unsafePackage: "An installation identifier failed the safety check."
        }
    }
}

public enum StudioInstallApproval {
    public static func proposals(for plan: StudioComposedPlan) -> [StudioApprovedInstall] {
        plan.components.compactMap { component in
            guard (component.installation == .homebrewCask || component.installation == .homebrewFormula),
                  StudioSafeRecipeLoader.isSupportedPackageToken(component.packageToken),
                  let token = component.packageToken else { return nil }
            return .init(componentID: component.id, name: component.name,
                         package: token, kind: component.installation)
        }
    }

    public static func approve(plan: StudioComposedPlan,
                               selectedIDs: Set<String>) throws -> [StudioApprovedInstall] {
        guard plan.readiness == .eligibleForTrial else { throw StudioInstallApprovalError.incompletePlan }
        guard !selectedIDs.isEmpty else { throw StudioInstallApprovalError.emptySelection }
        let all = proposals(for: plan)
        let allowed = Set(all.map(\.componentID))
        guard selectedIDs.isSubset(of: allowed) else { throw StudioInstallApprovalError.unknownComponent }
        // An invalid package in a selected component must not be silently skipped.
        for component in plan.components where selectedIDs.contains(component.id) {
            guard StudioSafeRecipeLoader.isSupportedPackageToken(component.packageToken) else {
                throw StudioInstallApprovalError.unsafePackage
            }
        }
        return all.filter { selectedIDs.contains($0.id) }
    }
}

public enum StudioInstallEventState: String, Codable, Sendable {
    case planned, alreadyInstalled, installing, installSucceeded, installVerified, verificationFailed, installFailed, skipped
}

public struct StudioInstallJournalEvent: Codable, Sendable, Equatable {
    public let componentID: String
    public let package: String
    public let state: StudioInstallEventState
    public let timestamp: Date
    public let message: String
    public init(componentID: String, package: String, state: StudioInstallEventState,
                timestamp: Date = Date(), message: String) {
        self.componentID = componentID
        self.package = package
        self.state = state
        self.timestamp = timestamp
        self.message = String(message.prefix(240))
    }
}

/// A local change ledger, not a rollback promise. It deliberately records no
/// command output, personal documents, or private credentials.
public struct StudioInstallJournal: Codable, Sendable {
    public let sessionID: UUID
    public let createdAt: Date
    public private(set) var events: [StudioInstallJournalEvent]
    public init(sessionID: UUID = UUID(), createdAt: Date = Date()) {
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.events = []
    }
    public mutating func append(_ event: StudioInstallJournalEvent) {
        events.append(event)
    }
}

public enum StudioInstallJournalStore {
    /// Fails closed if the expected local journal cannot be persisted.
    /// The selected path is in the user's Application Support directory.
    public static func save(_ journal: StudioInstallJournal, in applicationSupport: URL) throws -> URL {
        let directory = applicationSupport
            .appendingPathComponent("LibreReplace", isDirectory: true)
            .appendingPathComponent("Install History", isDirectory: true)
        let fm = FileManager.default
        let intermediate = applicationSupport.appendingPathComponent("LibreReplace", isDirectory: true)
        // Refuse redirection through a preexisting symlink in our owned path.
        for url in [intermediate, directory] {
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            if let attrs, attrs[.type] as? FileAttributeType == .typeSymbolicLink {
                throw StudioRecipeValidationIssue("Installation history path cannot be a symbolic link")
            }
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let destination = directory.appendingPathComponent(journal.sessionID.uuidString + ".json")
        if fm.fileExists(atPath: destination.path),
           let attrs = try? fm.attributesOfItem(atPath: destination.path),
           attrs[.type] as? FileAttributeType == .typeSymbolicLink {
            throw StudioRecipeValidationIssue("Installation history file cannot be a symbolic link")
        }
        let encoded = try JSONEncoder().encode(journal)
        try encoded.write(to: destination, options: .atomic)
        // Immediately read back to detect an unexpected serialization/write issue.
        guard try Data(contentsOf: destination) == encoded else { throw CocoaError(.fileWriteUnknown) }
        return destination
    }
}
