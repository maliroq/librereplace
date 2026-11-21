import Foundation

/// A compact, privacy-minimal checklist to accompany a community recipe.
/// This is user-reported evidence, never a certificate of compatibility.
/// No user file paths, document contents, installation logs or credentials.
public enum StudioCommunityReviewNotes {
    public static func render(plan: StudioComposedPlan, trial: StudioWorkflowTrial,
                              sourceAppName: String) throws -> String {
        let required = StudioWorkflowTrialStore.essentialIDs(for: plan)
        guard !sourceAppName.isEmpty, sourceAppName.count <= 100,
              trial.planIdentity == StudioWorkflowTrialStore.identity(for: plan),
              Set(trial.testedRequirementIDs) == required,
              plan.readiness == .eligibleForTrial, trial.macOSMajor >= 14,
              (plan.components.count < 2 || trial.interoperabilityConfirmed == true) else {
            throw StudioRecipeValidationIssue("The saved trial does not match this setup. Retest before exporting review notes.")
        }
        // Strip Markdown line breaks and formatting from external catalog labels.
        func plain(_ input: String) -> String {
            input.replacingOccurrences(of: "[\\r\\n\\t\\`\\[\\]#*]", with: " ",
                                       options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let date = ISO8601DateFormatter().string(from: trial.testedAt)
        var lines = [
            "# LibreReplace community review notes — user-reported trial",
            "",
            "Replaced workflow: \(plain(sourceAppName))",
            "Tested on: macOS \(trial.macOSMajor) (major version), \(date)",
            "",
            "## Free tools used"
        ]
        for component in plan.components.sorted(by: { $0.name < $1.name }) {
            lines.append("- \(plain(component.name))")
        }
        lines.append(contentsOf: ["", "## Required tasks the user reported testing"])
        for capability in plan.coverage.filter(\.requirement.essential).sorted(by: { $0.requirement.id < $1.requirement.id }) {
            lines.append("- \(plain(capability.requirement.id)): user marked successful")
        }
        lines.append(contentsOf: [
            "",
            "Multi-tool file/result handoff personally tested: \(plan.components.count < 2 ? "Not applicable" : "Yes (user-reported)")",
            "",
            "## Reviewer follow-up",
            "- Reproduce these tasks on a fresh Mac before publishing any compatibility claim.",
            "- Verify installed tool versions, file handoffs, unsupported cases and recovery.",
            "- Record remaining manual steps and limitations in the GitHub submission.",
            "- Attach the separately exported JSON recipe. This note alone cannot install or verify anything.",
            "",
            "This is a user's checklist, not independent verification or a promise of full replacement."
        ])
        return lines.joined(separator: "\n") + "\n"
    }
}
