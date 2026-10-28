import Foundation

public enum CatalogError: Error, LocalizedError, Equatable {
    case unreadable
    case invalidJSON(String)
    case validation([String])

    public var errorDescription: String? {
        switch self {
        case .unreadable: return "Catalog could not be read."
        case .invalidJSON(let detail): return "Catalog JSON is invalid: \(detail)"
        case .validation(let errors): return "Catalog validation failed: \(errors.joined(separator: "; "))"
        }
    }
}

public enum CatalogLoader {
    public static func load(from data: Data, validate: Bool = true) throws -> Catalog {
        let decoder = JSONDecoder()
        let catalog: Catalog
        do {
            catalog = try decoder.decode(Catalog.self, from: data)
        } catch {
            throw CatalogError.invalidJSON(error.localizedDescription)
        }

        if validate {
            let errors = CatalogValidator.validate(catalog)
            if !errors.isEmpty { throw CatalogError.validation(errors) }
        }
        return catalog
    }

    public static func load(from url: URL, validate: Bool = true) throws -> Catalog {
        guard let data = try? Data(contentsOf: url) else { throw CatalogError.unreadable }
        return try load(from: data, validate: validate)
    }
}

public enum CatalogValidator {
    public static func validate(_ catalog: Catalog, now: Date = Date()) -> [String] {
        var errors: [String] = []
        if catalog.schemaVersion != "1.0" { errors.append("unsupported schemaVersion: \(catalog.schemaVersion)") }
        if let generatedAt = CatalogDate.parse(catalog.generatedAt) {
            if CatalogDate.isFutureDay(generatedAt, relativeTo: now) { errors.append("generatedAt cannot be in the future") }
        } else {
            errors.append("generatedAt must be a valid YYYY-MM-DD date")
        }
        if catalog.apps.count < 20 || catalog.apps.count > 40 {
            errors.append("launch catalog should contain 20-40 commercial apps; found \(catalog.apps.count)")
        }

        var appIDs = Set<String>()
        var bundleIDs = Set<String>()
        var nameMatchers: [String: String] = [:]
        for app in catalog.apps {
            if app.id.isEmpty || !appIDs.insert(app.id).inserted { errors.append("duplicate or empty app id: \(app.id)") }
            if app.name.isEmpty { errors.append("\(app.id): name is required") }
            if app.vendor.isEmpty { errors.append("\(app.id): vendor is required") }
            if app.bundleIdentifiers.isEmpty && app.nameAliases.isEmpty { errors.append("\(app.id): at least one matcher is required") }
            for matcher in [app.name] + app.nameAliases {
                let normalized = normalizeMatcher(matcher)
                if normalized.isEmpty {
                    errors.append("\(app.id): empty normalized name matcher")
                } else if let existing = nameMatchers[normalized], existing != app.id {
                    errors.append("ambiguous name matcher \(matcher): used by \(existing) and \(app.id)")
                } else {
                    nameMatchers[normalized] = app.id
                }
            }
            for bundle in app.bundleIdentifiers {
                if bundle.isEmpty { errors.append("\(app.id): empty bundle identifier") }
                if !bundleIDs.insert(bundle.lowercased()).inserted { errors.append("duplicate bundle identifier: \(bundle)") }
            }
            if app.capabilities.isEmpty { errors.append("\(app.id): capabilities cannot be empty") }
            if app.alternatives.isEmpty { errors.append("\(app.id): alternatives cannot be empty") }
            if app.evidence.isEmpty { errors.append("\(app.id): source-app evidence cannot be empty") }
            if !(0...1).contains(app.policy.strongThreshold) || !(0...1).contains(app.policy.partialThreshold) || app.policy.partialThreshold > app.policy.strongThreshold {
                errors.append("\(app.id): invalid recommendation thresholds")
            }
            var capabilityIDs = Set<String>()
            for cap in app.capabilities {
                if cap.id.isEmpty || !capabilityIDs.insert(cap.id).inserted { errors.append("\(app.id): duplicate or empty capability id: \(cap.id)") }
                if cap.label.isEmpty { errors.append("\(app.id): capability \(cap.id) label is required") }
                if !cap.weight.isFinite || cap.weight <= 0 { errors.append("\(app.id): capability \(cap.id) must have a finite positive weight") }
            }
            var alternativeIDs = Set<String>()
            for alt in app.alternatives {
                if alt.id.isEmpty || !alternativeIDs.insert(alt.id).inserted { errors.append("\(app.id): duplicate or empty alternative id: \(alt.id)") }
                if alt.name.isEmpty { errors.append("\(app.id): alternative name is required") }
                if alt.license.isEmpty { errors.append("\(app.id)/\(alt.id): license is required") }
                if alt.evidence.isEmpty { errors.append("\(app.id)/\(alt.id): alternative evidence cannot be empty") }
                if ExternalURLSafety.httpsURL(alt.homepageURL) == nil { errors.append("\(app.id)/\(alt.id): homepage URL must be a credential-free https URL") }
                if let repo = alt.repositoryURL, ExternalURLSafety.httpsURL(repo) == nil { errors.append("\(app.id)/\(alt.id): repository URL must be a credential-free https URL") }
                if let lastVerified = CatalogDate.parse(alt.lastVerified) {
                    if CatalogDate.isFutureDay(lastVerified, relativeTo: now) { errors.append("\(app.id)/\(alt.id): lastVerified cannot be in the future") }
                } else {
                    errors.append("\(app.id)/\(alt.id): invalid lastVerified date")
                }
                if (alt.install.kind == .homebrewCask || alt.install.kind == .homebrewFormula) && !InstallActionBuilder.isSafePackageToken(alt.install.value) {
                    errors.append("\(app.id)/\(alt.id): unsafe Homebrew package token")
                }
                if [.githubRelease, .officialDownload].contains(alt.install.kind), ExternalURLSafety.httpsURL(alt.install.value) == nil {
                    errors.append("\(app.id)/\(alt.id): install URL must be a credential-free https URL")
                }
                if alt.install.kind == .macAppStore, ExternalURLSafety.macAppStoreURL(alt.install.value) == nil && ExternalURLSafety.httpsURL(alt.install.value) == nil {
                    errors.append("\(app.id)/\(alt.id): Mac App Store install URL is invalid")
                }
                let unknownKeys = Set(alt.support.keys).subtracting(capabilityIDs)
                if !unknownKeys.isEmpty { errors.append("\(app.id)/\(alt.id): support references unknown capabilities \(unknownKeys.sorted())") }
                for capID in capabilityIDs where alt.support[capID] == nil { errors.append("\(app.id)/\(alt.id): missing support state for \(capID)") }
            }
            if let pricingURL = app.pricing.sourceURL, ExternalURLSafety.httpsURL(pricingURL) == nil { errors.append("\(app.id): pricing source URL must be a credential-free https URL") }
            for evidence in app.evidence + app.alternatives.flatMap(\.evidence) {
                if ExternalURLSafety.httpsURL(evidence.url) == nil { errors.append("\(app.id): evidence URL must be a credential-free https URL: \(evidence.url)") }
                if let evidenceDate = CatalogDate.parse(evidence.lastVerified) {
                    if CatalogDate.isFutureDay(evidenceDate, relativeTo: now) { errors.append("\(app.id): evidence date cannot be in the future: \(evidence.lastVerified)") }
                } else {
                    errors.append("\(app.id): invalid evidence date \(evidence.lastVerified)")
                }
            }
            if let lastVerified = CatalogDate.parse(app.lastVerified) {
                if CatalogDate.isFutureDay(lastVerified, relativeTo: now) { errors.append("\(app.id): lastVerified cannot be in the future") }
            } else {
                errors.append("\(app.id): invalid lastVerified date")
            }
        }
        return errors
    }

    private static func normalizeMatcher(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }
}


public enum CatalogDate {
    public static func isFutureDay(_ date: Date, relativeTo now: Date = Date()) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        guard let utc = TimeZone(secondsFromGMT: 0) else { return true }
        calendar.timeZone = utc
        return calendar.startOfDay(for: date) > calendar.startOfDay(for: now)
    }

    public static func parse(_ value: String) -> Date? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        guard let utc = TimeZone(secondsFromGMT: 0) else { return nil }
        calendar.timeZone = utc
        let components = DateComponents(timeZone: calendar.timeZone, year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else { return nil }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else { return nil }
        return date
    }
}
