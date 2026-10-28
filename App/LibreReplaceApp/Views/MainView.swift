import SwiftUI

struct MainView: View {
    enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case detected = "Detected"
        case catalog = "Catalog"
        case privacy = "Privacy"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .overview: "gauge.with.dots.needle.50percent"
            case .detected: "square.stack.3d.up"
            case .catalog: "checklist"
            case .privacy: "hand.raised"
            }
        }
    }

    @EnvironmentObject private var state: AppState
    @State private var selection: Section? = .overview

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationTitle("LibreReplace")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 250)
        } detail: {
            NavigationStack {
                Group {
                    switch selection ?? .overview {
                    case .overview: OverviewView()
                    case .detected: DetectedAppsView()
                    case .catalog: CatalogView()
                    case .privacy: PrivacyView()
                    }
                }
            }
            // A recommendation is pushed from the Detected section. Rebuild the
            // section-local stack when the sidebar changes so a pushed detail
            // cannot remain above a newly selected top-level section.
            .id((selection ?? .overview).rawValue)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await state.scan() }
                    } label: {
                        Label(state.isScanning ? "Scanning…" : "Scan Applications", systemImage: "arrow.clockwise")
                    }
                    .disabled(state.isScanning || state.catalog == nil)
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Scan standard application folders again")
                    .accessibilityLabel(state.isScanning ? "Scanning applications" : "Scan applications")
                }
            }
            .alert("LibreReplace", isPresented: Binding(
                get: { state.errorMessage != nil },
                set: { if !$0 { state.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { state.errorMessage = nil }
            } message: {
                Text(state.errorMessage ?? "")
            }
        }
    }
}
