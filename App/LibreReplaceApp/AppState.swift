import Combine
import Foundation
import LibreReplaceCore

/// UI-only continuation for a user testing a built-in capability. Nothing here
/// is persisted or treated as proof of a successful replacement.
struct StudioToolContinuation: Identifiable {
    let id = UUID()
    let plan: StudioComposedPlan
    let sourceApp: PaidApplication
}

@MainActor
final class AppState: ObservableObject {
    enum BillingPeriod: String, CaseIterable, Identifiable {
        case monthly = "Monthly"
        case annually = "Annually"
        var id: String { rawValue }
    }

    @Published private(set) var catalog: Catalog?
    @Published private(set) var installed: [InstalledApplication] = []
    @Published private(set) var recommendations: [AppRecommendation] = []
    @Published private(set) var unsupported: [InstalledApplication] = []
    @Published private(set) var isScanning = false
    @Published var errorMessage: String?
    // Navigation requests are UI-only; source files and user data remain untouched.
    @Published var requestedExploreQuery = ""
    @Published var requestedComposerAppID = "cleanshot-x"
    @Published var toolContinuation: StudioToolContinuation?
    @Published var requestedLocalToolMode: StudioWorkflowLabView.LabMode?

    func beginLocalToolTrial(plan: StudioComposedPlan, sourceApp: PaidApplication,
                             mode: StudioWorkflowLabView.LabMode) {
        toolContinuation = StudioToolContinuation(plan: plan, sourceApp: sourceApp)
        requestedLocalToolMode = mode
    }

    @Published private(set) var annualCostText: [String: String] = [:]
    @Published private(set) var billingPeriod: [String: BillingPeriod] = [:]
    @Published private(set) var confirmedRecurringIDs = Set<String>()
    @Published private(set) var selectedSwitchIDs = Set<String>()

    // Explicit per-app choice: "best" in the catalog is NOT a user-selected plan.
    @Published private(set) var selectedAlternativeIDs: [String: String] = [:]
    @Published private(set) var replacementAnnualCostText: [String: String] = [:]
    @Published private(set) var confirmedReplacementCostIDs = Set<String>()
    @Published private(set) var confirmedCancellationIDs = Set<String>()

    /// Saved locally so comparisons and choices don't disappear on restart.
    @Published private(set) var requiredFeaturesByApp: [String: Set<String>] = [:]

    init() {
        let settings = UserDefaults.standard
        if let data = settings.data(forKey: "LibreReplace.studio.requirements.v1"),
           let previous = try? JSONDecoder().decode([String: Set<String>].self, from: data) {
            requiredFeaturesByApp = previous
        }
        if let data = settings.data(forKey: "LibreReplace.studio.alternatives.v1"),
           let previous = try? JSONDecoder().decode([String: String].self, from: data) {
            selectedAlternativeIDs = previous
        }
    }

    private func saveChoices() {
        if let data = try? JSONEncoder().encode(requiredFeaturesByApp) {
            UserDefaults.standard.set(data, forKey: "LibreReplace.studio.requirements.v1")
        }
        if let data = try? JSONEncoder().encode(selectedAlternativeIDs) {
            UserDefaults.standard.set(data, forKey: "LibreReplace.studio.alternatives.v1")
        }
    }

    func requiredFeatureIDs(for app: PaidApplication) -> Set<String> {
        requiredFeaturesByApp[app.id] ?? Set(app.capabilities.filter(\.critical).map(\.id))
    }
    /// Restore a saved plan's exact must-haves when the user chooses to edit it.
    /// Refuse stale or foreign IDs rather than silently dropping requirements.
    @discardableResult
    func restoreRequiredFeatures(_ ids: Set<String>, for app: PaidApplication) -> Bool {
        guard ids.isSubset(of: Set(app.capabilities.map(\.id))) else { return false }
        requiredFeaturesByApp[app.id] = ids
        saveChoices()
        confirmedCancellationIDs.remove(app.id)
        selectedSwitchIDs.remove(app.id)
        refreshRecommendations()
        return true
    }
    func isRequired(_ capabilityID: String, for app: PaidApplication) -> Bool {
        requiredFeatureIDs(for: app).contains(capabilityID)
    }
    func setRequired(_ capabilityID: String, for app: PaidApplication, enabled: Bool) {
        guard app.capabilities.contains(where: { $0.id == capabilityID }) else { return }
        var ids = requiredFeatureIDs(for: app)
        if enabled { ids.insert(capabilityID) } else { ids.remove(capabilityID) }
        guard ids != requiredFeatureIDs(for: app) else { return }
        requiredFeaturesByApp[app.id] = ids
        saveChoices()
        // Changing what must work invalidates the user's earlier cancellation decision.
        confirmedCancellationIDs.remove(app.id)
        selectedSwitchIDs.remove(app.id)
        refreshRecommendations()
    }

