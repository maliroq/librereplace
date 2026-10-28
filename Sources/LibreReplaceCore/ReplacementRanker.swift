import Foundation

public struct ReplacementRanker: Sendable {
    public init() {}

    public func recommendation(for match: AppMatch, now: Date = Date()) -> AppRecommendation {
        let app = match.catalogApp
        let ranked = app.alternatives.map { alt -> RankedAlternative in
            let totalWeight = app.capabilities.reduce(0) { $0 + $1.weight }
            let earned = app.capabilities.reduce(0.0) { partial, capability in
                partial + capability.weight * (alt.support[capability.id] ?? .unknown).score
            }
            let coverage = totalWeight == 0 ? 0 : earned / totalWeight
            let kept = app.capabilities.filter { alt.support[$0.id] == .full }
            let partial = app.capabilities.filter { alt.support[$0.id] == .partial }
            let missing = app.capabilities.filter { support in
                let state = alt.support[support.id] ?? .unknown
                return state == .none || state == .unknown
            }
            let missingCritical = missing.filter(\.critical)

            let evidenceFresh = EvidenceFreshness.isFresh(app: app, alternative: alt, now: now)
            var score = coverage * 100
            if alt.licenseKind == .openSource { score += 3 }
            if !evidenceFresh { score -= 10 }
            if !missingCritical.isEmpty { score -= 20 }
            return RankedAlternative(alternative: alt, coverage: coverage, score: score, missingCritical: missingCritical, kept: kept, partial: partial, missing: missing)
        }.sorted { lhs, rhs in
            if lhs.score == rhs.score { return lhs.alternative.name < rhs.alternative.name }
            return lhs.score > rhs.score
        }

        let level: RecommendationLevel
        if let best = ranked.first {
            let criticalOK = !app.policy.requireCriticalCapabilities || best.missingCritical.isEmpty
            let evidenceFresh = EvidenceFreshness.isFresh(app: app, alternative: best.alternative, now: now)
            if best.coverage >= app.policy.strongThreshold && criticalOK && evidenceFresh {
                level = .strong
            } else if best.coverage >= app.policy.partialThreshold {
                level = .partial
            } else {
                level = .keep
            }
        } else {
            level = .keep
        }
        return AppRecommendation(match: match, level: level, rankedAlternatives: ranked)
    }
}

public enum EvidenceFreshness {
    public static let staleAfterDays = 180

    public static func isStale(_ dateString: String, now: Date = Date()) -> Bool {
        guard let date = CatalogDate.parse(dateString) else { return true }
        if CatalogDate.isFutureDay(date, relativeTo: now) { return true }
        var calendar = Calendar(identifier: .gregorian)
        guard let utc = TimeZone(secondsFromGMT: 0) else { return true }
        calendar.timeZone = utc
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? Int.max
        return days > staleAfterDays
    }

    public static func isFresh(app: PaidApplication, alternative: Alternative, now: Date = Date()) -> Bool {
        let dates = [app.lastVerified, alternative.lastVerified] + (app.evidence + alternative.evidence).map(\.lastVerified)
        return dates.allSatisfy { !isStale($0, now: now) }
    }
}
