import Foundation

/// A user's record of a real trial, not automatic proof of app parity.
/// No filenames, document contents, or telemetry are stored.
public struct StudioWorkflowTrial: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let planIdentity: String
    public let testedRequirementIDs: [String]
    public let testedAt: Date
    public let macOSMajor: Int
    /// Nil on older Patch 18 records. Multi-tool trials with nil must be retested.
    public let interoperabilityConfirmed: Bool?

    public init(id: UUID = UUID(), planIdentity: String, testedRequirementIDs: [String],
                testedAt: Date = Date(), macOSMajor: Int, interoperabilityConfirmed: Bool = false) {
        self.id = id
        self.planIdentity = planIdentity
        self.testedRequirementIDs = testedRequirementIDs
        self.testedAt = testedAt
        self.macOSMajor = macOSMajor
        self.interoperabilityConfirmed = interoperabilityConfirmed
    }
}

public enum StudioWorkflowTrialError: Error, LocalizedError {
    case incomplete, incompleteTrial, incompleteHandoff, unsafeStorage, invalidStorage, limitReached

    public var errorDescription: String? {
        switch self {
        case .incomplete: "The selected setup is not ready for a full trial. Review its missing capabilities first."
        case .incompleteTrial: "Test every required capability on this Mac before recording a successful trial."
        case .incompleteHandoff: "Test moving a real result between the chosen tools before recording this multi-tool trial."
        case .unsafeStorage: "The trial record location is redirected or unsafe. Nothing was changed."
        case .invalidStorage: "The saved trial records cannot be read safely. Their contents were preserved."
        case .limitReached: "The trial history has reached its limit. No records were overwritten."
        }
    }
}

/// Stores self-reported success only for an exact candidate composition and set
/// of requirements. A changed plan or a new macOS major version requires a new
/// test. An imported community recipe never creates a trial record.
public enum StudioWorkflowTrialStore {
    private struct Envelope: Codable {
        let schemaVersion: Int
        let trials: [StudioWorkflowTrial]
    }

    public static func identity(for plan: StudioComposedPlan) -> String {
        // Include implementation details, not just component IDs. Changing a
        // package, evidence claim or required minimum must invalidate an old trial.
        let components = plan.components.sorted { $0.id < $1.id }.map { item in
            let claims = item.capabilities.sorted { $0.capabilityID < $1.capabilityID }.map {
                "\($0.capabilityID):\($0.support.rawValue):\($0.evidence.rawValue)"
            }.joined(separator: "\u{1e}")
            return [item.id, item.name, item.kind.rawValue, String(item.minimumMacOSMajor),
                    item.installation.rawValue, item.packageToken ?? "", claims].joined(separator: "\u{1f}")
        }.joined(separator: "\u{1d}")
        let coverage = plan.coverage.map {
            "\($0.requirement.id)\u{1f}\($0.requirement.essential ? "required" : "optional")\u{1f}\($0.state.rawValue)"
        }.sorted().joined(separator: "\u{1e}")
        return components + "\u{1d}" + coverage
    }

    public static func essentialIDs(for plan: StudioComposedPlan) -> Set<String> {
        Set(plan.coverage.filter(\.requirement.essential).map(\.requirement.id))
    }

    private static func location(in applicationSupport: URL) -> URL {
        applicationSupport.appendingPathComponent("LibreReplace", isDirectory: true)
            .appendingPathComponent("Workflow Trials", isDirectory: true)
            .appendingPathComponent("state-v1.json")
    }

    private static func checkedLocation(in applicationSupport: URL, fm: FileManager) throws -> URL {
        let file = location(in: applicationSupport)
        var candidate = file
        // Resolve from destination to root. Refuse a symlink at any user-owned
        // path, including the final file; do not follow links when reading.
        while candidate.path != "/" {
            if let attrs = try? fm.attributesOfItem(atPath: candidate.path),
               attrs[.type] as? FileAttributeType == .typeSymbolicLink,
               candidate.path != "/var" && candidate.path != "/tmp" {
                throw StudioWorkflowTrialError.unsafeStorage
            }
            candidate = candidate.deletingLastPathComponent()
        }
        return file
    }