    func chosenAssessment(for app: PaidApplication) -> ExploreAssessment? {
        guard let chosen = selectedAlternativeIDs[app.id] else { return nil }
        return ExploreDecision.assess(app, requiredFeatureIDs: requiredFeatureIDs(for: app))
            .first { $0.ranked.alternative.id == chosen }
    }

    func chooseAlternative(_ alternativeID: String, for app: PaidApplication) {
        guard alternativeID.isEmpty || app.alternatives.contains(where: { $0.id == alternativeID }) else { return }
        guard selectedAlternativeIDs[app.id] != alternativeID else { return }
        if alternativeID.isEmpty { selectedAlternativeIDs.removeValue(forKey: app.id) }
        else { selectedAlternativeIDs[app.id] = alternativeID }
        saveChoices()
        // A curated free desktop edition needs no annual-price form.
        // Hosted, freemium and conditional-use options remain unpriced
        // and are not counted as savings by default.
        if let alternative = app.alternatives.first(where: { $0.id == alternativeID }),
           ReplacementCostPolicy.isFreeStandalone(alternative) {
            replacementAnnualCostText[app.id] = "0"
            confirmedReplacementCostIDs.insert(app.id)
        } else {
            replacementAnnualCostText.removeValue(forKey: app.id)
            confirmedReplacementCostIDs.remove(app.id)
        }
        confirmedCancellationIDs.remove(app.id)
        selectedSwitchIDs.remove(app.id)
    }

    func setOriginalCost(_ value: String, appID: String) {
        guard annualCostText[appID] != value else { return }
        annualCostText[appID] = value
        confirmedRecurringIDs.remove(appID)
        selectedSwitchIDs.remove(appID)
    }
    func setBillingPeriod(_ period: BillingPeriod, appID: String) {
        guard billingPeriod[appID, default: .annually] != period else { return }
        billingPeriod[appID] = period
        confirmedRecurringIDs.remove(appID)
        selectedSwitchIDs.remove(appID)
    }
    func setRecurringConfirmed(_ confirmed: Bool, appID: String) {
        if confirmed { confirmedRecurringIDs.insert(appID) }
        else { confirmedRecurringIDs.remove(appID); selectedSwitchIDs.remove(appID) }
    }
    func setReplacementAnnualCost(_ value: String, appID: String) {
        guard replacementAnnualCostText[appID] != value else { return }
        replacementAnnualCostText[appID] = value
        confirmedReplacementCostIDs.remove(appID)
        selectedSwitchIDs.remove(appID)
    }
    func setReplacementCostConfirmed(_ confirmed: Bool, appID: String) {
        if confirmed { confirmedReplacementCostIDs.insert(appID) }
        else { confirmedReplacementCostIDs.remove(appID); selectedSwitchIDs.remove(appID) }
    }
    func setCanCancel(_ confirmed: Bool, for app: PaidApplication) {
        if confirmed {
            confirmedCancellationIDs.insert(app.id)
            // The user checked that they could cancel; no second opt-in
            // toggle is necessary for the explicitly selected switch.
            if canIncludeInEstimate(for: app) { selectedSwitchIDs.insert(app.id) }
        } else {
            confirmedCancellationIDs.remove(app.id)
            selectedSwitchIDs.remove(app.id)
        }
    }
    func setIncludedInEstimate(_ included: Bool, app: PaidApplication) {
        if included && canIncludeInEstimate(for: app) { selectedSwitchIDs.insert(app.id) }
        else { selectedSwitchIDs.remove(app.id) }
    }

