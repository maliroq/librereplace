import SwiftUI
import LibreReplaceCore

struct CatalogView: View {
    @EnvironmentObject private var state: AppState
    @State private var search = ""

    var filtered: [PaidApplication] {
        let apps = state.catalog?.apps ?? []
        guard !search.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || $0.alternatives.contains { $0.name.localizedCaseInsensitiveContains(search) }
        }
    }

    var body: some View {
        Group {
            if filtered.isEmpty && !search.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                List(filtered) { app in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name).font(.headline).lineLimit(2)
                        Text(app.alternatives.map(\.name).joined(separator: ", "))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Text("Last verified \(app.lastVerified)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .searchable(text: $search, prompt: "Commercial app or alternative")
        .navigationTitle("Evidence catalog")
    }
}
