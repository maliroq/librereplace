import AppKit
import SwiftUI
import LibreReplaceCore

struct AlternativeCard: View {
    let sourceApp: PaidApplication
    let ranked: RankedAlternative
    @EnvironmentObject private var state: AppState
    @StateObject private var installer = InstallCoordinator()
    @State private var confirmInstall = false
    @State private var installAction: InstallAction?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ranked.alternative.name)
                            .font(.title2.bold())
                            .lineLimit(2)
                        Text(ranked.alternative.license)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Text("\(Int((ranked.coverage * 100).rounded()))% of selected essentials")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if let projectURL = URL(string: ranked.alternative.homepageURL) {
                        Link("Project", destination: projectURL)
                    }
                }

                Text("Selected-essential coverage is not overall feature parity. Review all capability losses below.")
                    .font(.caption).foregroundStyle(.secondary)
                FeatureSection(title: "Keeps", symbol: "checkmark.circle", tint: .green, capabilities: ranked.kept,
                               requiredIDs: state.requiredFeatureIDs(for: sourceApp))
                FeatureSection(title: "Partial", symbol: "circle.lefthalf.filled", tint: .orange, capabilities: ranked.partial,
                               requiredIDs: state.requiredFeatureIDs(for: sourceApp))
                FeatureSection(title: "Missing", symbol: "xmark.circle", tint: .red, capabilities: ranked.missing,
                               requiredIDs: state.requiredFeatureIDs(for: sourceApp))

                if !ranked.alternative.limitations.isEmpty {
                    Divider()
                    Text("Known limitations")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(ranked.alternative.limitations, id: \.self) { limitation in
                            Text("• \(limitation)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(alignment: .firstTextBaseline) {
                    Button(installer.isRunning ? "Installing…" : installButtonTitle) {
                        prepareInstall()
                    }
                    .disabled(installer.isRunning || InstallActionBuilder.action(for: ranked.alternative.install) == nil)
                    .accessibilityHint("LibreReplace will ask for confirmation before opening or running anything")
                    if let message = installer.resultMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }

                if ranked.alternative.migrationAdapter == "sublime-to-zed-settings-v1" {
                    MigrationCard()
                }

                DisclosureGroup("Evidence") {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(ranked.alternative.evidence, id: \.url) { item in
                            if let url = URL(string: item.url) {
                                Link("\(item.title) · verified \(item.lastVerified)", destination: url)
                            }
                        }
                        ForEach(sourceApp.evidence, id: \.url) { item in
                            if let url = URL(string: item.url) {
                                Link("\(item.title) · verified \(item.lastVerified)", destination: url)
                            }
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .padding(.vertical, 6)
        }
        .confirmationDialog("Install \(ranked.alternative.name)?", isPresented: $confirmInstall, titleVisibility: .visible) {
            Button("Continue") {
                if let installAction {
                    Task { await installer.execute(installAction) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(installConfirmationText)
        }
    }

    private var installButtonTitle: String {
        switch ranked.alternative.install.kind {
        case .homebrewCask, .homebrewFormula: "Install with Homebrew…"
        default: "Open official download…"
        }
    }

    private var installConfirmationText: String {
        var text: String
        if case .homebrew(_, _, let command) = installAction {
            text = "LibreReplace will run exactly: \(command). It will not uninstall \(sourceApp.name)."
        } else {
            text = "LibreReplace will open the catalog-listed download page in your browser. Check its publisher and pricing before installing. It will not uninstall \(sourceApp.name)."
        }
        if let warning = ranked.alternative.install.warning {
            text += " Warning: \(warning)"
        }
        return text
    }

    private func prepareInstall() {
        installAction = InstallActionBuilder.action(for: ranked.alternative.install)
        confirmInstall = installAction != nil
    }
}

private struct FeatureSection: View {
    let title: String
    let symbol: String
    let tint: Color
    let capabilities: [Capability]
    let requiredIDs: Set<String>

    var body: some View {
        if !capabilities.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                ForEach(capabilities, id: \.id) { cap in
                    Label {
                        Text(cap.label + (requiredIDs.contains(cap.id) ? " (required)" : ""))
                    } icon: {
                        Image(systemName: symbol).foregroundStyle(tint)
                    }
                }
            }
        }
    }
}
