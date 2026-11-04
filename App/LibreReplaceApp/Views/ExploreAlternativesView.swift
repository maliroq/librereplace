import SwiftUI
import LibreReplaceCore

/// Works entirely from the bundled catalog, including on a Mac with zero matching apps.
struct ExploreAlternativesView: View {
    @EnvironmentObject private var state: AppState
    @State private var query = ""
    @State private var selectedAppID: String?

    private var available: [PaidApplication] {
        (state.catalog?.apps ?? []).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    private var filtered: [PaidApplication] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return available }
        return available.filter { app in
            ([app.name, app.vendor] + app.nameAliases + app.alternatives.map(\.name)).contains {
                $0.localizedCaseInsensitiveContains(query)
            }
        }
    }
    private var selected: PaidApplication? {
        available.first { $0.id == selectedAppID }
    }
    private func select(_ app: PaidApplication) {
        selectedAppID = app.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Explore Alternatives").font(.largeTitle.bold())
                Text("Compare paid software with open-source options. You don't need the paid app installed.")
                    .foregroundStyle(.secondary)
            }
            TextField("Search an app or alternative", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search supported applications and alternatives")
            HStack(alignment: .top, spacing: 18) {
                List(filtered) { app in
                    Button {
                        select(app)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(app.name).fontWeight(app.id == selectedAppID ? .semibold : .regular)
                                Text(app.vendor).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 3)
                            if app.id == selectedAppID { Image(systemName: "checkmark") }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Explore \(app.name)")
                }
                .frame(minWidth: 205, idealWidth: 245, maxWidth: 300)
                .overlay {
                    if filtered.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                }
                ScrollView {
                    if let app = selected {
                        comparison(app)
                    } else {
                        ContentUnavailableView(
                            "Choose an app",
                            systemImage: "square.stack.3d.up",
                            description: Text("Search or choose any supported paid application to compare without scanning your Mac.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 310)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(24)
        .navigationTitle("Explore Alternatives")
        .onAppear {
            if selectedAppID == nil, let first = available.first { select(first) }
        }
        .onChange(of: available.count) { _, count in
            if count > 0 && selectedAppID == nil, let first = available.first { select(first) }
        }
    }

    @ViewBuilder private func comparison(_ app: PaidApplication) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .firstTextBaseline) {
                Text(app.name).font(.title.bold())
                Spacer()
                Text(app.pricing.model.rawValue)
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let note = app.pricing.note {
                Text(note).font(.callout).foregroundStyle(.secondary)
            }
            if let pricing = app.pricing.sourceURL, let url = URL(string: pricing) {
                Link("Check current official pricing", destination: url).font(.callout)
            }
            Text("What do you need to keep?").font(.headline)
            Text("Preselected features are marked critical by the catalog. Change these to match your workflow; recommendations update immediately.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(app.capabilities, id: \.id) { capability in
                Toggle(isOn: Binding(
                    get: { state.isRequired(capability.id, for: app) },
                    set: { state.setRequired(capability.id, for: app, enabled: $0) }
                )) {
                    Text(capability.label)
                }
                .toggleStyle(.checkbox)
            }
            if state.requiredFeatureIDs(for: app).isEmpty {
                Label("Select at least one essential feature for a recommendation.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            Divider()
            Text("Open-source options").font(.headline)
            ForEach(ExploreDecision.assess(app, requiredFeatureIDs: state.requiredFeatureIDs(for: app)), id: \.ranked.alternative.id) { decision in
                alternativeCard(decision, source: app)
            }
            Text("Coverage is weighted across selected required features, or all catalog features when none are selected. It is not proof of feature parity, safety, polish, or file-format compatibility. Unknown support never counts as a match.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Catalog record dated \(app.lastVerified). Linked documentation is not a hands-on verification of feature parity; test before migrating.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 4)
    }

    @ViewBuilder private func alternativeCard(_ decision: ExploreAssessment, source: PaidApplication) -> some View {
        let alt = decision.ranked.alternative
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(alt.name).font(.title3.bold())
                    Spacer(minLength: 4)
                    Text(decision.outcome.label).font(.callout.weight(.semibold))
                }
                Text("\(Int((decision.ranked.coverage * 100).rounded()))% \(decision.requirements.isEmpty ? "overall catalog coverage" : "selected feature coverage") · \(alt.license)")
                    .font(.caption).foregroundStyle(.secondary)
                if !decision.evidenceFresh {
                    Label("Evidence is older than the freshness window or cannot be verified.", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                }
                if !decision.incompleteRequired.isEmpty {
                    Text("Required features not fully supported: \(decision.incompleteRequired.map(\.label).joined(separator: ", "))")
                        .font(.callout)
                } else if !decision.requirements.isEmpty {
                    Text("All selected required features are marked fully supported in the catalog; this is not a tested guarantee.")
                        .font(.callout)
                }
                ForEach(source.capabilities, id: \.id) { capability in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: symbol(alt.support[capability.id] ?? .unknown))
                            .frame(width: 17)
                        Text(capability.label)
                        Spacer(minLength: 8)
                        Text((alt.support[capability.id] ?? .unknown).rawValue.capitalized)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                ForEach(alt.limitations, id: \.self) { note in
                    Text("• \(note)").font(.callout).foregroundStyle(.secondary)
                }
                HStack(spacing: 14) {
                    if let url = URL(string: alt.homepageURL) { Link("Official site", destination: url) }
                    if let repository = alt.repositoryURL, let url = URL(string: repository) { Link("Source code", destination: url) }
                }
                Text("Catalog evidence dated \(alt.lastVerified)").font(.caption).foregroundStyle(.secondary)
                ForEach(alt.evidence, id: \.url) { evidence in
                    if let url = URL(string: evidence.url) {
                        Link("\(evidence.kind.rawValue.capitalized): \(evidence.title)", destination: url)
                            .font(.caption)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
    private func symbol(_ state: FeatureSupport) -> String {
        switch state {
        case .full: "checkmark.circle"
        case .partial: "circle.lefthalf.filled"
        case .none: "xmark.circle"
        case .unknown: "questionmark.circle"
        }
    }
}
