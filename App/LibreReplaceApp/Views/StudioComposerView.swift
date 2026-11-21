import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LibreReplaceCore

struct StudioComposerView: View {
    let embedded: Bool
    @EnvironmentObject private var state: AppState
    @State private var selectedAppID = "cleanshot-x"
    @AppStorage("LibreReplace.studio.cleanshotRequiresLocalOCR.v1") private var requireLocalOCR = false
    @State private var showAll = false
    @State private var showComparison = false
    @State private var recipeMessage = ""
    @State private var recipeError: String?
    @State private var setupSelection: StudioSetupSelection?
    let onOpenLab: () -> Void
    let onOpenPDFRescue: () -> Void
    let onOpenRecipes: () -> Void

    init(embedded: Bool = false, onOpenLab: @escaping () -> Void,
         onOpenPDFRescue: @escaping () -> Void, onOpenRecipes: @escaping () -> Void) {
        self.embedded = embedded
        self.onOpenLab = onOpenLab
        self.onOpenPDFRescue = onOpenPDFRescue
        self.onOpenRecipes = onOpenRecipes
    }

    private struct StudioSetupSelection: Identifiable {
        let id = UUID()
        let plan: StudioComposedPlan
        let sourceApp: PaidApplication
    }

    private var options: [PaidApplication] {
        (state.catalog?.apps ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private var selected: PaidApplication? { options.first(where: { $0.id == selectedAppID }) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !embedded {
                    Text("Build your free setup").font(.largeTitle.bold())
                } else if let app = selected {
                    HStack(alignment: .top, spacing: 13) {
                        AppArtwork(name: app.name, bundleIDs: app.bundleIdentifiers, size: 72)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.name).font(.title2.bold())
                            Text(AppPresentation.summary(for: app))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("By \(app.vendor) · \(app.alternatives.count) free \(app.alternatives.count == 1 ? "option" : "options")")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 6)
                        Button("Recipes", systemImage: "books.vertical") { onOpenRecipes() }
                            .labelStyle(.iconOnly)
                            .help("Community recipes")
                    }
                    .padding(.vertical, 3)
                }
                if options.isEmpty {
                    ContentUnavailableView("Catalog not loaded", systemImage: "square.stack.3d.up", description: Text("Open this page after the catalog loads."))
                } else {
                    if !embedded {
                    Picker("Paid application", selection: $selectedAppID) {
                        ForEach(options) { app in Text(app.name).tag(app.id) }
                    }
                    .frame(maxWidth: 500, alignment: .leading)
                    .onChange(of: selectedAppID) { _, _ in
                        recipeMessage = ""
                        showAll = false
                    }
                    }
                    if let app = selected {
                        requirements(for: app)
                        individualAlternatives(for: app)
                        plans(for: app)
                    }
                }
                if !recipeMessage.isEmpty {
                    Label(recipeMessage, systemImage: "info.circle").font(.callout)
                }
            }
            .padding(embedded ? 0 : 24)
            .frame(maxWidth: 1000, alignment: .leading)
        }
        .onAppear { selectedAppID = state.requestedComposerAppID }
        .onChange(of: state.requestedComposerAppID) { _, id in selectedAppID = id }
        .onChange(of: selectedAppID) { _, _ in
            recipeMessage = ""
            showAll = false
            showComparison = false
        }
        .sheet(item: $setupSelection) { selection in
            StudioGuidedSwitchView(plan: selection.plan, sourceApp: selection.sourceApp, onOpenLab: onOpenLab)
        }
        .alert("Recipe could not be saved", isPresented: Binding(get: { recipeError != nil }, set: { if !$0 { recipeError = nil } })) {
            Button("OK", role: .cancel) { recipeError = nil }
        } message: { Text(recipeError ?? "") }
    }

    @ViewBuilder
    private func individualAlternatives(for app: PaidApplication) -> some View {
        // A one-option catalog has nothing to compare. Its app is already in
        // Candidate setups; showing another collapsed row only creates clutter.
        if app.alternatives.count > 1 {
            DisclosureGroup(isExpanded: $showComparison) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("See how each app handles your must-have features. Setups below may combine tools to cover more.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(ExploreDecision.assess(app,
                        requiredFeatureIDs: state.requiredFeatureIDs(for: app)),
                        id: \.ranked.alternative.id) { assessment in
                        let alternative = assessment.ranked.alternative
                        HStack(alignment: .top, spacing: 11) {
                            AppArtwork(name: alternative.name, size: 46)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(alternative.name).font(.headline)
                                Text(AppPresentation.summary(for: alternative))
                                    .font(.callout).foregroundStyle(.secondary)
                                if assessment.requirements.isEmpty {
                                    Text("Select essentials above to compare coverage")
                                        .font(.caption).foregroundStyle(.secondary)
                                } else {
                                    let supported = assessment.requirements.filter {
                                        alternative.support[$0.id] == .full
                                    }.count
                                    Text("\(supported) of \(assessment.requirements.count) essentials fully supported in catalog · \(assessment.outcome.label)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                if !assessment.incompleteRequired.isEmpty {
                                    Text("Gaps or limitations: " + assessment.incompleteRequired.map(\.label).joined(separator: ", "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 3)
                            if let url = URL(string: alternative.homepageURL),
                               ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                                Link("Website", destination: url)
                            }
                        }
                        Divider()
                    }
                    Text("These assessments are catalog-based, not verified trials on your Mac.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.top, 10)
            } label: {
                Text("Compare \(app.alternatives.count) individual free apps")
                    .font(.callout.weight(.medium))
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func requirements(for app: PaidApplication) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What must work?").font(.title2.bold())
            Text("Choose the features that matter most to you.")
                .font(.callout).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8, alignment: .leading)],
                      alignment: .leading, spacing: 9) {
                ForEach(app.capabilities, id: \.id) { capability in
                    Toggle(isOn: Binding(
                        get: { state.isRequired(capability.id, for: app) },
                        set: { state.setRequired(capability.id, for: app, enabled: $0) }
                    )) {
                        Text(capability.label)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .toggleStyle(.checkbox)
                }
            }
            if app.id == "cleanshot-x", state.requiredFeatureIDs(for: app).contains("ocr") {
                Divider()
                Toggle("Require LibreReplace's on-device image OCR", isOn: $requireLocalOCR)
                    .toggleStyle(.checkbox)

            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func plans(for app: PaidApplication) -> some View {
        let required = state.requiredFeatureIDs(for: app)
        let plans = StudioCatalogComposer.compose(
            for: app,
            requiredFeatureIDs: required,
            macOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            requireLocalOCR: requireLocalOCR,
            limit: 32
        )
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Candidate setups").font(.title2.bold())
                Spacer()
                Text("\(plans.count) shown").font(.caption).foregroundStyle(.secondary)
            }
            if required.isEmpty {
                Text("Choose at least one must-have feature to build a meaningful plan.")
                    .foregroundStyle(.secondary)
            } else if plans.isEmpty {
                Text("There isn't enough documented capability coverage for this selection yet. Try changing requirements or checking additional tools.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(plans.prefix(showAll ? plans.count : 3).enumerated()), id: \.offset) { index, plan in
                    planCard(plan, app: app, index: index)
                }
                if plans.count > 3 {
                    Button(showAll ? "Show fewer setups" : "Show all \(plans.count) setups") { showAll.toggle() }
                }
            }

        }
    }

    private func planCard(_ plan: StudioComposedPlan, app: PaidApplication, index: Int) -> some View {
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Free setup \(index + 1)")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 6)
                Label(plan.readiness == .eligibleForTrial ? "Catalog match" : "Review gaps",
                      systemImage: plan.readiness == .eligibleForTrial ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.caption.weight(.medium))
            }
            ForEach(plan.components, id: \.id) { component in
                HStack(alignment: .center, spacing: 11) {
                    AppArtwork(name: component.name, size: 38)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(component.name).font(.subheadline.weight(.medium))
                        Text(AppPresentation.summary(for: component, replacing: app))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            let essential = plan.coverage.filter { $0.requirement.essential }
            let fullCount = essential.filter { $0.state == .supported }.count
            let partialCount = essential.filter { $0.state == .partial }.count
            let unknownCount = essential.filter { $0.state == .unverified }.count
            Text("\(fullCount) supported" +
                 (partialCount > 0 ? " · \(partialCount) partial" : "") +
                 (unknownCount > 0 ? " · \(unknownCount) unverified" : "") +
                 " of \(essential.count) must-haves")
                .font(.callout.weight(.medium))
            DisclosureGroup("See coverage and gaps") {
                VStack(alignment: .leading, spacing: 9) {
                ForEach(plan.coverage, id: \.requirement.id) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: item.state == .supported ? "checkmark.circle" : "questionmark.circle")
                            .frame(width: 18)
                        Text(item.requirement.id == "local-image-ocr" ? "On-device image OCR" :
                             (app.capabilities.first(where: { $0.id == item.requirement.id })?.label ?? item.requirement.id))
                        if item.requirement.essential { Text("Required").font(.caption).foregroundStyle(.secondary) }
                        Spacer(minLength: 8)
                        Text(item.state.rawValue.capitalized).foregroundStyle(.secondary)
                    }.font(.callout)
                    if !item.supportingComponentIDs.isEmpty {
                        Text("From: " + item.supportingComponentIDs.compactMap { id in plan.components.first(where: { $0.id == id })?.name }.joined(separator: ", "))
                            .font(.caption2).foregroundStyle(.secondary).padding(.leading, 26)
                    }
                }
                ForEach(plan.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
                if plan.components.contains(where: { $0.id == "bridge.image-ocr" }) {
                    Text("Image OCR works with saved images.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if plan.components.contains(where: { $0.id == "bridge.document-text-ocr" }) {
                    Text("Document OCR creates a separate searchable output.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                }
                .padding(.top, 8)
            }
            HStack(spacing: 8) {
                Button(plan.readiness == .eligibleForTrial ? "Explore setup…" : "Review gaps…") {
                    setupSelection = StudioSetupSelection(plan: plan, sourceApp: app)
                }
                .buttonStyle(.borderedProminent)
                Button("Save for later") { saveToMySetups(plan, for: app) }
                Menu("More") {
                    if app.id == "acrobat-pro" || plan.components.contains(where: { $0.kind == .builtInBridge }) {
                        Button(app.id == "acrobat-pro" ? "Try PDF Rescue" : "Try local tools") {
                            if app.id == "acrobat-pro" { onOpenPDFRescue() } else { onOpenLab() }
                        }
                    }
                    Button("Export recipe draft…") { saveRecipe(plan, for: app) }
                        .disabled(plan.readiness != .eligibleForTrial)
                }
                .accessibilityLabel("More actions for free setup \(index + 1)")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
    }


    private func saveToMySetups(_ plan: StudioComposedPlan, for app: PaidApplication) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let hasOCR = plan.coverage.contains { $0.requirement.id == "local-image-ocr" && $0.requirement.essential }
        let saved = StudioSavedSetup(paidAppID: app.id,
            requiredFeatureIDs: state.requiredFeatureIDs(for: app),
            componentIDs: plan.components.map(\.id), requiresLocalOCR: hasOCR)
        do {
            try StudioSavedSetupLibrary.add(saved, in: support)
            recipeMessage = "Saved in My Setups. No download needed."
        } catch { recipeError = error.localizedDescription }
    }

    private func saveRecipe(_ plan: StudioComposedPlan, for app: PaidApplication) {
        do {
            let draft = try StudioRecipeFactory.makeDraft(for: plan,
                workflow: "Free replacement workflow for \(app.name). Test before switching.")
            let panel = NSSavePanel()
            panel.title = "Export a reviewable recipe draft"
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "\(draft.recipe.id).json"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try draft.data.write(to: url, options: .atomic)
            guard try Data(contentsOf: url) == draft.data else { throw CocoaError(.fileWriteUnknown) }
            recipeMessage = "Saved a validated recipe draft. Loading or saving it does not install anything."
        } catch {
            recipeError = error.localizedDescription
        }
    }
}
