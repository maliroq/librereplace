import Foundation

/// The installed-app workflow uses the same assessment as manual exploration.
public struct ReplacementRanker: Sendable {
    public init() {}
    public func recommendation(for match: AppMatch, requiredFeatureIDs: Set<String>? = nil, now: Date = Date()) -> AppRecommendation {
        let assessments = ExploreDecision.assess(match.catalogApp, requiredFeatureIDs: requiredFeatureIDs, now: now)
        let best = assessments.first?.outcome
        let level: RecommendationLevel
        switch best {
        case .strong: level = .strong
        case .partial: level = .partial
        case .keep: level = .keep
        case .unknown: level = .keep // Avoid counting unknown evidence as a supported switch.
        case nil: level = .keep
        }
        return AppRecommendation(match: match, level: level, rankedAlternatives: assessments.map(\.ranked))
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
