import SwiftUI
import LibreReplaceCore

struct RecommendationDetailView: View {
    @EnvironmentObject private var state: AppState
    let recommendation: AppRecommendation

    private var source: PaidApplication { recommendation.match.catalogApp }
    private var currentRecommendation: AppRecommendation {
        state.recommendations.first { $0.match.catalogApp.id == source.id } ?? recommendation
    }
    private var allowsRecurring: Bool {
        source.pricing.model != .oneTime && source.pricing.model != .paidUpgrade
    }
    private var evidenceAllowsSwitch: Bool {
        let outcome = ExploreDecision.assess(source, requiredFeatureIDs: state.requiredFeatureIDs(for: source)).first?.outcome
        return outcome == .strong || outcome == .partial
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if !evidenceAllowsSwitch {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Do not switch on the current evidence", systemImage: "exclamationmark.triangle")
                                .font(.title3.bold())
                            Text("Required capabilities are missing or available evidence is insufficient or stale. Review the comparison sources before making a migration decision.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                }
                essentialFeatures
                recurringCost
                ForEach(currentRecommendation.rankedAlternatives, id: \.alternative.id) { ranked in
                    AlternativeCard(sourceApp: source, ranked: ranked)
                }
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .navigationTitle(source.name)
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(source.name).font(.largeTitle.bold()).lineLimit(2).layoutPriority(1)
                Spacer(minLength: 12)
                Text(evidenceAllowsSwitch ? levelLabel : "KEEP / NEEDS EVIDENCE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(levelColor)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(levelColor.opacity(0.12), in: Capsule())
            }
            Text("Detected \(recommendation.match.installed.version.map { "version \($0)" } ?? "on this Mac") · matched by \(recommendation.match.confidence == .bundleIdentifier ? "bundle identifier" : "name")")
                .foregroundStyle(.secondary)
            if let note = source.pricing.note {
                Text(note).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
    private var essentialFeatures: some View {
        GroupBox("What do you need to keep?") {
            VStack(alignment: .leading, spacing: 9) {
                Text("Required features affect all recommendations, your switch plan and the Overview. The same choices are used in Explore.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(source.capabilities, id: \.id) { feature in
                    Toggle(feature.label, isOn: Binding(
                        get: { state.isRequired(feature.id, for: source) },
                        set: { state.setRequired(feature.id, for: source, enabled: $0) }
                    )).toggleStyle(.checkbox)
                }
                if state.requiredFeatureIDs(for: source).isEmpty {
                    Label("Choose at least one required feature.", systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
    /// A quick estimate rather than a pricing survey. Curated free desktop
    /// replacements automatically have $0 recurring software cost.
    /// Cloud/paid-plan/conditional alternatives are disclosed and excluded.
    private var recurringCost: some View {
        GroupBox("Potential annual savings") {
            VStack(alignment: .leading, spacing: 10) {
                if allowsRecurring {
                    HStack {
                        Text("What do you pay now?").font(.headline)
                        Spacer(minLength: 10)
                    }
                    HStack {
                        Text("$")
                        TextField("Current subscription", text: Binding(
                            get: { state.annualCostText[source.id, default: ""] },
                            set: { state.setOriginalCost($0, appID: source.id) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 145)
                        Picker("Billed", selection: Binding(
                            get: { state.billingPeriod[source.id, default: .annually] },
                            set: { state.setBillingPeriod($0, appID: source.id) }
                        )) {
                            ForEach(AppState.BillingPeriod.allCases) { period in
                                Text(period.rawValue).tag(period)
                            }
                        }
                        .frame(maxWidth: 180)
                        Spacer()
                    }
                    if !state.annualCostText[source.id, default: ""].isEmpty &&
                       state.annualCostOverrides[source.id] == nil {
                        Text("Enter an amount like 9.99.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Toggle("I'm paying this subscription", isOn: Binding(
                        get: { state.confirmedRecurringIDs.contains(source.id) },
                        set: { state.setRecurringConfirmed($0, appID: source.id) }
                    ))
                    .disabled((state.annualCostOverrides[source.id] ?? 0) <= 0)

                    Divider()
                    Text("Which replacement would you use?").font(.headline)
                    Picker("Open-source alternative", selection: Binding(
                        get: { state.selectedAlternativeIDs[source.id] ?? "" },
                        set: { state.chooseAlternative($0, for: source) }
                    )) {
                        Text("Choose an alternative…").tag("")
                        ForEach(source.alternatives) { alternative in
                            Text(alternative.name).tag(alternative.id)
                        }
                    }
                    .frame(maxWidth: 460)

                    if let assessment = state.chosenAssessment(for: source) {
                        let selected = assessment.ranked.alternative
                        if ReplacementCostPolicy.isFreeStandalone(selected) {
                            Label("Free open-source edition · $0/year software cost",
                                  systemImage: "checkmark.circle")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            Label("Extra services or paid plans may apply. Savings aren't estimated for this option.",
                                  systemImage: "info.circle")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        if assessment.outcome != .strong {
                            Text("This option is \(assessment.outcome.label). Only a Strong match for your selected requirements can count toward savings.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Toggle("I could stop paying for the original app after switching", isOn: Binding(
                        get: { state.confirmedCancellationIDs.contains(source.id) },
                        set: { state.setCanCancel($0, for: source) }
                    ))
                    .disabled(
                        state.chosenAssessment(for: source)?.outcome != .strong ||
                        !state.confirmedRecurringIDs.contains(source.id) ||
                        !state.confirmedReplacementCostIDs.contains(source.id)
                    )
                    if state.selectedSwitchIDs.contains(source.id),
                       let original = state.annualCostOverrides[source.id],
                       let alternativeCost = state.replacementAnnualCosts[source.id] {
                        Text("Potential reduction: $\(NSDecimalNumber(decimal: original - alternativeCost).stringValue)/year")
                            .font(.headline)
                    }
                    Text("Estimate only. Keep your original app until the replacement works for you. One-time expenses and migration effort aren't included.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("This is not a recurring subscription, so it isn't counted as annual savings.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
    private var levelLabel: String {
        switch currentRecommendation.level {
        case .strong: "Strong"
        case .partial: "Partial"
        case .keep: "Keep"
        }
    }
    private var levelColor: Color {
        switch currentRecommendation.level {
        case .strong: .green
        case .partial: .orange
        case .keep: .secondary
        }
    }
}
