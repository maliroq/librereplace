import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LibreReplaceCore

/// A user-facing installation path: read-only preflight, exact approval,
/// installation, then a separate functional check. No recipe executes here.
struct StudioGuidedSwitchView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var installer = StudioSwitchCoordinator()
    @State private var selectedIDs: Set<String>
    @State private var showInstallConfirmation = false
    @State private var showInstallOptions = false
    @State private var finishedAppScan = false
    @State private var testedRequiredIDs: Set<String> = []
    @State private var savedTrial: StudioWorkflowTrial?
    @State private var trialMessage: String?
    @State private var setupSaveMessage: String?
    @State private var testedHandoff = false
    @State private var installedDesktopApps: [InstalledApplication] = []

    let plan: StudioComposedPlan
    let sourceApp: PaidApplication?
    let onOpenLab: () -> Void

    init(plan: StudioComposedPlan, sourceApp: PaidApplication? = nil, onOpenLab: @escaping () -> Void) {
        self.plan = plan
        self.sourceApp = sourceApp
        self.onOpenLab = onOpenLab
        _selectedIDs = State(initialValue: [])
    }

    private var items: [StudioApprovedInstall] { StudioInstallApproval.proposals(for: plan) }
    private var selected: [StudioApprovedInstall] { items.filter { selectedIDs.contains($0.id) && !installer.installedIDs.contains($0.id) } }
    private var canInstall: Bool {
        installer.preflightReady && !installer.isInstalling && !installer.checking &&
        plan.readiness == .eligibleForTrial && !selected.isEmpty
    }

    private var requiredFeatures: [StudioCapabilityCoverage] {
        plan.coverage.filter(\.requirement.essential)
    }

    private var missingDesktopApps: [StudioComponent] {
        plan.components.filter {
            $0.kind == .openSourceApp && matchingInstalledApp(for: $0) == nil
        }
    }

    private var canRecordTrial: Bool {
        finishedAppScan && missingDesktopApps.isEmpty &&
        !requiredFeatures.isEmpty && plan.readiness == .eligibleForTrial &&
        testedRequiredIDs == StudioWorkflowTrialStore.essentialIDs(for: plan) &&
        (plan.components.count < 2 || testedHandoff)
    }

    private var nextTrialStep: String {
        if !finishedAppScan { return "Checking which replacement apps are available on this Mac." }
        if !missingDesktopApps.isEmpty {
            return "To save a tested result, first use " + missingDesktopApps.map(\.name).joined(separator: ", ") + ". You can save this plan without installing anything."
        }
        if plan.readiness != .eligibleForTrial {
            return "This setup still has gaps. Review the missing features in Discover before recording a successful trial."
        }
        let remaining = requiredFeatures.filter { !testedRequiredIDs.contains($0.requirement.id) }
        if !remaining.isEmpty {
            return "Try the remaining \(remaining.count) \(remaining.count == 1 ? "task" : "tasks") before saving a result. You can save the plan without testing."
        }
        if plan.components.count > 1 && !testedHandoff {
            return "Finally, test a real handoff between the tools and check the handoff box."
        }
        return "Your checklist is ready to save."
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.shield").font(.title).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Explore this free setup").font(.title2.bold())
                    Text(plan.components.map(\.name).joined(separator: " + "))
                        .font(.callout).foregroundStyle(.secondary)
                    if let setupSaveMessage {
                        Text(setupSaveMessage).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Button("Save for later") { saveForLater() }
                    .disabled(sourceApp == nil || installer.isInstalling)
                Button("Done") { dismiss() }.disabled(installer.isInstalling)
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    matchSection
                    readySection
                    trySection
                    recordSection
                }.padding(18)
            }
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 580, idealHeight: 720)
        .task {
            loadTrial()
            await refreshInstalledApps()
        }
        .onChange(of: showInstallOptions) { _, expanded in
            if expanded && !items.isEmpty { Task { await installer.check(items) } }
        }
        .onChange(of: installer.isInstalling) { _, installing in
            if installing { showInstallOptions = true }
            if !installing { Task { await refreshInstalledApps() } }
        }
        .alert("Approve Homebrew installation?", isPresented: $showInstallConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Install approved apps") {
                do {
                    let actions = try StudioInstallApproval.approve(plan: plan, selectedIDs: Set(selected.map(\.id)))
                    Task { await installer.install(actions) }
                } catch { installer.errorMessage = error.localizedDescription }
            }
        } message: {
            Text("Selected: " + selected.map(\.name).joined(separator: ", ") +
                 ". Homebrew will download these apps and may request your Mac password. Your current apps remain installed. Removing a newly installed app later is a separate step.\n\nCommands:\n" + selected.map(\.displayCommand).joined(separator: "\n"))
        }
        .alert("Setup needs attention", isPresented: Binding(
            get: { installer.errorMessage != nil },
            set: { if !$0 { installer.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { installer.errorMessage = nil }
        } message: { Text(installer.errorMessage ?? "") }
    }


    private var matchSection: some View {
        section(1, "Check the match") {
            ForEach(requiredFeatures, id: \.requirement.id) { feature in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: feature.state == .supported ? "checkmark.circle" : "exclamationmark.circle")
                        .frame(width: 18)
                        .foregroundStyle(feature.state == .supported ? Color.green : Color.orange)
                    Text(featureLabel(feature.requirement.id)).font(.callout)
                    Spacer(minLength: 8)
                    Text(coverageDescription(feature.state))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Coverage is based on the catalog. Try your own tasks before switching.")
                .font(.caption).foregroundStyle(.secondary)
            if plan.readiness == .incomplete {
                Label("Some selected requirements have gaps. Installation is unavailable for this setup.", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
            }
        }
    }

    private var readySection: some View {
        section(2, "See what's ready on your Mac") {
            Text("Use an app you have, or save this setup for later.")
                .font(.callout).foregroundStyle(.secondary)
            if !finishedAppScan {
                ProgressView("Checking installed app names…")
            } else {
                ForEach(plan.components.filter { $0.kind == .openSourceApp }, id: \.id) { component in
                    HStack(spacing: 8) {
                        Image(systemName: matchingInstalledApp(for: component) == nil ? "circle.dashed" : "checkmark.circle.fill")
                            .foregroundStyle(matchingInstalledApp(for: component) == nil ? Color.secondary : Color.green)
                        Text(component.name).font(.callout.weight(.medium))
                        Spacer(minLength: 8)
                        Text(matchingInstalledApp(for: component) == nil ? "Not detected on this Mac" : "Found on this Mac")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if plan.components.contains(where: { $0.kind == .builtInBridge || $0.kind == .macOSNative }) {
                Label("Included Mac or LibreReplace tools need no additional installation.", systemImage: "checkmark.circle")
                    .font(.callout)
            }
            if !items.isEmpty {
                DisclosureGroup("Install missing free apps (optional)", isExpanded: $showInstallOptions) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Nothing is selected or installed automatically. Choose any apps you actually want, review what happens, then approve installation separately.")
                            .font(.callout).foregroundStyle(.secondary)
                        if installer.checking {
                            ProgressView("Checking installation status…")
                        } else if !installer.homebrewAvailable {
                            Label("Homebrew isn't available. You can still explore this setup without it.", systemImage: "info.circle")
                                .font(.callout)
                            Text("If you choose to install later, Homebrew is a separate free package manager that needs your approval.")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("See official Homebrew instructions…") { openHomebrewInstaller() }
                                Button("Recheck Homebrew") { Task { await installer.check(items) } }
                                    .disabled(installer.checking || installer.isInstalling)
                            }
                        } else {
                            ForEach(items) { item in
                                Toggle(isOn: Binding(
                                    get: { selectedIDs.contains(item.id) },
                                    set: { value in
                                        if value { selectedIDs.insert(item.id) }
                                        else { selectedIDs.remove(item.id) }
                                    }
                                )) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(item.name).font(.callout.weight(.medium))
                                        if installer.installedIDs.contains(item.id) {
                                            Label("Already installed through Homebrew — will be left alone", systemImage: "checkmark.circle")
                                                .font(.caption).foregroundStyle(.green)
                                        } else if installer.checkedIDs.contains(item.id) {
                                            Text("Homebrew can download and install this free app if you approve.")
                                                .font(.caption).foregroundStyle(.secondary)
                                        } else {
                                            Text("Installation status needs checking first.")
                                                .font(.caption).foregroundStyle(.orange)
                                        }
                                        DisclosureGroup("Technical installation command") {
                                            Text(item.displayCommand).font(.caption.monospaced()).textSelection(.enabled)
                                        }.font(.caption)
                                    }
                                }
                                .toggleStyle(.checkbox)
                                .disabled(installer.isInstalling || installer.installedIDs.contains(item.id))
                            }
                            Text("Homebrew may download extra files, request Mac permissions or run third-party install scripts. LibreReplace will not remove your paid apps. There is no automatic uninstall or guaranteed rollback.")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("Recheck installation status") { Task { await installer.check(items) } }
                                    .disabled(installer.checking || installer.isInstalling)
                                Spacer()
                                Button("Review selected installations…") { showInstallConfirmation = true }
                                    .disabled(!canInstall)
                                    .buttonStyle(.borderedProminent)
                            }
                            if selected.isEmpty && !installer.isInstalling {
                                Text("Select an unchecked app above to enable installation. You can also skip this entirely.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if installer.isInstalling {
                            ProgressView("Installing approved software…")
                            Button(installer.stopAfterCurrent ? "Remaining installs will be skipped" : "Stop after current installation") {
                                installer.stopAfterCurrent = true
                            }.disabled(installer.stopAfterCurrent)
                            Text("A running Homebrew installation is allowed to finish before the queue stops.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(installer.messages, id: \.self) { message in
                            Label(message, systemImage: "info.circle").font(.callout)
                        }
                        if let history = installer.historyURL {
                            Button("Show local installation record") {
                                NSWorkspace.shared.activateFileViewerSelecting([history])
                            }
                        }
                    }
                    .padding(.top, 10)
                }
                .font(.callout.weight(.medium))
            }
        }
    }

    private var trySection: some View {
        section(3, "Try it out") {
            Text("Try a task with a sample file before relying on this setup.")
                .font(.callout).foregroundStyle(.secondary)
            if let route = StudioLocalToolRoute.forPlan(plan) {
                Button(route.buttonTitle) { saveAndOpenLocalTool(route) }
                    .buttonStyle(.borderedProminent)
                    .disabled(installer.isInstalling)
                Text(route.detail)
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(plan.components.filter { $0.kind == .openSourceApp }, id: \.id) { component in
                if let installed = matchingInstalledApp(for: component) {
                    Button("Open installed \(component.name)") {
                        NSWorkspace.shared.open(installed.path)
                    }
                    .buttonStyle(.bordered)
                    .help("Opens the exact locally detected application; the result must still be checked by you")
                } else if finishedAppScan {
                    Text("\(component.name) isn't installed. You can save this plan and try it later.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            if plan.components.contains(where: { $0.kind == .openSourceApp }) {
                Button("Refresh installed app list") { Task { await refreshInstalledApps() } }
                    .font(.caption)
            }
        }
    }

    private var recordSection: some View {
        section(4, "Record what worked") {
            Text("Check each task after you've tested it successfully.")
                .font(.callout).foregroundStyle(.secondary)
            Text("\(testedRequiredIDs.count) of \(requiredFeatures.count) required tasks checked")
                .font(.callout.weight(.medium))
            ForEach(requiredFeatures, id: \.requirement.id) { feature in
                Toggle(isOn: Binding(
                    get: { testedRequiredIDs.contains(feature.requirement.id) },
                    set: { successful in
                        if successful { testedRequiredIDs.insert(feature.requirement.id) }
                        else { testedRequiredIDs.remove(feature.requirement.id) }
                        savedTrial = nil
                    }
                )) {
                    Text(featureLabel(feature.requirement.id))
                }
                .toggleStyle(.checkbox)
                .disabled(!finishedAppScan || !missingDesktopApps.isEmpty)
            }
            if plan.components.count > 1 {
                Toggle("I tested a real result moving between these tools", isOn: Binding(
                    get: { testedHandoff },
                    set: { testedHandoff = $0; savedTrial = nil }
                ))
                .toggleStyle(.checkbox)
                .disabled(!finishedAppScan || !missingDesktopApps.isEmpty)
                Text("For multiple apps, both the tasks and the connection between apps must work.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let savedTrial {
                Label("Your self-reported test was saved on " +
                      savedTrial.testedAt.formatted(date: .abbreviated, time: .shortened),
                      systemImage: "checkmark.circle")
                    .font(.callout).foregroundStyle(.green)
                Button("Export community review notes…") { exportReviewNotes(savedTrial) }
            }
            Button("Save my tested result") { saveTrial() }
                .disabled(!canRecordTrial)
            Text(nextTrialStep)
                .font(.caption).foregroundStyle(.secondary)
            Text("Test notes stay on this Mac. Your files aren't stored with them.")
                .font(.caption).foregroundStyle(.secondary)
            if let trialMessage {
                Text(trialMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private var macOSMajor: Int {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    }

    private func coverageDescription(_ state: StudioCoverageState) -> String {
        switch state {
        case .supported: "Catalog-supported"
        case .partial: "Partly supported"
        case .unverified: "Unverified"
        case .missing: "Not covered"
        }
    }

    private func featureLabel(_ id: String) -> String {
        if id == "local-image-ocr" { return "On-device image OCR" }
        if let name = sourceApp?.capabilities.first(where: { $0.id == id })?.label { return name }
        return id.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private func loadTrial() {
        do {
            savedTrial = try StudioWorkflowTrialStore.matching(plan, macOSMajor: macOSMajor, in: support)
            testedRequiredIDs = savedTrial.map { Set($0.testedRequirementIDs) } ?? []
            testedHandoff = savedTrial?.interoperabilityConfirmed == true
        } catch {
            trialMessage = "Existing trial history needs attention: " + error.localizedDescription
        }
    }

    @discardableResult
    private func saveForLater() -> Bool {
        guard let sourceApp else {
            setupSaveMessage = "This setup cannot be saved without its original catalog entry."
            return false
        }
        let featureIDs = Set(requiredFeatures.map(\.requirement.id).filter { $0 != "local-image-ocr" })
        let saved = StudioSavedSetup(
            paidAppID: sourceApp.id,
            requiredFeatureIDs: featureIDs,
            componentIDs: plan.components.map(\.id),
            requiresLocalOCR: requiredFeatures.contains(where: { $0.requirement.id == "local-image-ocr" })
        )
        do {
            try StudioSavedSetupLibrary.add(saved, in: support)
            setupSaveMessage = "Saved in My Setups."
            return true
        } catch {
            setupSaveMessage = "Couldn't save this setup: " + error.localizedDescription
            return false
        }
    }

    private func saveAndOpenLocalTool(_ route: StudioLocalToolRoute) {
        guard let sourceApp, saveForLater() else { return }
        let mode: StudioWorkflowLabView.LabMode
        switch route.mode {
        case .extract: mode = .extract
        case .merge: mode = .merge
        case .searchable: mode = .searchable
        case .rescue: mode = .rescue
        case .convert: mode = .convert
        }
        state.beginLocalToolTrial(plan: plan, sourceApp: sourceApp, mode: mode)
        dismiss()
        onOpenLab()
    }

    private func saveTrial() {
        do {
            savedTrial = try StudioWorkflowTrialStore.recordSuccessfulTrial(
                for: plan, testedRequirementIDs: testedRequiredIDs,
                macOSMajor: macOSMajor, interoperabilityConfirmed: testedHandoff, in: support)
            trialMessage = "Test results saved for this setup."
        } catch {
            trialMessage = "Could not save the trial: " + error.localizedDescription
        }
    }

    private func exportReviewNotes(_ record: StudioWorkflowTrial) {
        do {
            let content = try StudioCommunityReviewNotes.render(plan: plan, trial: record,
                sourceAppName: sourceApp?.name ?? "Selected paid workflow")
            let panel = NSSavePanel()
            panel.title = "Export community review notes"
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue = "LibreReplace-review-notes.txt"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            let bytes = Data(content.utf8)
            try bytes.write(to: url, options: .atomic)
            guard try Data(contentsOf: url) == bytes else { throw CocoaError(.fileWriteUnknown) }
            trialMessage = "Saved review notes. Attach them with the separately exported recipe for human review."
        } catch {
            trialMessage = "Could not export review notes: " + error.localizedDescription
        }
    }

    private func refreshInstalledApps() async {
        // The scanner reads installed app-bundle metadata only; no document scan.
        let result = await Task.detached(priority: .utility) {
            AppScanner().scan()
        }.value
        installedDesktopApps = result
        finishedAppScan = true
    }

    private func matchingInstalledApp(for component: StudioComponent) -> InstalledApplication? {
        // Only launch an unambiguous app with an exact displayed name or bundle
        // filename match. Never guess based on an approximate search result.
        let matches = installedDesktopApps.filter { app in
            app.name.caseInsensitiveCompare(component.name) == .orderedSame ||
            app.path.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(component.name) == .orderedSame
        }
        return matches.count == 1 ? matches.first : nil
    }

    private func openHomebrewInstaller() {
        // Homebrew's official graphical .pkg is available for Apple Silicon.
        // Intel users get the official instructions, not an incompatible .pkg.
        #if arch(arm64)
        let address = "https://github.com/Homebrew/brew/releases/latest"
        #else
        let address = "https://brew.sh/"
        #endif
        if let url = URL(string: address) { NSWorkspace.shared.open(url) }
    }

    private func section<Content: View>(_ number: Int, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Text("\(number)").font(.headline)
                    .frame(width: 26, height: 26)
                    .background(Color.accentColor.opacity(0.13), in: Circle())
                Text(title).font(.title3.bold())
            }
            VStack(alignment: .leading, spacing: 8) { content() }
                .padding(.leading, 36)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
