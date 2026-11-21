import Foundation

public struct StudioSwitchStep: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case review, installCask, installFormula, tryBridge, verifyManually
    }
    public let kind: Kind
    public let title: String
    public let detail: String
    public init(kind: Kind, title: String, detail: String) {
        self.kind = kind; self.title = title; self.detail = detail
    }
}

public struct StudioSwitchPreview: Sendable {
    public let steps: [StudioSwitchStep]
    public let blockers: [String]
    public let warnings: [String]
    public var hasAutomaticChanges: Bool { false }
    public var readyForUserReview: Bool { blockers.isEmpty }
}

/// Read-only preflight. It never invokes Homebrew or claims recovery that
/// the app cannot guarantee. Execution will be a separate, consented milestone.
public enum StudioSwitchPlanner {
    public static func preview(_ plan: StudioComposedPlan) -> StudioSwitchPreview {
        var blockers: [String] = []
        var warnings: [String] = []
        var steps: [StudioSwitchStep] = [.init(kind: .review,
            title: "Review proposed replacement", detail: "No changes have been made.")]
        if plan.readiness == .incomplete {
            blockers.append("One or more required capabilities lack full documented coverage.")
        }
        for item in plan.components {
            switch item.installation {
            case .homebrewCask, .homebrewFormula:
                guard StudioSafeRecipeLoader.isSupportedPackageToken(item.packageToken),
                      let token = item.packageToken else {
                    blockers.append("\(item.name): package identifier is not safe to use.")
                    continue
                }
                let kind: StudioSwitchStep.Kind = item.installation == .homebrewCask ? .installCask : .installFormula
                let command = item.installation == .homebrewCask ? "brew install --cask \(token)" : "brew install \(token)"
                steps.append(.init(kind: kind, title: "Optional installation: \(item.name)",
                                   detail: "Proposed command for review only: \(command)"))
            case .none:
                if item.kind == .builtInBridge {
                    steps.append(.init(kind: .tryBridge, title: "Try \(item.name) locally",
                                       detail: "Use Workflow Lab with a file you select; no installation required."))
                } else {
                    steps.append(.init(kind: .review, title: "Check \(item.name)",
                                       detail: "No approved automatic installer is available for this component."))
                    warnings.append("\(item.name) needs manual setup review.")
                }
            }
        }
        steps.append(.init(kind: .verifyManually, title: "Run a representative workflow",
                           detail: "Confirm results and limitations before switching. Installation alone is not verification."))
        if plan.components.count > 1 {
            warnings.append("Interoperability is untested; this is not a complete migration or a guaranteed rollback.")
        }
        warnings.append("The paid application, account, subscriptions and existing preferences remain untouched.")
        return StudioSwitchPreview(steps: steps, blockers: blockers, warnings: warnings)
    }
}