    public static func load(in applicationSupport: URL, fm: FileManager = .default) throws -> [StudioWorkflowTrial] {
        let file = try checkedLocation(in: applicationSupport, fm: fm)
        guard fm.fileExists(atPath: file.path) else { return [] }
        guard let data = fm.contents(atPath: file.path), data.count <= 512_000,
              let value = try? JSONDecoder().decode(Envelope.self, from: data),
              value.schemaVersion == 1, value.trials.count <= 100,
              Set(value.trials.map(\.id)).count == value.trials.count,
              Set(value.trials.map { $0.planIdentity + "\u{1c}" + String($0.macOSMajor) }).count == value.trials.count,
              value.trials.allSatisfy({ $0.macOSMajor >= 14 && !$0.planIdentity.isEmpty &&
                  $0.planIdentity.count <= 12_000 && !$0.testedRequirementIDs.isEmpty &&
                  $0.testedRequirementIDs.count <= 64 &&
                  Set($0.testedRequirementIDs).count == $0.testedRequirementIDs.count }) else {
            throw StudioWorkflowTrialError.invalidStorage
        }
        return value.trials
    }

    public static func matching(_ plan: StudioComposedPlan, macOSMajor: Int,
                                in applicationSupport: URL,
                                fm: FileManager = .default) throws -> StudioWorkflowTrial? {
        let ids = essentialIDs(for: plan)
        return try load(in: applicationSupport, fm: fm).first {
            $0.planIdentity == identity(for: plan) && $0.macOSMajor == macOSMajor &&
            Set($0.testedRequirementIDs) == ids &&
            (plan.components.count < 2 || $0.interoperabilityConfirmed == true)
        }
    }

    @discardableResult
    public static func recordSuccessfulTrial(for plan: StudioComposedPlan,
                                            testedRequirementIDs: Set<String>,
                                            macOSMajor: Int,
                                            interoperabilityConfirmed: Bool = false,
                                            in applicationSupport: URL,
                                            fm: FileManager = .default) throws -> StudioWorkflowTrial {
        guard plan.readiness == .eligibleForTrial else { throw StudioWorkflowTrialError.incomplete }
        let mustHaves = essentialIDs(for: plan)
        guard !mustHaves.isEmpty, mustHaves == testedRequirementIDs, macOSMajor >= 14 else {
            throw StudioWorkflowTrialError.incompleteTrial
        }
        guard plan.components.count < 2 || interoperabilityConfirmed else {
            throw StudioWorkflowTrialError.incompleteHandoff
        }
        var saved = try load(in: applicationSupport, fm: fm)
        let identity = identity(for: plan)
        saved.removeAll { $0.planIdentity == identity && $0.macOSMajor == macOSMajor }
        guard saved.count < 100 else { throw StudioWorkflowTrialError.limitReached }
        let record = StudioWorkflowTrial(planIdentity: identity,
                                         testedRequirementIDs: mustHaves.sorted(),
                                         macOSMajor: macOSMajor,
                                         interoperabilityConfirmed: interoperabilityConfirmed)
        saved.append(record)
        let destination = try checkedLocation(in: applicationSupport, fm: fm)
        try fm.createDirectory(at: destination.deletingLastPathComponent(),
                               withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        // Refuse a redirection created between initial read and directory setup.
        _ = try checkedLocation(in: applicationSupport, fm: fm)
        let bytes = try JSONEncoder().encode(Envelope(schemaVersion: 1, trials: saved))
        guard bytes.count <= 512_000 else { throw StudioWorkflowTrialError.limitReached }
        try bytes.write(to: destination, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        guard fm.contents(atPath: destination.path) == bytes else { throw StudioWorkflowTrialError.invalidStorage }
        return record
    }
}
