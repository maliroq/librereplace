import Foundation
import Combine
import LibreReplaceCore

/// A foreground, explicitly approved installer. Nothing runs on view creation.
/// Reads installed state with Homebrew; changes only the exact reviewed packages.
@MainActor
final class StudioSwitchCoordinator: ObservableObject {
    @Published private(set) var checking = false
    @Published private(set) var isInstalling = false
    @Published private(set) var preflightReady = false
    @Published private(set) var homebrewAvailable = false
    @Published private(set) var installedIDs: Set<String> = []
    @Published private(set) var checkedIDs: Set<String> = []
    @Published private(set) var messages: [String] = []
    @Published private(set) var historyURL: URL?
    @Published var errorMessage: String?
    @Published var stopAfterCurrent = false

    private let executor = HomebrewExecutor()
    private var journal = StudioInstallJournal()
    private var preflight: StudioInstallPreflight?

    func check(_ items: [StudioApprovedInstall]) async {
        guard !checking && !isInstalling else { return }
        checking = true
        defer { checking = false }
        preflightReady = false
        preflight = nil
        homebrewAvailable = false
        errorMessage = nil
        installedIDs = []
        checkedIDs = []
        guard executor.resolvedExecutable() != nil else { return }
        let executor = self.executor
        let status = await Task.detached(priority: .userInitiated) { executor.run(arguments: ["--version"]) }.value
        guard status?.terminationStatus == 0 else {
            errorMessage = "Homebrew needs attention. Open the official Homebrew installer or check your existing installation, then try again."
            return
        }
        homebrewAvailable = true
        for item in items {
            let check = await Task.detached(priority: .userInitiated) {
                executor.run(arguments: item.installedCheckArguments)
            }.value
            guard let check, check.terminationStatus == 0 || check.terminationStatus == 1 else {
                errorMessage = "Could not reliably check whether \(item.name) is installed. No changes were made."
                return
            }
            checkedIDs.insert(item.id)
            if check.terminationStatus == 0 { installedIDs.insert(item.id) }
        }
        // One exact package list, checked recently. The user may select any
        // subset of those packages but cannot swap the payload after checking.
        guard let receipt = StudioInstallPreflight(items: items) else {
            errorMessage = "This setup's installation list could not be reviewed safely. No changes were made."
            return
        }
        preflight = receipt
        preflightReady = true
    }

    func install(_ items: [StudioApprovedInstall]) async {
        guard preflightReady, !isInstalling, !checking, !items.isEmpty else { return }
        guard let receipt = preflight, receipt.permits(items),
              items.allSatisfy({ checkedIDs.contains($0.id) && !installedIDs.contains($0.id) }) else {
            preflightReady = false
            preflight = nil
            errorMessage = "The installation list changed or its safety check expired. Check the apps again before proceeding."
            return
        }
        // A preflight cannot authorize a second installation session.
        preflightReady = false
        preflight = nil
        isInstalling = true
        stopAfterCurrent = false
        defer { isInstalling = false }
        journal = StudioInstallJournal()
        messages = []
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let support else {
            errorMessage = "Unable to find local application storage. No installation was started."
            return
        }
        do {
            for item in items {
                journal.append(.init(componentID: item.id, package: item.package,
                                     state: .planned, message: "User approved the listed Homebrew package."))
            }
            historyURL = try StudioInstallJournalStore.save(journal, in: support)
        } catch {
            errorMessage = "Could not save the installation record. No software was changed: \(error.localizedDescription)"
            return
        }
        let executor = self.executor
        for item in items {
            if stopAfterCurrent {
                journal.append(.init(componentID: item.id, package: item.package, state: .skipped,
                                     message: "User stopped the queue before this installation."))
                do { historyURL = try StudioInstallJournalStore.save(journal, in: support) }
                catch { errorMessage = "Could not update installation record: \(error.localizedDescription)" }
                continue
            }
            // Recheck immediately before the install, so preexisting packages
            // are never reinstalled by a stale UI state.
            let before = await Task.detached(priority: .userInitiated) {
                executor.run(arguments: item.installedCheckArguments)
            }.value
            guard let before, before.terminationStatus == 0 || before.terminationStatus == 1 else {
                errorMessage = "Could not reliably check \(item.name). Remaining installations were stopped."
                break
            }
            if before.terminationStatus == 0 {
                installedIDs.insert(item.id)
                journal.append(.init(componentID: item.id, package: item.package,
                                     state: .alreadyInstalled, message: "Already installed; left unchanged."))
                messages.append("\(item.name) was already installed. Nothing changed.")
                do { historyURL = try StudioInstallJournalStore.save(journal, in: support) }
                catch { errorMessage = "Could not update the installation record: \(error.localizedDescription)"; break }
                continue
            }
            journal.append(.init(componentID: item.id, package: item.package,
                                 state: .installing, message: "Started \(item.displayCommand)"))
            do { historyURL = try StudioInstallJournalStore.save(journal, in: support) }
            catch { errorMessage = "Could not record installation start: \(error.localizedDescription)"; break }

            // Typed arguments, explicit executable, no shell or recipe execution.
            let completed = await Task.detached(priority: .userInitiated) {
                executor.run(arguments: item.arguments)
            }.value
            let success = completed?.terminationStatus == 0
            let state: StudioInstallEventState = success ? .installSucceeded : .installFailed
            let note = success ? "Homebrew returned success; functional test still needed." :
                "Homebrew returned \(completed?.terminationStatus ?? -1); installation may be incomplete."
            journal.append(.init(componentID: item.id, package: item.package, state: state, message: note))
            do { historyURL = try StudioInstallJournalStore.save(journal, in: support) }
            catch { errorMessage = "Could not update the installation record: \(error.localizedDescription)"; break }
            messages.append("\(item.name): \(note)")
            if !success {
                errorMessage = "Installation of \(item.name) did not finish successfully. Check Homebrew before retrying. No uninstall or automatic rollback was performed."
                break
            }
            // Verify Homebrew's installed registry separately from exit status.
            let verify = await Task.detached(priority: .userInitiated) {
                executor.run(arguments: item.installedCheckArguments)
            }.value
            if verify?.terminationStatus == 0 {
                installedIDs.insert(item.id)
                journal.append(.init(componentID: item.id, package: item.package, state: .installVerified,
                                     message: "Homebrew confirms package installed. User workflow still needs testing."))
            } else {
                journal.append(.init(componentID: item.id, package: item.package, state: .verificationFailed,
                                     message: "Homebrew did not confirm installed package after successful install exit."))
            }
            do { historyURL = try StudioInstallJournalStore.save(journal, in: support) }
            catch { errorMessage = "Could not save the verification record: \(error.localizedDescription)"; break }
            if verify?.terminationStatus != 0 {
                messages.append("\(item.name) could not be confirmed in Homebrew's installed list.")
                errorMessage = "Homebrew finished but \(item.name) was not confirmed installed. Review the installation before continuing."
                break
            }
        }
    }
}
