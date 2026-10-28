import SwiftUI
import LibreReplaceCore

struct RecommendationDetailView: View {
    @EnvironmentObject private var state: AppState
    let recommendation: AppRecommendation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if recommendation.level == .keep {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("KEEP THIS APP", systemImage: "hand.thumbsup.fill")
                                .font(.title3.bold())
                            Text("The catalog does not currently have an open-source replacement that preserves enough of this app’s critical workflow. That is an intentional result, not an error.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                }

                annualCost

                ForEach(recommendation.rankedAlternatives, id: \.alternative.id) { ranked in
                    AlternativeCard(sourceApp: recommendation.match.catalogApp, ranked: ranked)
                }
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .navigationTitle(recommendation.match.catalogApp.name)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(recommendation.match.catalogApp.name)
                    .font(.largeTitle.bold())
                    .lineLimit(2)
                    .layoutPriority(1)
                Spacer(minLength: 12)
                Text(levelLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(levelColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(levelColor.opacity(0.12), in: Capsule())
            }

            Text("Detected \(recommendation.match.installed.version.map { "version \($0)" } ?? "on this Mac") · matched by \(recommendation.match.confidence == .bundleIdentifier ? "bundle identifier" : "name")")
                .foregroundStyle(.secondary)
            if let note = recommendation.match.catalogApp.pricing.note {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var annualCost: some View {
        GroupBox("Your recurring cost (optional)") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("$")
                    TextField("Annual amount you actually pay", text: Binding(
                        get: { state.annualCostText[recommendation.match.catalogApp.id, default: ""] },
                        set: { state.annualCostText[recommendation.match.catalogApp.id] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                    .accessibilityLabel("Annual recurring cost for \(recommendation.match.catalogApp.name)")
                    Text("per year")
                    Spacer()
                }
                Text("Enter this only if you know your actual recurring cost. It stays in memory for this app session and is used only for the local savings estimate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var levelLabel: String {
        switch recommendation.level {
        case .strong: "Strong"
        case .partial: "Partial"
        case .keep: "Keep"
        }
    }

    private var levelColor: Color {
        switch recommendation.level {
        case .strong: .green
        case .partial: .orange
        case .keep: .secondary
        }
    }
}
