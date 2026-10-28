import SwiftUI

@main
struct LibreReplaceApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(state)
                .frame(minWidth: 980, minHeight: 680)
                .task { await state.start() }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1120, height: 760)
    }
}
