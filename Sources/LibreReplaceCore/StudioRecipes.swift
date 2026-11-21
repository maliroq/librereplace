import Foundation

public enum StudioRecipeActionKind: String, Codable, Sendable {
    case installHomebrewCask, installHomebrewFormula, invokeBuiltInBridge, verifyCapability
}

public struct StudioRecipeAction: Codable, Sendable {
    public let kind: StudioRecipeActionKind
    public let targetID: String
    public init(kind: StudioRecipeActionKind, targetID: String) {
        self.kind = kind; self.targetID = targetID
    }
}

public struct StudioReplacementRecipe: Codable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let sourceWorkflow: String
    public let requirements: [StudioCapabilityRequirement]
    public let componentIDs: [String]
    public let actions: [StudioRecipeAction]
    public init(schemaVersion: Int = 1, id: String, sourceWorkflow: String,
                requirements: [StudioCapabilityRequirement], componentIDs: [String], actions: [StudioRecipeAction]) {
        self.schemaVersion = schemaVersion; self.id = id; self.sourceWorkflow = sourceWorkflow
        self.requirements = requirements; self.componentIDs = componentIDs; self.actions = actions
    }
}

public struct StudioRecipeValidationIssue: LocalizedError, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Loads untrusted data with a strict allowlist. Does not execute actions.
public enum StudioSafeRecipeLoader {
    private static func validID(_ s: String) -> Bool {
        s.range(of: "^[a-z][a-z0-9._-]{1,79}$", options: .regularExpression) != nil
    }
    private static func keys(_ value: Any, allowed: Set<String>, at: String) throws {
        guard let dict = value as? [String: Any] else { throw StudioRecipeValidationIssue("\(at): expected object") }
        let unknown = Set(dict.keys).subtracting(allowed)
        if let bad = unknown.sorted().first { throw StudioRecipeValidationIssue("\(at): unknown or unsafe field '\(bad)'") }
    }

    public static func decodeAndValidate(_ data: Data, catalog: [StudioComponent]) throws -> StudioReplacementRecipe {
        guard data.count <= 256 * 1024 else { throw StudioRecipeValidationIssue("Recipe exceeds size limit") }
        let json = try JSONSerialization.jsonObject(with: data)
        try keys(json, allowed: ["schemaVersion", "id", "sourceWorkflow", "requirements", "componentIDs", "actions"], at: "recipe")
        guard let root = json as? [String: Any] else { throw StudioRecipeValidationIssue("Invalid recipe") }
        for (index, item) in ((root["requirements"] as? [Any]) ?? []).enumerated() {
            try keys(item, allowed: ["id", "essential"], at: "requirements[\(index)]")
        }
        for (index, item) in ((root["actions"] as? [Any]) ?? []).enumerated() {
            try keys(item, allowed: ["kind", "targetID"], at: "actions[\(index)]")
        }
        let recipe: StudioReplacementRecipe
        do { recipe = try JSONDecoder().decode(StudioReplacementRecipe.self, from: data) }
        catch { throw StudioRecipeValidationIssue("Malformed or unsupported recipe data: \(error)") }
        guard recipe.schemaVersion == 1 else { throw StudioRecipeValidationIssue("Unsupported recipe schema version") }
        guard validID(recipe.id) else { throw StudioRecipeValidationIssue("Invalid recipe ID") }
        guard !recipe.requirements.isEmpty && recipe.requirements.count <= 64 else { throw StudioRecipeValidationIssue("Invalid requirement count") }
        guard !recipe.componentIDs.isEmpty && recipe.componentIDs.count <= 32 else { throw StudioRecipeValidationIssue("Invalid component count") }
        guard recipe.actions.count <= 128 else { throw StudioRecipeValidationIssue("Too many recipe actions") }
        guard recipe.sourceWorkflow.count <= 200 && !recipe.sourceWorkflow.isEmpty else { throw StudioRecipeValidationIssue("Invalid workflow description") }
        let requirementIDs = recipe.requirements.map(\.id)
        guard Set(requirementIDs).count == requirementIDs.count && requirementIDs.allSatisfy(validID) else {
            throw StudioRecipeValidationIssue("Invalid or duplicate capability IDs")
        }
        guard Set(recipe.componentIDs).count == recipe.componentIDs.count && recipe.componentIDs.allSatisfy(validID) else {
            throw StudioRecipeValidationIssue("Invalid or duplicate component IDs")
        }
        var indexed: [String: StudioComponent] = [:]
        for component in catalog {
            guard indexed[component.id] == nil else { throw StudioRecipeValidationIssue("Duplicate component ID in catalog") }
            indexed[component.id] = component
        }
        guard recipe.componentIDs.allSatisfy({ indexed[$0] != nil }) else { throw StudioRecipeValidationIssue("Unknown component ID") }
        for action in recipe.actions {
            guard validID(action.targetID), recipe.componentIDs.contains(action.targetID), let component = indexed[action.targetID] else {
                throw StudioRecipeValidationIssue("Action refers to an unapproved component")
            }
            switch action.kind {
            case .installHomebrewCask:
                guard component.installation == .homebrewCask, isSupportedPackageToken(component.packageToken) else { throw StudioRecipeValidationIssue("Invalid cask action") }
            case .installHomebrewFormula:
                guard component.installation == .homebrewFormula, isSupportedPackageToken(component.packageToken) else { throw StudioRecipeValidationIssue("Invalid formula action") }
            case .invokeBuiltInBridge:
                guard component.kind == .builtInBridge else { throw StudioRecipeValidationIssue("Bridge invocation targets non-bridge") }
            case .verifyCapability:
                // Typed verification is scoped to a known selected component.
                break
            }
        }
        return recipe
    }

