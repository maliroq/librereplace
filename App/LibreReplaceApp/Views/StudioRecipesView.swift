import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CryptoKit
import LibreReplaceCore

/// Publicly reviewed builds and personally imported recipes have separate
/// sections. Nothing is installed or executed when a recipe is imported.
struct StudioRecipesView: View {
    let onOpenComposer: () -> Void
    let onOpenLab: () -> Void
    @EnvironmentObject private var state: AppState
    @State private var saved: [StudioSavedRecipe] = []
    @State private var skipped: [String] = []
    @State private var publicBuilds: [StudioCommunityBuild] = []
    @State private var query = ""
    @State private var category = "All"
    @State private var loading = false
    @State private var importingID: String?
    @State private var galleryMessage = ""
    @State private var notice = ""
    @State private var errorMessage: String?
    @State private var showContributorHelp = false
    @State private var openRecipe: RecipeSelection?
    @State private var removeRecipeID: String?

    private struct RecipeSelection: Identifiable {
        let id = UUID()
        let resolved: StudioResolvedRecipePlan
    }

    private var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
    private var allComponents: [StudioComponent] {
        (state.catalog?.apps ?? []).flatMap { StudioCatalogComposer.components(for: $0) }
    }
    private var categories: [String] {
        ["All"] + Array(Set(publicBuilds.map(\.category))).sorted()
    }
    private var filtered: [StudioCommunityBuild] {
        publicBuilds.filter { build in
            let matchesCategory = category == "All" || category == build.category
            let matchesQuery = query.isEmpty ||
                ([build.title, build.summary, build.paidApp, build.contributor] + build.freeApps)
                    .contains(where: { $0.localizedCaseInsensitiveContains(query) })
            return matchesCategory && matchesQuery
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                if !saved.isEmpty { importedSection }
                browser
                contributorSection
            }
            .padding(24)
            .frame(maxWidth: 1120)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Community Builds")
        .task {
            reload()
            await refreshGallery()
        }
        .onChange(of: state.catalog != nil) { _, hasCatalog in
            if hasCatalog { reload() }
        }
        .sheet(item: $openRecipe) { selection in
            StudioGuidedSwitchView(plan: selection.resolved.plan,
                sourceApp: selection.resolved.sourceApp, onOpenLab: onOpenLab)
        }
        .confirmationDialog("Remove imported recipe?", isPresented: Binding(
            get: { removeRecipeID != nil },
            set: { if !$0 { removeRecipeID = nil } }
        )) {
            Button("Remove recipe", role: .destructive) {
                if let id = removeRecipeID {
                    do {
                        try StudioRecipeLibrary.remove(id: id, in: applicationSupport)
                        reload()
                        notice = "Recipe removed from your library."
                    } catch { errorMessage = error.localizedDescription }
                }
                removeRecipeID = nil
            }
            Button("Cancel", role: .cancel) { removeRecipeID = nil }
        } message: {
            Text("Only this imported recipe will be removed. Saved setups and installed apps stay unchanged.")
        }
        .alert("Community Builds", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 60, height: 60)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
            Text("Share setups that work")
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            Text("Find setups people have shared, import recipes, or share one that works for you.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 580)
            HStack(spacing: 10) {
                Button { submitBuild() } label: {
                    Label("Share your build", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                Button { importRecipe() } label: {
                    Label("Import recipe", systemImage: "square.and.arrow.down")
                }
                .disabled(state.catalog == nil)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 20)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
    }

    private var browser: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Browse community builds").font(.title2.bold())
                Spacer(minLength: 8)
                if loading { ProgressView().controlSize(.small) }
                Button { Task { await refreshGallery() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .help("Refresh the community gallery")
            }
            if !publicBuilds.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search by app, task, or free tool", text: $query)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search community builds")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                Divider().frame(height: 18)
                Picker("Category", selection: $category) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 148)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }

            if publicBuilds.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up.slash")
                        .font(.system(size: 34)).foregroundStyle(.secondary)
                    Text("Community builds are coming")
                        .font(.headline)
                    Text(galleryMessage.isEmpty
                         ? "Browse free setups in Discover, or import a recipe you've saved."
                         : galleryMessage)
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                    HStack(spacing: 10) {
                        Button("Explore free setups") { onOpenComposer() }
                            .buttonStyle(.borderedProminent)
                        Button("Import a recipe…") { importRecipe() }
                            .disabled(state.catalog == nil)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 190)
                .padding(20)
                .background(Color.secondary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 14)], spacing: 14) {
                    ForEach(filtered) { build in buildCard(build) }
                }
            }
        }
    }

    private func buildCard(_ build: StudioCommunityBuild) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                AppArtwork(name: build.paidApp, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(build.title).font(.headline).lineLimit(2)
                    Text("Replaces \(build.paidApp)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Text(build.summary).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(4)
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text(build.freeApps.joined(separator: " + "))
                    .lineLimit(2)
            }
            .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack {
                Text("By \(build.contributor)").lineLimit(1)
                Spacer(minLength: 4)
                Text(build.category).lineLimit(1)
            }
            .font(.caption2).foregroundStyle(.tertiary)
            Divider()
            HStack {
                Text("Reviewed \(build.lastReviewed)").font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 5)
                Button(importingID == build.id ? "Importing…" : "Add to My Library") {
                    Task { await importPublicBuild(build) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(importingID != nil || state.catalog == nil)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 270, alignment: .topLeading)
        .background(Color.secondary.opacity(0.065), in: RoundedRectangle(cornerRadius: 14))
    }

    private var importedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your imported builds").font(.title2.bold())
                Spacer()
                Text("\(saved.count)").font(.caption).foregroundStyle(.secondary)
                Button("Open Folder") { showFolder() }.buttonStyle(.bordered)
            }
            ForEach(saved) { entry in
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.recipe.sourceWorkflow).font(.headline)
                    HStack {
                        Text("\(entry.recipe.componentIDs.count) components")
                        Text("·")
                        Text("\(entry.recipe.requirements.filter(\.essential).count) must-haves")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button("Explore this setup…") { exploreRecipe(entry.recipe) }
                            .buttonStyle(.borderedProminent)
                        Button("Remove", role: .destructive) { removeRecipeID = entry.recipe.id }
                            .buttonStyle(.bordered)
                    }
                    DisclosureGroup("See components and actions") {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(entry.recipe.componentIDs, id: \.self) { id in
                                Text(allComponents.first(where: { $0.id == id })?.name ?? id)
                            }
                            Divider()
                            ForEach(Array(entry.recipe.actions.enumerated()), id: \.offset) { _, action in
                                Text(actionLabel(action))
                            }
                        }
                        .font(.callout).padding(.top, 6)
                    }
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.065), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var contributorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "hammer.fill")
                    .foregroundStyle(.secondary)
                Text("Built something worth sharing?").font(.headline)
                Spacer()
                Button("Start a setup") { onOpenComposer() }
                    .buttonStyle(.bordered)
            }
            Text("Build a free setup in Discover, export its recipe, and submit it for review. You stay in control of what you share.")
                .font(.callout).foregroundStyle(.secondary)
            DisclosureGroup("How to publish a community build", isExpanded: $showContributorHelp) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Choose an app in Discover and configure a working replacement.")
                    Text("2. Export a JSON recipe from the selected setup.")
                    Text("3. Select Share your build to open a GitHub submission. Attach the recipe and describe what you tested.")
                    Text("4. Reviewed recipes appear in the online gallery after the maintainer publishes them.")
                    HStack {
                        Button("Open my recipe folder") { showFolder() }
                        Button("Submit on GitHub") { submitBuild() }
                    }.padding(.top, 3)
                }
                .font(.callout).padding(.top, 8)
            }
        }
        .padding(18)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .bottomLeading) {
            if !notice.isEmpty { Text(notice).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 18).offset(y: 20) }
        }
    }

    @MainActor
    private func refreshGallery() async {
        loading = true
        defer { loading = false }
        do {
            var request = URLRequest(url: StudioCommunityRegistry.indexURL)
            request.timeoutInterval = 12
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                publicBuilds = []
                galleryMessage = "The online gallery isn't published yet. You can still import recipes and submit your own builds."
                return
            }
            publicBuilds = try StudioCommunityRegistry.read(data)
            galleryMessage = ""
        } catch {
            publicBuilds = []
            galleryMessage = "Couldn't load the online gallery. Your imported builds remain available offline."
        }
    }

    @MainActor
    private func importPublicBuild(_ build: StudioCommunityBuild) async {
        importingID = build.id
        defer { importingID = nil }
        do {
            var request = URLRequest(url: StudioCommunityRegistry.recipeURL(for: build))
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  data.count <= 256 * 1024 else {
                throw StudioRecipeValidationIssue("Could not download the reviewed recipe")
            }
            let actualHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actualHash == build.recipeSHA256 else {
                throw StudioRecipeValidationIssue("Recipe differs from the published reviewed version")
            }
            let entry = try StudioRecipeLibrary.store(data, catalog: allComponents, in: applicationSupport)
            notice = "Added \(entry.recipe.sourceWorkflow) to your library."
            reload()
        } catch { errorMessage = error.localizedDescription }
    }

    private func exploreRecipe(_ recipe: StudioReplacementRecipe) {
        guard let catalog = state.catalog,
              let found = StudioRecipePlanResolver.resolve(recipe, in: catalog,
                  macOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion) else {
            errorMessage = "This recipe no longer matches a complete setup in the current catalog. Its file is still saved; choose updated options in Discover."
            return
        }
        openRecipe = RecipeSelection(resolved: found)
    }

    private func actionLabel(_ action: StudioRecipeAction) -> String {
        switch action.kind {
        case .installHomebrewCask, .installHomebrewFormula: "Optional app installation · \(action.targetID)"
        case .invokeBuiltInBridge: "Local capability · \(action.targetID)"
        case .verifyCapability: "Capability check · \(action.targetID)"
        }
    }

    private func reload() {
        guard state.catalog != nil else { return }
        do {
            let snapshot = try StudioRecipeLibrary.load(catalog: allComponents, in: applicationSupport)
            saved = snapshot.recipes
            skipped = snapshot.skipped
            if !skipped.isEmpty { notice = "\(skipped.count) older recipe files need review." }
        } catch { errorMessage = error.localizedDescription }
    }

    private func importRecipe() {
        let panel = NSOpenPanel()
        panel.title = "Import a community replacement recipe"
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size > 0 && size <= 256 * 1024 else {
                throw StudioRecipeValidationIssue("Choose a JSON recipe under 256 KB")
            }
            let data = try Data(contentsOf: url)
            let entry = try StudioRecipeLibrary.store(data, catalog: allComponents, in: applicationSupport)
            notice = "Imported \(entry.recipe.id) into your library."
            reload()
        } catch { errorMessage = error.localizedDescription }
    }

    private func submitBuild() {
        guard let url = URL(string: "https://github.com/maliroq/librereplace/issues/new?template=community-build.yml") else { return }
        NSWorkspace.shared.open(url)
    }

    private func showFolder() {
        do {
            _ = try StudioRecipeLibrary.load(catalog: allComponents, in: applicationSupport)
            NSWorkspace.shared.open(StudioRecipeLibrary.directory(in: applicationSupport))
        } catch { errorMessage = error.localizedDescription }
    }
}
