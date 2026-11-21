import SwiftUI

/// Five distinct destinations: discover, use, create, share, and manage.
/// There is only one application discovery/composition flow.
struct MainView: View {
    enum SidebarPage: String, CaseIterable, Identifiable {
        case discover = "Discover"
        case setups = "My Setups"
        case tools = "Tools"
        case community = "Community"
        case mac = "My Mac"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .discover: "square.grid.2x2"
            case .setups: "square.stack.3d.up"
            case .tools: "wand.and.stars"
            case .community: "person.3.sequence"
            case .mac: "desktopcomputer"
            }
        }
    }

    @EnvironmentObject private var state: AppState
    @State private var selection: SidebarPage? = .discover
    @State private var requestedLabMode: StudioWorkflowLabView.LabMode = .extract
    @State private var returnToSetup: StudioToolContinuation?

    private func explore(_ query: String = "") {
        state.requestedExploreQuery = query
        if !query.isEmpty, let match = state.catalog?.apps.first(where: { app in
            ([app.name, app.vendor] + app.nameAliases + app.alternatives.map(\.name))
                .contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }) { state.requestedComposerAppID = match.id }
        selection = .discover
    }

    private func build(_ id: String) {
        state.requestedExploreQuery = ""
        state.requestedComposerAppID = id
        selection = .discover
    }

    private func openTools(_ mode: StudioWorkflowLabView.LabMode = .extract) {
        requestedLabMode = state.requestedLocalToolMode ?? mode
        if state.requestedLocalToolMode == nil { state.toolContinuation = nil }
        state.requestedLocalToolMode = nil
        selection = .tools
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(SidebarPage.allCases) { page in
                        Label(page.rawValue, systemImage: page.icon)
                            .tag(page)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("LibreReplace")
            .navigationSplitViewColumnWidth(min: 164, ideal: 190, max: 232)
        } detail: {
            NavigationStack {
                Group {
                    switch selection ?? .discover {
                    case .discover:
                        StudioReplaceView(
                            onOpenLab: { openTools() },
                            onOpenPDFRescue: { openTools(.rescue) },
                            onOpenRecipes: { selection = .community })
                    case .setups:
                        StudioFreeTwinsView(
                            onExplore: { selection = .discover },
                            onBuild: build,
                            onOpenLab: { openTools() })
                    case .tools:
                        VStack(spacing: 0) {
                            if let visit = state.toolContinuation {
                                HStack(spacing: 12) {
                                    Image(systemName: "arrow.uturn.backward.circle")
                                        .foregroundStyle(.secondary)
                                    Text("Testing a setup for \(visit.sourceApp.name)")
                                        .font(.callout)
                                    Spacer(minLength: 8)
                                    Button("Return to setup") { returnToSetup = visit }
                                        .buttonStyle(.borderedProminent)
                                    Button("Finish") { state.toolContinuation = nil }
                                        .buttonStyle(.bordered)
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 11)
                                .background(Color.secondary.opacity(0.07))
                            }
                            StudioWorkflowLabView(
                                initialMode: requestedLabMode,
                                imageOnly: state.toolContinuation?.plan.components.contains { $0.id == "bridge.image-ocr" } == true
                            )
                        }
                    case .community:
                        StudioRecipesView(onOpenComposer: { selection = .discover },
                            onOpenLab: { openTools() })
                    case .mac:
                        StudioMyMacView()
                    }
                }
            }
            .id((selection ?? .discover).rawValue)
            .sheet(item: $returnToSetup) { visit in
                StudioGuidedSwitchView(plan: visit.plan, sourceApp: visit.sourceApp,
                    onOpenLab: { openTools() })
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await state.scan() }
                    } label: {
                        Label(state.isScanning ? "Scanning…" : "Scan Applications", systemImage: "arrow.clockwise")
                    }
                    .disabled(state.isScanning || state.catalog == nil)
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Rescan your installed applications")
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
