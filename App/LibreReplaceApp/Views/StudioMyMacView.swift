import SwiftUI

/// Keep system information together rather than scattering it through menus.
/// These are working existing views, not duplicate recommendation flows.
struct StudioMyMacView: View {
    @EnvironmentObject private var state: AppState
    @State private var section: MacSection = .installed

    private enum MacSection: String, CaseIterable, Identifiable {
        case installed = "Installed"
        case savings = "Savings"
        case evidence = "Evidence"
        case privacy = "Privacy"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Mac")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Your applications, replacement progress, and preferences.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if state.isScanning {
                    ProgressView().controlSize(.small)
                }
                Button("Scan apps", systemImage: "arrow.clockwise") {
                    Task { await state.scan() }
                }
                .disabled(state.isScanning || state.catalog == nil)
            }
            HStack(spacing: 10) {
                Label("\(state.installed.count) apps", systemImage: "square.grid.2x2")
                Divider().frame(height: 14)
                Label("\(state.recommendations.count) catalog matches", systemImage: "checkmark.circle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Picker("My Mac section", selection: $section) {
                ForEach(MacSection.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Choose information about your Mac")

            Group {
                switch section {
                case .installed: DetectedAppsView()
                case .savings: OverviewView()
                case .evidence: CatalogView()
                case .privacy: PrivacyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 8)
        .navigationTitle("My Mac")
    }
}
