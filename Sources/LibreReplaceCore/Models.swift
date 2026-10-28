import Foundation

public struct Catalog: Codable, Sendable {
    public let schemaVersion: String
    public let generatedAt: String
    public let apps: [PaidApplication]

    public init(schemaVersion: String, generatedAt: String, apps: [PaidApplication]) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.apps = apps
    }
}

public struct PaidApplication: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let vendor: String
    public let bundleIdentifiers: [String]
    public let nameAliases: [String]
    public let pricing: Pricing
    public let capabilities: [Capability]
    public let alternatives: [Alternative]
    public let policy: RecommendationPolicy
    public let evidence: [Evidence]
    public let lastVerified: String
    public let notes: String?

    public init(
        id: String,
        name: String,
        vendor: String,
        bundleIdentifiers: [String],
        nameAliases: [String],
        pricing: Pricing,
        capabilities: [Capability],
        alternatives: [Alternative],
        policy: RecommendationPolicy,
        evidence: [Evidence],
        lastVerified: String,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.vendor = vendor
        self.bundleIdentifiers = bundleIdentifiers
        self.nameAliases = nameAliases
        self.pricing = pricing
        self.capabilities = capabilities
        self.alternatives = alternatives
        self.policy = policy
        self.evidence = evidence
        self.lastVerified = lastVerified
        self.notes = notes
    }
}

public struct Pricing: Codable, Hashable, Sendable {
    public enum Model: String, Codable, Sendable {
        case subscription
        case paidUpgrade
        case oneTime
        case freemium
        case commercial
        case unknown
    }

    public let model: Model
    public let recurringAnnualUSD: Decimal?
    public let oneTimeUSD: Decimal?
    public let note: String?
    public let sourceURL: String?

    public init(model: Model, recurringAnnualUSD: Decimal? = nil, oneTimeUSD: Decimal? = nil, note: String? = nil, sourceURL: String? = nil) {
        self.model = model
        self.recurringAnnualUSD = recurringAnnualUSD
        self.oneTimeUSD = oneTimeUSD
        self.note = note
        self.sourceURL = sourceURL
    }
}

public struct Capability: Codable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let weight: Double
    public let critical: Bool

    public init(id: String, label: String, weight: Double = 1.0, critical: Bool = false) {
        self.id = id
        self.label = label
        self.weight = weight
        self.critical = critical
    }
}

public enum FeatureSupport: String, Codable, Hashable, Sendable {
    case full
    case partial
    case none
    case unknown

    public var score: Double {
        switch self {
        case .full: 1.0
        case .partial: 0.5
        case .none, .unknown: 0.0
        }
    }
}

public enum AlternativeLicenseKind: String, Codable, Hashable, Sendable {
    case openSource
    case sourceAvailable
    case freeware
    case proprietaryFree
}

public struct Alternative: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let license: String
    public let licenseKind: AlternativeLicenseKind
    public let repositoryURL: String?
    public let homepageURL: String
    public let install: InstallMethod
    public let support: [String: FeatureSupport]
    public let limitations: [String]
    public let minimumMacOS: String?
    public let migrationAdapter: String?
    public let evidence: [Evidence]
    public let lastVerified: String

    public init(
        id: String,
        name: String,
        license: String,
        licenseKind: AlternativeLicenseKind,
        repositoryURL: String?,
        homepageURL: String,
        install: InstallMethod,
        support: [String: FeatureSupport],
        limitations: [String],
        minimumMacOS: String? = nil,
        migrationAdapter: String? = nil,
        evidence: [Evidence],
        lastVerified: String
    ) {
        self.id = id
        self.name = name
        self.license = license
        self.licenseKind = licenseKind
        self.repositoryURL = repositoryURL
        self.homepageURL = homepageURL
        self.install = install
        self.support = support
        self.limitations = limitations
        self.minimumMacOS = minimumMacOS
        self.migrationAdapter = migrationAdapter
        self.evidence = evidence
        self.lastVerified = lastVerified
    }
}

public struct InstallMethod: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case homebrewCask
        case homebrewFormula
        case githubRelease
        case macAppStore
        case officialDownload
    }

    public let kind: Kind
    public let value: String
    public let warning: String?

    public init(kind: Kind, value: String, warning: String? = nil) {
        self.kind = kind
        self.value = value
        self.warning = warning
    }
}

public struct RecommendationPolicy: Codable, Hashable, Sendable {
    public let strongThreshold: Double
    public let partialThreshold: Double
    public let requireCriticalCapabilities: Bool

    public init(strongThreshold: Double = 0.80, partialThreshold: Double = 0.50, requireCriticalCapabilities: Bool = true) {
        self.strongThreshold = strongThreshold
        self.partialThreshold = partialThreshold
        self.requireCriticalCapabilities = requireCriticalCapabilities
    }
}

public struct Evidence: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case demand
        case feature
        case license
        case pricing
        case installation
        case limitation
        case maintenance
    }

    public let kind: Kind
    public let title: String
    public let url: String
    public let lastVerified: String

    public init(kind: Kind, title: String, url: String, lastVerified: String) {
        self.kind = kind
        self.title = title
        self.url = url
        self.lastVerified = lastVerified
    }
}

public struct InstalledApplication: Codable, Hashable, Identifiable, Sendable {
    public var id: String { bundleIdentifier ?? path.path }
    public let name: String
    public let bundleIdentifier: String?
    public let version: String?
    public let path: URL

    public init(name: String, bundleIdentifier: String?, version: String?, path: URL) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.path = path
    }
}

public enum MatchConfidence: String, Codable, Sendable {
    case bundleIdentifier
    case nameAlias
}

public struct AppMatch: Hashable, Sendable {
    public let installed: InstalledApplication
    public let catalogApp: PaidApplication
    public let confidence: MatchConfidence

    public init(installed: InstalledApplication, catalogApp: PaidApplication, confidence: MatchConfidence) {
        self.installed = installed
        self.catalogApp = catalogApp
        self.confidence = confidence
    }
}

public enum RecommendationLevel: String, Codable, Sendable {
    case strong
    case partial
    case keep
}

public struct RankedAlternative: Hashable, Sendable {
    public let alternative: Alternative
    public let coverage: Double
    public let score: Double
    public let missingCritical: [Capability]
    public let kept: [Capability]
    public let partial: [Capability]
    public let missing: [Capability]

    public init(alternative: Alternative, coverage: Double, score: Double, missingCritical: [Capability], kept: [Capability], partial: [Capability], missing: [Capability]) {
        self.alternative = alternative
        self.coverage = coverage
        self.score = score
        self.missingCritical = missingCritical
        self.kept = kept
        self.partial = partial
        self.missing = missing
    }
}

public struct AppRecommendation: Hashable, Sendable {
    public let match: AppMatch
    public let level: RecommendationLevel
    public let rankedAlternatives: [RankedAlternative]

    public var bestAlternative: RankedAlternative? { rankedAlternatives.first }
}
