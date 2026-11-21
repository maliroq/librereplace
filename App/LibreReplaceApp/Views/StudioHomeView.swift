import SwiftUI
import LibreReplaceCore

/// A calm starting point: one search, relevant recommendations and a compact
/// route to existing working capabilities. Browsing and configuration live in Replace.
struct StudioHomeView: View {
    @EnvironmentObject private var state: AppState
    @State private var search = ""
    @AppStorage("LibreReplace.studio.pinnedApps.v1") private var pinnedRaw = ""

    let onExplore: (String) -> Void
    let onBuild: (String) -> Void
    let onFreeSetups: () -> Void
    let onTools: () -> Void
    let onInstalled: () -> Void

    private var apps: [PaidApplication] {
        (state.catalog?.apps ?? []).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    private var pinned: Set<String> {
        Set(pinnedRaw.split(separator: ",").map(String.init))
    }
    private var personal: [PaidApplication] {
        let matches = state.recommendations.map(\.match.catalogApp)
        var seen = Set<String>()
        return (matches + apps.filter { pinned.contains($0.id) })
            .filter { seen.insert($0.id).inserted }
    }
    private var suggested: [PaidApplication] {
        let favorites = ["cleanshot-x", "bear", "paste", "textexpander", "acrobat-pro", "sublime-text"]
        return favorites.compactMap { id in apps.first(where: { $0.id == id }) }
    }
    private var matching: [PaidApplication] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        return apps.filter { app in
            ([app.name, app.vendor] + app.nameAliases + app.alternatives.map(\.name))
                .contains { $0.localizedCaseInsensitiveContains(term) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Make more of your Mac. For free.")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Find practical alternatives to the software you use.")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }

                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("What app do you want to replace?", text: $search)
                        .textFieldStyle(.plain)
                        .onSubmit { onExplore(search) }
                        .accessibilityLabel("Search for a replacement")
                    if !search.isEmpty {
                        Button {
                            search = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Clear search")
                    }
                    Button("Find a replacement") { onExplore(search) }
                        .buttonStyle(.borderedProminent)
                }
                .padding(14)
                .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))

                if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Results").font(.title2.bold())
                        if matching.isEmpty {
                            Text("No matches. Try another app name.").foregroundStyle(.secondary)
                        }
                        ForEach(matching.prefix(12)) { app in
                            appRow(app)
                        }
                    }
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your Mac").font(.headline)
                            Text("\(state.installed.count) apps found · \(state.recommendations.count) matches in LibreReplace")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("View installed apps", action: onInstalled)
                    }
                    .padding(16)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 13) {
                        HStack {
                            Text(personal.isEmpty ? "Popular starting points" : "For your Mac")
                                .font(.title2.bold())
                            Spacer()
                            Button("Browse all \(apps.count) apps") { onExplore("") }
                        }
                        let shown = personal.isEmpty ? suggested : personal
                        ForEach(shown.prefix(7)) { app in
                            appRow(app)
                        }
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "keyboard")
                            .font(.title3).frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Move your text shortcuts").font(.headline)
                            Text("TextExpander → Espanso")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open setup", action: onFreeSetups)
                    }
                    .padding(15)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(26)
            .frame(maxWidth: 930, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .navigationTitle("LibreReplace")
    }

    private func appRow(_ app: PaidApplication) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name).fontWeight(.medium)
                Text(app.alternatives.prefix(2).map(\.name).joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 10)
            Button {
                togglePinned(app.id)
            } label: {
                Image(systemName: pinned.contains(app.id) ? "star.fill" : "star")
                    .foregroundStyle(pinned.contains(app.id) ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(pinned.contains(app.id) ? "Unsave \(app.name)" : "Save \(app.name)")
            Button("View options") { onBuild(app.id) }
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 6)
    }

    private func togglePinned(_ id: String) {
        var ids = pinned
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        pinnedRaw = ids.sorted().joined(separator: ",")
    }
}
