import Combine
import AppKit
import Foundation
import LibreReplaceCore

@MainActor
final class InstallCoordinator: ObservableObject {
    @Published var isRunning = false
    @Published var resultMessage: String?

    func execute(_ action: InstallAction) async {
        isRunning = true
        defer { isRunning = false }
        switch action {
        case .openURL(let url):
            let opened = NSWorkspace.shared.open(url)
            resultMessage = opened ? "Opened the official installation page." : "macOS could not open the installation page."
        case .homebrew(let candidates, let arguments, let displayCommand):
            let executor = HomebrewExecutor(executableCandidates: candidates)
            guard executor.resolvedExecutable() != nil else {
                resultMessage = "Homebrew was not found in /opt/homebrew/bin or /usr/local/bin. No command was run."
                return
            }
            let result = await Task.detached(priority: .userInitiated) {
                executor.run(arguments: arguments)
            }.value
            let status = result?.terminationStatus ?? -1
            resultMessage = status == 0 ? "Completed: \(displayCommand)" : "Homebrew exited with status \(status). No existing app was removed."
        }
    }
}
