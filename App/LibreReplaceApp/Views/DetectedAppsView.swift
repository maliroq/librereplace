import SwiftUI
import LibreReplaceCore

struct DetectedAppsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        List {
            if state.isScanning {
                ProgressView("Scanning applications…")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 28)
            } else if state.recommendations.isEmpty {
                ContentUnavailableView {
                    Label("No supported commercial apps found", systemImage: "checkmark.circle")
                } description: {
                    Text("LibreReplace scanned \(state.installed.count) applications. Unsupported apps stay local and are not added to the report.")
                }
            } else {
                ForEach(state.recommendations, id: \.match.catalogApp.id) { recommendation in
                    NavigationLink {
                        RecommendationDetailView(recommendation: recommendation)
                    } label: {
                        RecommendationRow(recommendation: recommendation)
                    }
                }
            }
        }
        .navigationTitle("Detected apps")
    }
}

private struct RecommendationRow: View {
    let recommendation: AppRecommendation

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 30)
                .foregroundStyle(badgeColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(recommendation.match.catalogApp.name)
                    .font(.headline)
                    .lineLimit(2)
                if let best = recommendation.bestAlternative {
                    Text(subtitle(best))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 12)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(badgeColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(badgeColor.opacity(0.12), in: Capsule())
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(recommendation.match.catalogApp.name), \(label) recommendation")
    }

    private var icon: String {
        switch recommendation.level {
        case .strong: "arrow.triangle.swap"
        case .partial: "circle.lefthalf.filled"
        case .keep: "hand.thumbsup"
        }
    }

    private var badgeColor: Color {
        switch recommendation.level {
        case .strong: .green
        case .partial: .orange
        case .keep: .secondary
        }
    }

    private var label: String {
        switch recommendation.level {
        case .strong: "Strong"
        case .partial: "Partial"
        case .keep: "Keep"
        }
    }

    private func subtitle(_ best: RankedAlternative) -> String {
        "\(best.alternative.name) · \(Int((best.coverage * 100).rounded()))% feature coverage"
    }
}
