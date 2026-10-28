import Foundation

public struct AppMatcher: Sendable {
    public init() {}

    public func match(installed: [InstalledApplication], catalog: Catalog) -> [AppMatch] {
        var bundleIndex: [String: PaidApplication] = [:]
        for app in catalog.apps {
            for bundle in app.bundleIdentifiers {
                // Catalog validation rejects duplicates. Keeping the first entry here
                // makes the matcher robust even if a caller passes an unvalidated catalog.
                if bundleIndex[bundle.lowercased()] == nil { bundleIndex[bundle.lowercased()] = app }
            }
        }

        var matches: [AppMatch] = []
        for item in installed {
            if let bundle = item.bundleIdentifier?.lowercased(), let app = bundleIndex[bundle] {
                matches.append(AppMatch(installed: item, catalogApp: app, confidence: .bundleIdentifier))
                continue
            }
            let normalized = normalize(item.name)
            if let app = catalog.apps.first(where: { candidate in
                ([candidate.name] + candidate.nameAliases).contains(where: { normalize($0) == normalized })
            }) {
                matches.append(AppMatch(installed: item, catalogApp: app, confidence: .nameAlias))
            }
        }
        return matches
    }

    public func unsupported(installed: [InstalledApplication], catalog: Catalog) -> [InstalledApplication] {
        let matchedIDs = Set(match(installed: installed, catalog: catalog).map { $0.installed.id })
        return installed.filter { !matchedIDs.contains($0.id) }
    }

    private func normalize(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }
}
