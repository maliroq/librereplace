import SwiftUI
import LibreReplaceCore

/// The only place to browse alternatives, choose requirements, and assemble
/// a free stack. The composer is shared rather than duplicating the checklist.
struct StudioReplaceView: View {
    @EnvironmentObject private var state: AppState
    @State private var query = ""
    @State private var installedOnly = false
    let onOpenLab: () -> Void
    let onOpenPDFRescue: () -> Void
    let onOpenRecipes: () -> Void

    private var all: [PaidApplication] {
        (state.catalog?.apps ?? []).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    private var filtered: [PaidApplication] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let knownIDs = Set(state.recommendations.map(\.match.catalogApp.id))
        let matches = all.filter { app in
            (!installedOnly || knownIDs.contains(app.id)) &&
            (term.isEmpty || ([app.name, app.vendor] + app.nameAliases + app.alternatives.map(\.name))
                .contains { $0.localizedCaseInsensitiveContains(term) })
        }
        guard !term.isEmpty else { return matches }
        return matches.sorted { lhs, rhs in
            let left = searchRank(lhs, term: term)
            let right = searchRank(rhs, term: term)
            return left == right
                ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                : left < right
        }
    }

    // Put the actual paid-app name first, rather than alphabetical near-misses.
    // A query can also match a free alternative; never hide why it appeared.
    private func searchRank(_ app: PaidApplication, term: String) -> Int {
        let q = term.lowercased()
        let name = app.name.lowercased()
        if name == q { return 0 }
        if name.hasPrefix(q) { return 1 }
        if name.contains(q) { return 2 }
        if app.nameAliases.contains(where: { $0.localizedCaseInsensitiveContains(term) }) { return 3 }
        if app.alternatives.contains(where: { $0.name.lowercased().hasPrefix(q) }) { return 4 }
        if app.alternatives.contains(where: { $0.name.localizedCaseInsensitiveContains(term) }) { return 5 }
        return 6
    }

    private func matchedAlternative(for app: PaidApplication) -> String? {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return nil }
        let primary = [app.name, app.vendor] + app.nameAliases
        guard !primary.contains(where: { $0.localizedCaseInsensitiveContains(term) }) else { return nil }
        return app.alternatives.first(where: { $0.name.localizedCaseInsensitiveContains(term) })?.name
    }
    private var current: PaidApplication? {
        all.first { $0.id == state.requestedComposerAppID }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Find your next free setup")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Choose an app, pick what matters, and explore free options.")
                        .foregroundStyle(.secondary)
                }
                searchField
                if geometry.size.width >= 720 {
                    HStack(alignment: .top, spacing: 20) {
                        browser
                            .frame(width: min(286, max(238, geometry.size.width * 0.30)))
                        Divider()
                        if filtered.isEmpty {
                            emptyResults
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            composer
                        }
                    }
                } else {
                    compactBrowser
                    if filtered.isEmpty {
                        emptyResults
                    } else {
                        composer
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Discover")
        .onAppear { applyRequestedSearch(state.requestedExploreQuery) }
        .onChange(of: state.requestedExploreQuery) { _, value in applyRequestedSearch(value) }
        .onChange(of: query) { _, _ in keepSelectionVisible() }
        .onChange(of: installedOnly) { _, _ in keepSelectionVisible() }
    }

    private var browser: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("On my Mac", isOn: $installedOnly)
                .font(.callout)
                .disabled(state.recommendations.isEmpty)
            Text("Browse · \(filtered.count) apps")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(filtered) { app in
                        Button { choose(app) } label: {
                            HStack(spacing: 10) {
                                AppArtwork(name: app.name, bundleIDs: app.bundleIdentifiers, size: 44)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(app.name)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Text(AppPresentation.summary(for: app))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    if let matched = matchedAlternative(for: app) {
                                        Text("Free app match: \(matched)")
                                            .font(.caption2)
                                            .foregroundStyle(.tint)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(app.id == current?.id ? Color.accentColor.opacity(0.12) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 12))
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Select \(app.name)")
                    }
                }
            }
        }
    }

    private var emptyResults: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                installedOnly ? "No matching apps on this Mac" : "No matches found",
                systemImage: "magnifyingglass",
                description: Text(installedOnly
                    ? "Try showing the full catalog or changing your search."
                    : "Try another app name or browse the catalog.")
            )
            Button(installedOnly ? "Show all apps" : "Clear search") {
                if installedOnly { installedOnly = false }
                else { query = "" }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var compactBrowser: some View {
        VStack(alignment: .leading, spacing: 9) {
            Picker("Choose an app", selection: Binding(
                get: { current?.id ?? "" },
                set: { id in if let app = all.first(where: { $0.id == id }) { choose(app) } }
            )) {
                ForEach(filtered) { app in Text(app.name).tag(app.id) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search apps and free alternatives", text: $query)
                .textFieldStyle(.plain)
                .accessibilityLabel("Search replacements")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }

    private var composer: some View {
        StudioComposerView(embedded: true,
            onOpenLab: onOpenLab,
            onOpenPDFRescue: onOpenPDFRescue,
            onOpenRecipes: onOpenRecipes)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func keepSelectionVisible() {
        guard let first = filtered.first else { return }
        if !filtered.contains(where: { $0.id == state.requestedComposerAppID }) {
            choose(first)
        }
    }

    private func choose(_ app: PaidApplication) {
        state.requestedComposerAppID = app.id
    }

    private func applyRequestedSearch(_ value: String) {
        query = value
        if !value.isEmpty, let bestMatch = filtered.first {
            choose(bestMatch)
        }
    }
}
