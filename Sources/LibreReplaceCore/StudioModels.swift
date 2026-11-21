import Foundation

/// Catalog claims are not equivalent to successfully executing an end-to-end workflow.
public enum StudioFeatureSupport: String, Codable, Sendable {
    case full, partial, none, unknown
}

public enum StudioEvidenceStatus: String, Codable, Sendable {
    case documented, unverified
}

public enum StudioComponentKind: String, Codable, Sendable {
    case openSourceApp, macOSNative, builtInBridge, externalEngine
}

public enum StudioInstallationKind: String, Codable, Sendable {
    case none, homebrewCask, homebrewFormula
}

public struct StudioCapabilityClaim: Codable, Sendable, Equatable {
    public let capabilityID: String
    public let support: StudioFeatureSupport
    public let evidence: StudioEvidenceStatus
    public init(_ id: String, _ support: StudioFeatureSupport, evidence: StudioEvidenceStatus) {
        self.capabilityID = id
        self.support = support
        self.evidence = evidence
    }
}

public struct StudioComponent: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let kind: StudioComponentKind
    public let minimumMacOSMajor: Int
    public let capabilities: [StudioCapabilityClaim]
    public let requires: [String]
    public let conflictsWith: [String]
    public let installation: StudioInstallationKind
    public let packageToken: String?

    public init(id: String, name: String, kind: StudioComponentKind, minimumMacOSMajor: Int = 14,
                capabilities: [StudioCapabilityClaim], requires: [String] = [], conflictsWith: [String] = [],
                installation: StudioInstallationKind = .none, packageToken: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.minimumMacOSMajor = minimumMacOSMajor
        self.capabilities = capabilities
        self.requires = requires
        self.conflictsWith = conflictsWith
        self.installation = installation
        self.packageToken = packageToken
    }
}

public struct StudioCapabilityRequirement: Codable, Sendable, Equatable {
    public let id: String
    public let essential: Bool
    public init(_ id: String, essential: Bool = true) {
        self.id = id
        self.essential = essential
    }
}

public struct StudioComposeRequest: Sendable {
    public let requirements: [StudioCapabilityRequirement]
    public let macOSMajor: Int
    public let installedComponentIDs: Set<String>
    public init(requirements: [StudioCapabilityRequirement], macOSMajor: Int, installedComponentIDs: Set<String> = []) {
        self.requirements = requirements
        self.macOSMajor = macOSMajor
        self.installedComponentIDs = installedComponentIDs
    }
}

public enum StudioCoverageState: String, Sendable {
    case supported, partial, unverified, missing
}

public struct StudioCapabilityCoverage: Sendable {
    public let requirement: StudioCapabilityRequirement
    public let state: StudioCoverageState
    public let supportingComponentIDs: [String]
}

public enum StudioPlanReadiness: String, Sendable {
    case eligibleForTrial, incomplete
}

public struct StudioComposedPlan: Sendable {
    public let components: [StudioComponent]
    public let coverage: [StudioCapabilityCoverage]
    public let readiness: StudioPlanReadiness
    public let warnings: [String]
    public let score: Int
    // Only an actual workflow execution/verifier can set a verified status.
    public var workflowVerified: Bool { false }
}
