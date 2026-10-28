import SwiftUI

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Privacy by construction").font(.largeTitle.bold())
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("No account, telemetry, analytics, ads, or remote inventory upload.", systemImage: "checkmark.shield")
                        Label("The scanner reads app bundle metadata from application directories — not your documents.", systemImage: "folder.badge.gearshape")
                        Label("Installation always requires confirmation and never uninstalls the source app.", systemImage: "hand.raised")
                        Label("Migration is preview-first, narrowly scoped, backup-verified, and rollback-capable.", systemImage: "arrow.uturn.backward.circle")
                        Label("The default exported report contains aggregate counts only.", systemImage: "doc.text")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                }
                Text("LibreReplace deliberately avoids Keychain, browser credentials, passwords, private documents, browser profiles, and full user-library crawling in v0.1.")
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(maxWidth: 850, alignment: .leading)
        }
        .navigationTitle("Privacy")
    }
}
