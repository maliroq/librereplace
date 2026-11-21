import Foundation

/// Adapts the existing reviewed catalog to Studio's deterministic, non-executing
/// planning engine. No alternative is considered functionally verified here.
public enum StudioCatalogComposer {
    public static func components(for app: PaidApplication, now: Date = Date()) -> [StudioComponent] {
        var result: [StudioComponent] = app.alternatives.compactMap { alt in
            // A freeware or source-available application is not automatically FOSS.
            guard alt.licenseKind == .openSource else { return nil }
            let minimumMajor: Int
            if let minimum = alt.minimumMacOS {
                guard let parsed = Int(minimum.split(separator: ".").first ?? ""), parsed >= 10 else { return nil }
                minimumMajor = parsed
            } else {
                minimumMajor = 14  // Catalog does not state a higher minimum.
            }
            let fresh = EvidenceFreshness.isFresh(app: app, alternative: alt, now: now)
            let claims = app.capabilities.map { feature in
                let support: StudioFeatureSupport
                switch alt.support[feature.id] ?? .unknown {
                case .full: support = .full
                case .partial: support = .partial
                case .none: support = .none
                case .unknown: support = .unknown
                }
                return StudioCapabilityClaim(feature.id, support,
                    evidence: fresh && !alt.evidence.isEmpty ? .documented : .unverified)
            }
            let installation: StudioInstallationKind
            let packageToken: String?
            switch alt.install.kind {
            case .homebrewCask where StudioSafeRecipeLoader.isSupportedPackageToken(alt.install.value):
                installation = .homebrewCask
                packageToken = alt.install.value
            case .homebrewFormula where StudioSafeRecipeLoader.isSupportedPackageToken(alt.install.value):
                installation = .homebrewFormula
                packageToken = alt.install.value
            default:
                installation = .none
                packageToken = nil
            }
            return StudioComponent(id: "app.\(app.id).\(alt.id)", name: alt.name, kind: .openSourceApp,
                minimumMacOSMajor: minimumMajor, capabilities: claims,
                installation: installation, packageToken: packageToken)
        }
        // Explicit initial bridge scope: text extraction from user-selected
        // screenshots/images. This does NOT claim PDF OCR or live screen capture.
        if app.id == "cleanshot-x" && app.capabilities.contains(where: { $0.id == "ocr" }) {
            result.append(StudioComponent(
                id: "bridge.image-ocr", name: "LibreReplace Image OCR", kind: .builtInBridge,
                capabilities: [StudioCapabilityClaim("ocr", .full, evidence: .documented),
                    StudioCapabilityClaim("local-image-ocr", .full, evidence: .documented)]
            ))
        }
        // Acrobat's scanned-document OCR is a genuine gap that the existing
        // document bridge partially fills: it extracts text but does not create
        // a searchable PDF or replace Acrobat editing/redaction features.
        if app.id == "acrobat-pro" && app.capabilities.contains(where: { $0.id == "ocr" }) {
            result.append(StudioComponent(
                id: "bridge.document-text-ocr", name: "LibreReplace Document OCR", kind: .builtInBridge,
                capabilities: [StudioCapabilityClaim("ocr", .partial, evidence: .documented)]
            ))
        }
        return result
    }

    public static func compose(
        for app: PaidApplication,
        requiredFeatureIDs: Set<String>,
        macOSMajor: Int,
        now: Date = Date(),
        requireLocalOCR: Bool = false,
        limit: Int = 10
    ) -> [StudioComposedPlan] {
        let known = Set(app.capabilities.map(\.id))
        let required = requiredFeatureIDs.intersection(known)
        guard !required.isEmpty else { return [] }
        var requirements = app.capabilities.map { StudioCapabilityRequirement($0.id, essential: required.contains($0.id)) }
        if requireLocalOCR && app.id == "cleanshot-x" && required.contains("ocr") {
            requirements.append(StudioCapabilityRequirement("local-image-ocr"))
        }
        return StudioFreeStackComposer.compose(
            components: components(for: app, now: now),
            request: StudioComposeRequest(requirements: requirements, macOSMajor: macOSMajor),
            limit: limit
        )
    }
}