    public static func isSupportedPackageToken(_ token: String?) -> Bool {
        guard let token else { return false }
        // This narrow allowlist is deliberate. Tap tokens with slashes require a separate reviewed contract.
        return token.range(of: "^[a-zA-Z0-9][a-zA-Z0-9+._-]{0,79}$", options: .regularExpression) != nil
    }
}

/// Creates a reviewable, versioned recipe draft from an actual Composer plan.
/// The generated file is data: saving or loading it cannot execute anything.
public enum StudioRecipeFactory {
    public static func makeDraft(for plan: StudioComposedPlan, workflow: String) throws -> (recipe: StudioReplacementRecipe, data: Data) {
        guard plan.readiness == .eligibleForTrial else {
            throw StudioRecipeValidationIssue("Cannot export an incomplete setup as a trial recipe")
        }
        let components = plan.components.sorted { $0.id < $1.id }
        let ids = components.map(\.id)
        let fullDescription = String(workflow.prefix(200))
        // Stable 64-bit FNV-1a avoids IDs that depend on system hashing seeds.
        var hash: UInt64 = 14_695_981_039_346_656_037
        // Two setups using the same free tools can have different essential
        // requirements. Their exported recipe IDs must not collide.
        let requirementsFingerprint = plan.coverage.map {
            $0.requirement.id + ":" + ($0.requirement.essential ? "required" : "optional")
        }.sorted().joined(separator: "|")
        for byte in (ids.joined(separator: "|") + "||" + requirementsFingerprint).utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        let id = "studio-" + String(hash, radix: 16)
        var actions: [StudioRecipeAction] = []
        for component in components {
            switch component.installation {
            case .homebrewCask: actions.append(.init(kind: .installHomebrewCask, targetID: component.id))
            case .homebrewFormula: actions.append(.init(kind: .installHomebrewFormula, targetID: component.id))
            case .none: if component.kind == .builtInBridge {
                actions.append(.init(kind: .invokeBuiltInBridge, targetID: component.id))
            }
            }
        }
        let recipe = StudioReplacementRecipe(id: id, sourceWorkflow: fullDescription,
            requirements: plan.coverage.map(\.requirement), componentIDs: ids, actions: actions)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(recipe)
        _ = try StudioSafeRecipeLoader.decodeAndValidate(data, catalog: components)
        return (recipe, data)
    }
}
