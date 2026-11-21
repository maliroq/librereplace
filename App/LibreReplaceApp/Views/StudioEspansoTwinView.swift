import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LibreReplaceCore

/// A real, reversible consumer Free Twin: exported static snippets become
/// installed Espanso matches, not just a report or a downloadable template.
struct StudioEspansoTwinView: View {
    @StateObject private var installer = StudioSwitchCoordinator()
    @State private var trial: StudioEspansoPreview?
    @State private var receipt: StudioEspansoReceipt?
    @State private var error: String?
    @State private var note: String?
    @State private var busy = false
    @State private var approveSetup = false
    @State private var approveUndo = false
    @State private var approveInstall = false
    @State private var testText = ""
    @State private var issueLimit = 25
    @State private var manualConfigRoot: URL?
    @State private var isExpanded = false

    private let espansoPackage = StudioApprovedInstall(componentID: "espanso", name: "Espanso",
        package: "espanso", kind: .homebrewCask)
    private var support: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0] }
    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    private var appURL: URL? {
        // Launch Services also finds installations outside the usual app folders.
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.espanso.Espanso") ??
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.espanso.Espanso") ??
        [URL(fileURLWithPath: "/Applications/Espanso.app"),
         home.appendingPathComponent("Applications/Espanso.app")]
        .first(where: { FileManager.default.fileExists(atPath: $0.path) })
    }
    private var appInstalled: Bool { appURL != nil || installer.installedIDs.contains("espanso") }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top, spacing: 12) {
                    AppArtwork(name: "Espanso", size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("TextExpander → Espanso").font(.title2.bold())
                        Text("Bring your shortcuts to a free text expander. Keep your original snippets and start typing.")
                            .foregroundStyle(.secondary).font(.callout)
                    }
                    Spacer()
                    if receipt != nil {
                        Label("Prepared", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    } else {
                        Button(isExpanded ? "Close" : "Set up text expansion") { isExpanded.toggle() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                if isExpanded || receipt != nil {
                if let receipt {
                    Label("\(receipt.installedCount) expansions ready · \(receipt.excludedCount) excluded for review",
                          systemImage: "text.badge.checkmark")
                        .font(.callout)
                    HStack(spacing: 10) {
                        Button("Open Espanso") { launchEspanso() }
                            .buttonStyle(.borderedProminent).disabled(appURL == nil)
                        Button("Show saved expansions") {
                            NSWorkspace.shared.activateFileViewerSelecting([receipt.generatedFile])
                        }
                        Button("Check setup") { verify() }
                        Button("Undo setup…", role: .destructive) { approveUndo = true }
                    }
                    TextField("Test a shortcut here after opening Espanso", text: $testText)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Test your imported text expansion shortcuts")
                } else {
                    if let trial {
                        HStack(spacing: 15) {
                            Label("\(trial.ready) ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("\(trial.needsReview) need review · \(trial.blocked) incompatible")
                                .foregroundStyle(.secondary)
                        }.font(.callout)
                        if trial.needsReview + trial.blocked > 0 {
                            DisclosureGroup("Review skipped snippets") {
                                let problems = trial.trial.findings.filter { !$0.isExportable }
                                ForEach(Array(problems.prefix(issueLimit))) { item in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.trigger.isEmpty ? "(empty shortcut)" : item.trigger)
                                            .font(.callout.weight(.medium))
                                        Text(item.reasons.joined(separator: "; "))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }.padding(.vertical, 3)
                                }
                                if problems.count > issueLimit {
                                    Button("Show 25 more of \(problems.count) skipped") {
                                        issueLimit = min(problems.count, issueLimit + 25)
                                    }
                                }
                            }
                        }
                        HStack {
                            Button("Choose different exports") { chooseCSV() }
                            Button("Create my free setup…") { approveSetup = true }
                                .buttonStyle(.borderedProminent)
                                .disabled(trial.ready == 0 || busy || !appInstalled)
                            if !appInstalled {
                                Text("Install Espanso below to enable this setup.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Select one or more exported TextExpander CSV groups. LibreReplace combines the compatible shortcuts and prevents duplicates.")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Button("Choose TextExpander CSV files…") { chooseCSV() }
                                .buttonStyle(.borderedProminent)
                            Link("How to export", destination: URL(string: "https://textexpander.com/learn/using/importing-and-exporting-snippet-groups")!)
                        }
                    }
                }
                HStack {
                    if let manualConfigRoot {
                        Text("Espanso folder: \(manualConfigRoot.lastPathComponent)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Choose Espanso folder…") { chooseConfigRoot() }
                        .font(.caption)
                }
                if !appInstalled {
                    Divider()
                    HStack {
                        Text("Espanso isn't installed yet.")
                        Spacer()
                        if installer.checking { ProgressView().controlSize(.small) }
                        else if installer.homebrewAvailable {
                            Button("Install Espanso…") { approveInstall = true }
                                .disabled(installer.isInstalling || busy)
                        } else {
                            Link("Get Espanso", destination: URL(string: "https://espanso.org/docs/install/mac/")!)
                        }
                    }.font(.callout)
                }
                if busy || installer.isInstalling { ProgressView("Preparing your free setup…") }
                if let note { Label(note, systemImage: "info.circle").font(.callout).textSelection(.enabled) }
                if let error { Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.red).textSelection(.enabled) }
                if let message = installer.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red)
                }
                }
            }.padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { load(); await installer.check([espansoPackage]) }
        .confirmationDialog("Create your Espanso setup?", isPresented: $approveSetup) {
            Button("Create and verify setup") { prepare() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("LibreReplace will add a new Espanso match file with the compatible static shortcuts. Existing matches and TextExpander data will not change.")
        }
        .confirmationDialog("Undo this Espanso setup?", isPresented: $approveUndo) {
            Button("Remove LibreReplace expansions", role: .destructive) { undo() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only the matching file LibreReplace created will be removed. Edited files are preserved.")
        }
        .confirmationDialog("Install Espanso through Homebrew?", isPresented: $approveInstall) {
            Button("Install Espanso") { Task { await installer.install([espansoPackage]) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Install the free Espanso application using brew install --cask espanso. Homebrew may request permission for its installer.")
        }
    }

    private func load() {
        do { receipt = try StudioEspansoTwin.load(in: support); error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func chooseCSV() {
        let panel = NSOpenPanel()
        panel.title = "Choose a TextExpander CSV export"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls
        busy = true; note = nil; error = nil
        let root: URL
        do { root = try manualConfigRoot ?? StudioEspansoTwin.preferredConfigRoot(home: home) }
        catch { busy = false; self.error = error.localizedDescription; return }
        Task {
            defer { busy = false }
            do {
                let value = try await Task.detached(priority: .userInitiated) {
                    try StudioEspansoTwin.preview(csvs: urls, configRoot: root)
                }.value
                trial = value
                note = "\(value.total) shortcuts across \(urls.count) exports. Compatible, nonconflicting shortcuts are ready."
            } catch { self.error = error.localizedDescription }
        }
    }

    private func chooseConfigRoot() {
        let panel = NSOpenPanel()
        panel.title = "Select the Espanso configuration folder (containing match and config)"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        manualConfigRoot = url
        trial = nil // Old plans must never be written to a newly selected folder.
        note = "Espanso folder selected. Choose your CSV exports again to prepare the setup."
    }

    private func prepare() {
        guard let trial, !busy else { return }
        busy = true; note = nil; error = nil
        let support = self.support
        Task {
            defer { busy = false }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try StudioEspansoTwin.prepare(trial, approved: true, applicationSupport: support)
                }.value
                receipt = result
                self.trial = nil
                note = "\(result.installedCount) shortcuts saved in Espanso. Open it and try one below."
            } catch { self.error = error.localizedDescription }
        }
    }

    private func undo() {
        guard let receipt, !busy else { return }
        busy = true; note = nil; error = nil
        let support = self.support
        Task {
            defer { busy = false }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try StudioEspansoTwin.undo(receipt, applicationSupport: support)
                }.value
                self.receipt = nil
                note = "LibreReplace's expansions were removed. Your existing Espanso matches were untouched."
            } catch { self.error = error.localizedDescription }
        }
    }

    private func verify() {
        guard let receipt else { return }
        do {
            note = try StudioEspansoTwin.verify(receipt)
                ? "The generated expansion configuration matches the saved setup. Try an imported shortcut in Espanso."
                : "The generated file is missing or has changed; it was not modified."
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func launchEspanso() {
        guard let appURL else { error = "Espanso is not installed. Install it first."; return }
        if !NSWorkspace.shared.open(appURL) { error = "macOS could not open Espanso." }
    }
}
