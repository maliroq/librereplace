import SwiftUI
import AppKit
import LibreReplaceCore

/// A repeatable, local Free Twin. The first validated adapter is a complete
/// editor *environment* trial, not an assertion that every Sublime feature
/// is supported by Zed. Further adapters use the same persisted record format.
struct StudioFreeTwinsView: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var installer = StudioSwitchCoordinator()
    @State private var settings: MigrationPlan?
    @State private var snippets: StudioSnippetPreview?
    @State private var saved: StudioFreeTwinRecord?
    @State private var message: String?
    @State private var error: String?
    @State private var approved = false
    @State private var undoApproval = false
    @State private var installApproval = false
    @State private var isWorking = false
    @State private var savedPlans: [StudioSavedSetup] = []
    @State private var trials: [StudioWorkflowTrial] = []
    @State private var openSaved: SavedSetupSelection?
    @State private var deleteSavedID: UUID?
    @State private var showMigrationTools = false

    private struct SavedSetupSelection: Identifiable {
        let id = UUID()
        let plan: StudioComposedPlan
        let sourceApp: PaidApplication
    }

    let onExplore: () -> Void
    let onBuild: (String) -> Void
    let onOpenLab: () -> Void
    private let adapter = SublimeToZedMigration()
    private let snippetBridge = StudioSnippetBridge()
    private let store = StudioFreeTwinStore()
    private let pilotID = "sublime-zed-workstyle-v1"
    private let zedPackage = StudioApprovedInstall(componentID: "zed", name: "Zed", package: "zed", kind: .homebrewCask)
    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    private var support: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0] }
    private var zedApplication: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "dev.zed.Zed") ??
        [URL(fileURLWithPath: "/Applications/Zed.app"), home.appendingPathComponent("Applications/Zed.app")]
            .first(where: { FileManager.default.fileExists(atPath: $0.path) })
    }
    private var hasSublimeData: Bool {
        if adapter.detect(home: home) { return true }
        return ["Sublime Text", "Sublime Text 3"].contains { edition in
            FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Application Support/\(edition)/Packages/User").path)
        }
    }
    private var canPrepare: Bool {
        !isWorking && saved == nil && ((settings?.changes.isEmpty == false) || (snippets?.ready ?? 0) > 0)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your free setups").font(.largeTitle.bold())
                    Text("Pick up where you left off.")
                        .foregroundStyle(.secondary)
                }
                savedSetupSection
                DisclosureGroup(isExpanded: $showMigrationTools) {
                    VStack(alignment: .leading, spacing: 14) {
                        StudioEspansoTwinView()
                        if hasSublimeData || saved != nil {
                GroupBox {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack(alignment: .top, spacing: 12) {
                            AppArtwork(name: "Zed", size: 48)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Sublime Text → Zed").font(.title2.bold())
                                Text("Bring your editor preferences, compatible snippets, and familiar keyboard layout to Zed. No export or project upload required.")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            if saved?.state == .prepared {
                                Label("Configuration prepared", systemImage: "checkmark.seal")
                                    .foregroundStyle(.green)
                            }
                        }
                        if !hasSublimeData {
                            Label("No local Sublime settings detected. Your other apps can still be explored below.", systemImage: "info.circle")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        if let saved {
                            Label(saved.state == .prepared ? "Saved setup found" : "Partially prepared: finish or recover changes", systemImage: saved.state == .prepared ? "checkmark.circle" : "exclamationmark.triangle")
                                .font(.callout)

                            HStack {
                                Button("Use Zed") { openZed() }.buttonStyle(.borderedProminent).disabled(zedApplication == nil)
                                Button("Open a project in Zed…") { chooseProject() }.disabled(zedApplication == nil)
                                Button("Check setup") { verify() }
                                Button("Undo my changes…", role: .destructive) { undoApproval = true }
                            }
                        }
                        if settings == nil && snippets == nil {
                            Button("Check what I can bring over") { preview() }
                                .buttonStyle(.borderedProminent).disabled(isWorking || !hasSublimeData)
                        } else {
                            if let settings {
                                Label("\(settings.changes.count) editor preferences ready to apply", systemImage: "slider.horizontal.3")
                                ForEach(settings.changes, id: \.key) { change in
                                    LabeledContent(change.key.replacingOccurrences(of: "_", with: " ").capitalized) {
                                        Text(change.toValue).font(.callout)
                                    }.font(.callout)
                                }
                            }
                            if let snippets {
                                Label("\(snippets.ready) compatible snippets in \(snippets.files.count) Zed language files", systemImage: "text.badge.checkmark")
                                Text("\(snippets.scanned) found · \(snippets.issues.count) need attention")
                                    .font(.caption).foregroundStyle(.secondary)
                                if !snippets.issues.isEmpty {
                                    DisclosureGroup("Review snippets that need attention") {
                                        ForEach(snippets.issues.indices, id: \.self) { index in
                                            Text("\(snippets.issues[index].filename): \(snippets.issues[index].explanation)")
                                                .font(.caption).textSelection(.enabled)
                                        }
                                    }
                                }
                            }
                            if saved != nil {
                                Text("Restore the previous setup before preparing another one.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if canPrepare {
                                Button("Prepare my Zed setup…") { approved = true }
                                    .buttonStyle(.borderedProminent)
                            }
                            Button("Refresh compatibility check") { preview() }.disabled(isWorking)
                        }
                        if isWorking { ProgressView("Preparing and checking your setup…") }
                        Divider()
                        if zedApplication == nil {
                            Text("Zed isn't installed yet.")
                                .font(.callout)
                            if !installer.homebrewAvailable && !installer.checking {
                                Button("Check installation options") {
                                    Task { await installer.check([zedPackage]) }
                                }
                                .disabled(isWorking || installer.isInstalling)
                            }
                            if installer.checking { ProgressView("Checking installation options…") }
                            else if installer.homebrewAvailable {
                                Button("Install free Zed…") { installApproval = true }.disabled(installer.isInstalling || isWorking)
                            } else {
                                Link("Get Zed from its official website", destination: URL(string: "https://zed.dev/download")!)

                            }
                            if installer.isInstalling { ProgressView("Installing Zed with your approval…") }
                        }

                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                }
                }
                    }
                    .padding(.top, 12)
                } label: {
                    Label("Move settings from another app", systemImage: "arrow.left.arrow.right")
                        .font(.headline)
                }
                .padding(15)
                .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                if let message { Label(message, systemImage: "info.circle").font(.callout).textSelection(.enabled) }
                if let error { Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            }.padding(24).frame(maxWidth: 920, alignment: .leading)
        }
        .navigationTitle("My Setups")
        .task { reload(); loadSavedPlans(); if saved != nil { showMigrationTools = true } }
        .sheet(item: $openSaved, onDismiss: { loadSavedPlans() }) { item in
            StudioGuidedSwitchView(plan: item.plan, sourceApp: item.sourceApp, onOpenLab: onOpenLab)
        }
        .confirmationDialog("Remove saved setup?", isPresented: Binding(
            get: { deleteSavedID != nil }, set: { if !$0 { deleteSavedID = nil } }
        )) {
            Button("Remove from My Free Setups", role: .destructive) {
                if let id = deleteSavedID { removeSavedPlan(id) }
                deleteSavedID = nil
            }
            Button("Cancel", role: .cancel) { deleteSavedID = nil }
        } message: {
            Text("This removes the saved plan only. It does not remove installed applications or their files.")
        }
        .confirmationDialog("Prepare your Zed setup?", isPresented: $approved) {
            Button("Back up and prepare") { prepare() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("LibreReplace will back up your current Zed settings, then add the approved settings and compatible snippets. Your Sublime setup stays unchanged.")
        }
        .confirmationDialog("Undo LibreReplace's Zed changes?", isPresented: $undoApproval) {
            Button("Restore earlier settings and snippets", role: .destructive) { undo() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your earlier Zed settings will be restored. If you've edited them since setup, recovery stops without overwriting those edits.")
        }
        .confirmationDialog("Install Zed using Homebrew?", isPresented: $installApproval) {
            Button("Install Zed") { Task { await installer.install([zedPackage]) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("LibreReplace will run: brew install --cask zed. Homebrew may run its own installation scripts. No existing app is removed.")
        }
    }

    private var savedSetupSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Saved plans").font(.title2.bold())
                    Spacer()
                    Text("\(savedPlans.count) saved")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if savedPlans.isEmpty {
                    Text("Keep free setups here while you compare. You can return whenever you're ready.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Explore free setups") { onExplore() }
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(savedPlans) { item in
                            StudioSavedSetupCard(
                                saved: item,
                                paidApp: catalogApp(for: item.paidAppID),
                                onEdit: { editSavedPlan(item) },
                                hasTestedResult: { plan in
                                    trials.contains {
                                        $0.planIdentity == StudioWorkflowTrialStore.identity(for: plan) &&
                                        $0.macOSMajor == ProcessInfo.processInfo.operatingSystemVersion.majorVersion &&
                                        Set($0.testedRequirementIDs) == StudioWorkflowTrialStore.essentialIDs(for: plan) &&
                                        (plan.components.count < 2 || $0.interoperabilityConfirmed == true)
                                    }
                                },
                                onOpen: { plan, sourceApp in
                                    openSaved = SavedSetupSelection(plan: plan, sourceApp: sourceApp)
                                },
                                onRemove: { deleteSavedID = item.id }
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
    }

    private func catalogApp(for id: String) -> PaidApplication? {
        state.catalog?.apps.first(where: { $0.id == id })
    }

    private func loadSavedPlans() {
        do {
            savedPlans = try StudioSavedSetupLibrary.load(in: support).sorted { $0.createdAt > $1.createdAt }
        } catch { self.error = error.localizedDescription }
        do { trials = try StudioWorkflowTrialStore.load(in: support) }
        catch { trials = [] } // A damaged trial history never hides saved plans.
    }
    private func editSavedPlan(_ savedPlan: StudioSavedSetup) {
        guard let app = catalogApp(for: savedPlan.paidAppID),
              state.restoreRequiredFeatures(savedPlan.requiredFeatureIDs, for: app) else {
            error = "This plan's requirements have changed in the catalog. Choose new options in Discover."
            return
        }
        if app.id == "cleanshot-x" {
            UserDefaults.standard.set(savedPlan.requiresLocalOCR,
                forKey: "LibreReplace.studio.cleanshotRequiresLocalOCR.v1")
        }
        onBuild(app.id)
    }
    private func removeSavedPlan(_ id: UUID) {
        do {
            try StudioSavedSetupLibrary.remove(id: id, in: support)
            loadSavedPlans()
        } catch { self.error = error.localizedDescription }
    }

    private func reload() {
        do { saved = try store.load(in: support).first(where: { $0.id == pilotID }) }
        catch { self.error = error.localizedDescription }
    }
    private func preview() {
        guard !isWorking else { return }
        isWorking = true
        let home = self.home
        let id = pilotID
        Task {
            defer { isWorking = false }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try StudioFreeTwinEngine().preview(id: id, home: home)
                }.value
                settings = result.settings
                snippets = result.snippets
                error = nil
                message = "Local compatibility check complete. Nothing changed."
            } catch { self.error = error.localizedDescription }
        }
    }
    private func prepare() {
        guard canPrepare, let snippets else { return }
        isWorking = true
        let preview = StudioFreeTwinPreview(id: pilotID, settings: settings, snippets: snippets)
        let home = self.home
        let support = self.support
        Task {
            defer { isWorking = false }
            do {
                let record = try await Task.detached(priority: .userInitiated) {
                    try StudioFreeTwinEngine().prepare(preview, approved: true,
                        home: home, applicationSupport: support)
                }.value
                saved = record
                settings = nil; self.snippets = nil
                message = "Zed configuration prepared. Try your editing tasks in Zed before relying on it."
                error = nil
            } catch {
                self.error = error.localizedDescription
                reload()
            }
        }
    }
    private func verify() {
        guard let saved else { return }
        let checks = StudioFreeTwinEngine().verifyLocalChanges(saved, home: home)
        message = (checks + [zedApplication != nil ? "Zed installed" : "Zed not detected"])
            .joined(separator: ". ") + ". Actual editing workflows still need a personal trial."
    }
    private func undo() {
        guard let saved, !isWorking else { return }
        isWorking = true
        let home = self.home
        let support = self.support
        Task {
            defer { isWorking = false }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try StudioFreeTwinEngine().rollback(saved, home: home, applicationSupport: support)
                }.value
                self.saved = nil
                settings = nil; snippets = nil
                message = "LibreReplace's Zed changes were restored. Sublime was never changed."
                error = nil
            } catch { self.error = "Recovery stopped: \(error.localizedDescription)" }
        }
    }
    private func openZed() {
        guard let app = zedApplication else { error = "Zed is not installed yet."; return }
        if !NSWorkspace.shared.open(app) { error = "macOS could not launch Zed." }
    }
    private func chooseProject() {
        guard let app = zedApplication else { error = "Zed is not installed yet."; return }
        let panel = NSOpenPanel()
        panel.title = "Choose files or a project folder for Zed"
        panel.canChooseFiles = true; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Open in Zed"
        guard panel.runModal() == .OK else { return }
        NSWorkspace.shared.open(panel.urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, problem in
            if let problem { Task { @MainActor in self.error = problem.localizedDescription } }
        }
    }
}

/// Keep saved-plan recomposition out of the large Free Twins view builder.
/// Each card recomputes its plan against the current catalog and macOS version.
private struct StudioSavedSetupCard: View {
    let saved: StudioSavedSetup
    let paidApp: PaidApplication?
    let onEdit: () -> Void
    let hasTestedResult: (StudioComposedPlan) -> Bool
    let onOpen: (StudioComposedPlan, PaidApplication) -> Void
    let onRemove: () -> Void

    private var currentPlan: StudioComposedPlan? {
        guard let paidApp else { return nil }
        return StudioSavedSetupLibrary.resolve(
            saved,
            app: paidApp,
            macOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            actions
        }
        .padding(13)
        .background(Color.secondary.opacity(0.065),
                    in: RoundedRectangle(cornerRadius: 10))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            AppArtwork(name: paidApp?.name ?? "Saved setup", bundleIDs: paidApp?.bundleIdentifiers ?? [], size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(paidApp?.name ?? "Unavailable catalog app")
                    .font(.headline)
                if let paidApp {
                    Text(AppPresentation.summary(for: paidApp))
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let plan = currentPlan {
                    Text(plan.components.map(\.name).joined(separator: " + "))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if hasTestedResult(plan) {
                        Label("You tested this setup on this Mac", systemImage: "checkmark.circle")
                            .font(.caption).foregroundStyle(.green)
                    } else {
                        Text("Saved for later")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("This setup needs an updated comparison before use.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Remove", role: .destructive, action: onRemove)
                .buttonStyle(.borderless)
        }
    }

    private var actions: some View {
        HStack {
            if let plan = currentPlan {
                if let paidApp {
                    Button(plan.readiness == .eligibleForTrial ? "Open setup…" : "Review gaps…") {
                        onOpen(plan, paidApp)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if let paidApp {
                Button("Review updated options") { onEdit() }
            }
            if let paidApp {
                Button("Change requirements") { onEdit() }
            }
        }
    }
}
