import Foundation

/// Pure, deterministic candidate composer. No installation or file mutations.
public enum StudioFreeStackComposer {
    /// Returns a shortlist of feasible candidate sets, not a claim that any workflow works.
    public static func compose(
        components: [StudioComponent], request: StudioComposeRequest, maxComponents: Int = 4, limit: Int = 20
    ) -> [StudioComposedPlan] {
        guard !request.requirements.isEmpty, maxComponents > 0, limit > 0 else { return [] }
        let requirementIDs = Set(request.requirements.map(\.id))
        let relevantIDs = Set(components.filter { component in
            component.capabilities.contains { requirementIDs.contains($0.capabilityID) && $0.support != .none }
        }.map(\.id))
        let dependencyIDs = Set(components.filter { relevantIDs.contains($0.id) }.flatMap(\.requires))
        let available = components
            .filter { $0.minimumMacOSMajor <= request.macOSMajor &&
                      (relevantIDs.contains($0.id) || dependencyIDs.contains($0.id)) }
            .sorted { $0.id < $1.id }
        // Prevent combinatorial blow-ups from a broad future catalog.
        guard available.count <= 24 else { return [] }
        var results: [StudioComposedPlan] = []
        var chosen: [StudioComponent] = []
        func visit(_ start: Int) {
            if !chosen.isEmpty, valid(chosen, installed: request.installedComponentIDs) {
                results.append(makePlan(chosen, requirements: request.requirements))
            }
            guard chosen.count < maxComponents else { return }
            for index in start..<available.count {
                chosen.append(available[index])
                visit(index + 1)
                chosen.removeLast()
            }
        }
        visit(0)
        let ranked = results.sorted { lhs, rhs in
            if lhs.readiness != rhs.readiness { return lhs.readiness == .eligibleForTrial }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            let leftIDs = lhs.components.map(\.id).joined(separator: ",")
            let rightIDs = rhs.components.map(\.id).joined(separator: ",")
            return leftIDs < rightIDs
        }
        // A larger setup that adds no capability coverage is not a better
        // recommendation. Suppress dominated supersets, including redundant
        // OCR bridges when a selected application already covers the requirement.
        let minimal = ranked.filter { candidate in
            !ranked.contains { smaller in
                smaller.components.count < candidate.components.count &&
                Set(smaller.components.map(\.id)).isSubset(of: Set(candidate.components.map(\.id))) &&
                zip(smaller.coverage, candidate.coverage).allSatisfy { a, b in
                    Self.coverageRank(a.state) >= Self.coverageRank(b.state)
                }
            }
        }
        return Array(minimal.prefix(limit))
    }

    /// Review an exact imported combination, including a user-chosen extra
    /// component that the automatic shortlist would otherwise suppress.
    /// Never executes the recipe or infers working interoperability.
    public static func assessExact(components: [StudioComponent],
                                   request: StudioComposeRequest) -> StudioComposedPlan? {
        guard !components.isEmpty, components.count <= 4,
              !request.requirements.isEmpty,
              Set(request.requirements.map(\.id)).count == request.requirements.count,
              components.allSatisfy({ $0.minimumMacOSMajor <= request.macOSMajor }),
              valid(components, installed: request.installedComponentIDs) else { return nil }
        return makePlan(components.sorted { $0.id < $1.id }, requirements: request.requirements)
    }

    private static func coverageRank(_ state: StudioCoverageState) -> Int {
        switch state {
        case .supported: 3
        case .partial: 2
        case .unverified: 1
        case .missing: 0
        }
    }

    private static func valid(_ chosen: [StudioComponent], installed: Set<String>) -> Bool {
        let ids = Set(chosen.map(\.id))
        guard ids.count == chosen.count else { return false }
        for component in chosen {
            if component.conflictsWith.contains(where: { ids.contains($0) }) { return false }
            if component.requires.contains(where: { !ids.contains($0) && !installed.contains($0) }) { return false }
        }
        // Conflicts are checked from both sides by visiting all chosen components.
        return true
    }

    private static func makePlan(_ components: [StudioComponent], requirements: [StudioCapabilityRequirement]) -> StudioComposedPlan {
        var coverage: [StudioCapabilityCoverage] = []
        for requirement in requirements {
            let claims: [(String, StudioCapabilityClaim)] = components.flatMap { component in
                component.capabilities.filter { $0.capabilityID == requirement.id }.map { (component.id, $0) }
            }
            let supported = claims.filter { $0.1.support == .full && $0.1.evidence == .documented }
            let partial = claims.filter { $0.1.support == .partial && $0.1.evidence == .documented }
            let unknown = claims.filter { $0.1.support == .unknown || $0.1.evidence == .unverified }
            let state: StudioCoverageState = !supported.isEmpty ? .supported :
                (!partial.isEmpty ? .partial : (!unknown.isEmpty ? .unverified : .missing))
            let providers: [String]
            switch state {
            case .supported: providers = supported.map(\.0)
            case .partial: providers = partial.map(\.0)
            case .unverified: providers = unknown.map(\.0)
            case .missing: providers = []
            }
            coverage.append(StudioCapabilityCoverage(requirement: requirement, state: state, supportingComponentIDs: providers.sorted()))
        }
        let ready = coverage.filter(\.requirement.essential).allSatisfy { $0.state == .supported }
        var warnings: [String] = []
        if components.count > 1 { warnings.append("Component interoperability has not been demonstrated; a real workflow trial is required.") }
        if coverage.contains(where: { $0.state == .unverified }) { warnings.append("Some capabilities have insufficient verified evidence.") }
        if !ready { warnings.append("At least one essential capability is not fully supported by documented evidence.") }
        let points = coverage.reduce(0) { sum, item in
            let weight = item.requirement.essential ? 100 : 20
            switch item.state {
            case .supported: return sum + weight
            case .partial: return sum + (weight / 4)
            case .unverified, .missing: return sum
            }
        }
        let score = points - components.count * 5
        return StudioComposedPlan(components: components, coverage: coverage,
                            readiness: ready ? .eligibleForTrial : .incomplete,
                            warnings: warnings, score: score)
    }
}