    private static func positiveOrZeroAmount(_ raw: String) -> Decimal? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
        // Foundation's Decimal(string:) accepts partial strings such as "12abc"
        // or "12,500" as 12. Reject malformed money instead of silently
        // producing an understated or overstated planning estimate.
        guard value.range(of: #"^[0-9]{1,9}(\.[0-9]{1,2})?$"#,
                          options: .regularExpression) != nil,
              let number = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")),
              number >= 0 else { return nil }
        return number
    }
    var annualCostOverrides: [String: Decimal] {
        annualCostText.reduce(into: [:]) { result, pair in
            guard let amount = Self.positiveOrZeroAmount(pair.value) else { return }
            result[pair.key] = billingPeriod[pair.key, default: .annually] == .monthly ? amount * 12 : amount
        }
    }
    var replacementAnnualCosts: [String: Decimal] {
        replacementAnnualCostText.reduce(into: [:]) { result, pair in
            if let amount = Self.positiveOrZeroAmount(pair.value) { result[pair.key] = amount }
        }
    }
    func canIncludeInEstimate(for app: PaidApplication) -> Bool {
        guard app.pricing.model != .oneTime, app.pricing.model != .paidUpgrade,
              let original = annualCostOverrides[app.id], original > 0,
              replacementAnnualCosts[app.id] != nil,
              confirmedRecurringIDs.contains(app.id),
              confirmedReplacementCostIDs.contains(app.id),
              confirmedCancellationIDs.contains(app.id),
              chosenAssessment(for: app)?.outcome == .strong
        else { return false }
        return true
    }

    private func refreshRecommendations() {
        guard let catalog else { return }
        let matcher = AppMatcher()
        recommendations = matcher.match(installed: installed, catalog: catalog)
            .map { ReplacementRanker().recommendation(
                for: $0, requiredFeatureIDs: requiredFeatureIDs(for: $0.catalogApp)
            ) }
            .sorted { $0.match.catalogApp.name.localizedCaseInsensitiveCompare($1.match.catalogApp.name) == .orderedAscending }
        unsupported = matcher.unsupported(installed: installed, catalog: catalog)
    }

    private var hasStarted = false
    var summary: ReportSummary {
        ReportSummary(
            applicationsDetected: installed.count,
            recommendations: recommendations,
            annualCostOverrides: annualCostOverrides,
            selectedSwitchIDs: selectedSwitchIDs,
            confirmedRecurringIDs: confirmedRecurringIDs,
            requirementsByApp: requiredFeaturesByApp,
            selectedAlternativeIDs: selectedAlternativeIDs,
            replacementAnnualCosts: replacementAnnualCosts,
            confirmedReplacementCostIDs: confirmedReplacementCostIDs,
            confirmedCancellationIDs: confirmedCancellationIDs
        )
    }
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        do {
            try loadCatalog()
            await scan()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    func loadCatalog() throws {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json") else {
            throw CatalogError.unreadable
        }
        catalog = try CatalogLoader.load(from: url)
        if let catalog {
            // Stored catalog choices are untrusted across schema/version changes.
            let byID = Dictionary(uniqueKeysWithValues: catalog.apps.map { ($0.id, $0) })
            requiredFeaturesByApp = requiredFeaturesByApp.filter { id, values in
                guard let app = byID[id] else { return false }
                return values.isSubset(of: Set(app.capabilities.map(\.id)))
            }
            selectedAlternativeIDs = selectedAlternativeIDs.filter { id, altID in
                byID[id]?.alternatives.contains(where: { $0.id == altID }) == true
            }
            saveChoices()
        }
    }
    func scan() async {
        guard let catalog else { return }
        isScanning = true
        defer { isScanning = false }
        let apps = await Task.detached(priority: .userInitiated) {
            AppScanner().scan()
        }.value
        installed = apps
        refreshRecommendations()
    }
    func reportMarkdown(includeNames: Bool) -> String {
        ReportGenerator.markdown(summary: summary, includeApplicationNames: includeNames, recommendations: recommendations)
    }
}
