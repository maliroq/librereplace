import SwiftUI
import LibreReplaceCore

struct MigrationCard: View {
    @State private var plan: MigrationPlan?
    @State private var receipt: MigrationReceipt?
    @State private var errorMessage: String?
    @State private var confirmApply = false
    @State private var confirmRollback = false
    private let adapter = SublimeToZedMigration()

    var body: some View {
        GroupBox("Optional migration · Sublime Text → Zed") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Only four non-sensitive editor preferences are supported. LibreReplace does not read projects, recent files, snippets, credentials, Keychain data, or document contents.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button("Preview migration") { preview() }
                    .accessibilityHint("Reads only the supported Sublime Text preference file and shows proposed Zed setting changes")

                if let plan {
                    Divider()
                    Text("Proposed changes")
                        .font(.headline)
                    ForEach(plan.changes, id: \.key) { change in
                        LabeledContent(change.key) {
                            Text("\(change.fromValue ?? "not set") → \(change.toValue)")
                                .textSelection(.enabled)
                        }
                    }
                    ForEach(plan.warnings, id: \.self) {
                        Label($0, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Apply after backup…") { confirmApply = true }
                        .disabled(plan.changes.isEmpty)
                }

                if let receipt {
                    if let backupPath = receipt.backupPath {
                        Label("Verified backup created", systemImage: "checkmark.shield")
                            .font(.caption.weight(.semibold))
                        Text(backupPath.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else {
                        Text("Applied. The target file did not previously exist; rollback will remove the file LibreReplace created.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Rollback…", role: .destructive) { confirmRollback = true }
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .confirmationDialog("Apply this migration?", isPresented: $confirmApply, titleVisibility: .visible) {
            Button("Back up and apply") { apply() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("LibreReplace will back up the existing Zed settings file if present, then change only the previewed keys. No Sublime Text files will be deleted.")
        }
        .confirmationDialog("Roll back this migration?", isPresented: $confirmRollback, titleVisibility: .visible) {
            Button("Restore previous state", role: .destructive) {
                if let receipt { rollback(receipt) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Rollback restores the target to its state before this LibreReplace migration. Any edits made to that target after migration may be replaced.")
        }
    }

    private func preview() {
        do {
            plan = try adapter.preview(home: FileManager.default.homeDirectoryForCurrentUser, fileManager: .default)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply() {
        guard let plan else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let backupRoot = home.appendingPathComponent("Library/Application Support/LibreReplace/Backups", isDirectory: true)
        do {
            receipt = try adapter.apply(plan: plan, home: home, backupRoot: backupRoot, fileManager: .default)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rollback(_ receipt: MigrationReceipt) {
        do {
            try adapter.rollback(receipt: receipt, home: FileManager.default.homeDirectoryForCurrentUser, fileManager: .default)
            self.receipt = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
