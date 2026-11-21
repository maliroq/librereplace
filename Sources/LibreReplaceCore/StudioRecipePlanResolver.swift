import Foundation

/// Reopen imported declarative recipes as current catalog candidates. A recipe
/// never installs software or certifies an end-to-end workflow.
public struct StudioResolvedRecipePlan: Sendable {
    public let sourceApp: PaidApplication
    public let plan: StudioComposedPlan
    public init(sourceApp: PaidApplication, plan: StudioComposedPlan) {
        self.sourceApp = sourceApp
        self.plan = plan
    }
}

public enum StudioRecipePlanResolver {
    public static func resolve(_ recipe: StudioReplacementRecipe, in catalog: Catalog,
                               macOSMajor: Int, now: Date = Date()) -> StudioResolvedRecipePlan? {
        guard macOSMajor >= 14, !recipe.componentIDs.isEmpty else { return nil }
        let selectedComponents = Set(recipe.componentIDs)
        let required = Set(recipe.requirements.filter(\.essential).map(\.id))
        guard !required.isEmpty else { return nil }
        var matches: [StudioResolvedRecipePlan] = []
        for app in catalog.apps {
            let availableIDs = Set(StudioCatalogComposer.components(for: app, now: now).map(\.id))
            guard selectedComponents.isSubset(of: availableIDs) else { continue }
            let known = Set(app.capabilities.map(\.id))
            let includesLocalOCR = recipe.requirements.contains {
                $0.id == "local-image-ocr" && $0.essential
            }
            let validIDs = known.union(app.id == "cleanshot-x" ? ["local-image-ocr"] : [])
            guard Set(recipe.requirements.map(\.id)).isSubset(of: validIDs),
                  !required.subtracting(["local-image-ocr"]).isEmpty else { continue }
            guard !includesLocalOCR || (app.id == "cleanshot-x" && required.contains("ocr")) else {
                continue
            }
            let components = StudioCatalogComposer.components(for: app, now: now)
                .filter { selectedComponents.contains($0.id) }
            let requirements = app.capabilities.map {
                StudioCapabilityRequirement($0.id, essential: required.contains($0.id))
            } + (includesLocalOCR ? [StudioCapabilityRequirement("local-image-ocr", essential: true)] : [])
            guard components.count == recipe.componentIDs.count,
                  let exact = StudioFreeStackComposer.assessExact(
                    components: components,
                    request: StudioComposeRequest(requirements: requirements, macOSMajor: macOSMajor)),
                  Set(exact.coverage.filter(\.requirement.essential).map(\.requirement.id)) == required
            else { continue }
            matches.append(StudioResolvedRecipePlan(sourceApp: app, plan: exact))
        }
        // Never guess which paid app a recipe describes.
        return matches.count == 1 ? matches[0] : nil
    }
}
