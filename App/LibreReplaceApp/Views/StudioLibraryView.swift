import SwiftUI

/// Saved setups and community recipes are one library with two focused views.
struct StudioLibraryView: View {
    @Binding var showRecipes: Bool
    let onExplore: () -> Void
    let onBuild: (String) -> Void
    let onOpenLab: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker("Library", selection: $showRecipes) {
                Text("Setups").tag(false)
                Text("Recipes").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 310)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .accessibilityLabel("Choose saved setups or community recipes")

            Group {
                if showRecipes {
                    StudioRecipesView(onOpenComposer: onExplore, onOpenLab: onOpenLab)
                } else {
                    StudioFreeTwinsView(onExplore: onExplore,
                        onBuild: onBuild, onOpenLab: onOpenLab)
                }
            }
        }
        .navigationTitle("My Setups")
    }
}
