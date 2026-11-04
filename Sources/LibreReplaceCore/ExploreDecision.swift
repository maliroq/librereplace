import Foundation

/// A workflow-specific decision. No installed application is required.
public enum ExploreOutcome: String, Sendable, Equatable {
    case strong
    case partial
    case keep
    case unknown

    // A known usable alternative must outrank a higher-scoring incompatible
    // one. Numeric coverage alone cannot decide which option is recommended.
    fileprivate var recommendationPriority: Int {
        switch self {
        case .strong: 3
        case .partial: 2
        case .unknown: 1
        case .keep: 0
        }
    }

    public var label: String {
        switch self {
        case .strong: "Strong"
        case .partial: "Partial"
        case .keep: "Keep"
        case .unknown: "Not enough evidence"
        }
    }
}

public struct ExploreAssessment: Sendable {
    public let ranked: RankedAlternative
    public let outcome: ExploreOutcome
    public let requirements: [Capability]
    public let incompleteRequired: [Capability]
    public let unknownRequired: [Capability]
    public let evidenceFresh: Bool
}

/// Shared scoring for the installed-app and manual-exploration entry points.
/// A fully verified overall score cannot override a missing required feature.
public enum ExploreDecision {
    public static func assess(
        _ app: PaidApplication,
        requiredFeatureIDs: Set<String>? = nil,
        now: Date = Date()
    ) -> [ExploreAssessment] {
        let ids = requiredFeatureIDs ?? Set(app.capabilities.filter(\.critical).map(\.id))
        let requirements = app.capabilities.filter { ids.contains($0.id) }
        let evaluatedCapabilities = requirements
        let totalWeight = evaluatedCapabilities.reduce(0.0) { $0 + $1.weight }

        return app.alternatives.map { alternative in
            let earned = evaluatedCapabilities.reduce(0.0) { sum, capability in
                sum + capability.weight * (alternative.support[capability.id] ?? .unknown).score
            }
            let coverage = totalWeight > 0 ? earned / totalWeight : 0
            let kept = app.capabilities.filter { alternative.support[$0.id] == .full }
            let partial = app.capabilities.filter { alternative.support[$0.id] == .partial }
            let missing = app.capabilities.filter {
                let value = alternative.support[$0.id] ?? .unknown
                return value == .none || value == .unknown
            }
            let incomplete = requirements.filter { alternative.support[$0.id] != .full }
            let unknown = requirements.filter { alternative.support[$0.id] == nil || alternative.support[$0.id] == .unknown }
            let missingRequired = requirements.filter { alternative.support[$0.id] == FeatureSupport.none }
            let partialRequired = requirements.filter { alternative.support[$0.id] == .partial }
            let fresh = EvidenceFreshness.isFresh(app: app, alternative: alternative, now: now)

            let outcome: ExploreOutcome
            if requirements.isEmpty || !unknown.isEmpty || !fresh {
                outcome = .unknown
            } else if !missingRequired.isEmpty || coverage < app.policy.partialThreshold {
                outcome = .keep
            } else if !partialRequired.isEmpty {
                outcome = .partial
            } else if coverage >= app.policy.strongThreshold {
                outcome = .strong
            } else {
                outcome = .partial
            }

            // Never prioritize a missing required feature behind a high weighted score.
            var score = coverage * 100
            switch outcome {
            case .strong: score += 12
            case .partial: break
            case .keep: score -= 40
            case .unknown: score -= 50
            }
            let ranked = RankedAlternative(
                alternative: alternative,
                coverage: coverage,
                score: score,
                missingCritical: incomplete,
                kept: kept,
                partial: partial,
                missing: missing
            )
            return ExploreAssessment(
                ranked: ranked,
                outcome: outcome,
                requirements: requirements,
                incompleteRequired: incomplete,
                unknownRequired: unknown,
                evidenceFresh: fresh
            )
        }.sorted {
            if $0.outcome.recommendationPriority != $1.outcome.recommendationPriority {
                return $0.outcome.recommendationPriority > $1.outcome.recommendationPriority
            }
            if $0.ranked.score != $1.ranked.score {
                return $0.ranked.score > $1.ranked.score
            }
            return $0.ranked.alternative.name < $1.ranked.alternative.name
        }
    }
}
