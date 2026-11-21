import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers
import LibreReplaceCore

/// Multi-stage native workflow: scanned PDF -> local OCR -> positioned text ->
/// checked, newly saved searchable PDF. Never edits the input document.
struct StudioSearchablePDFView: View {
    @State private var sourceFiles: [URL] = []
    @State private var outputFolder: URL?
    @State private var completedFiles: [StudioSearchablePDFOutput] = []
    @State private var running = false
    @State private var message = ""
    @State private var errors: [String] = []
    @State private var active: Task<StudioSearchablePDFOutput, Error>?
    @StateObject private var progress = StudioSearchablePDFProgress()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Make PDFs searchable")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Find words and select text in scanned PDFs. LibreReplace reads each page locally, adds a searchable text layer and saves a new PDF.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.title).foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Select scanned PDFs").font(.headline)
                            Text("Choose up to 8 PDFs. Original files stay in place.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 12) {
                        Button { choosePDFs() } label: {
                            Label("Choose PDFs…", systemImage: "plus")
                        }.disabled(running)
                        Text(sourceFiles.isEmpty ? "No files selected" : "\(sourceFiles.count) selected")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Button { start() } label: {
                            Label("Make searchable…", systemImage: "text.magnifyingglass")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(running || sourceFiles.isEmpty)
                        if running {
                            Button("Stop") { active?.cancel(); progress.stopRequested = true }
                        }
                    }
                    if !sourceFiles.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(sourceFiles, id: \.self) { url in
                                Label(url.lastPathComponent, systemImage: "doc.richtext")
                                    .lineLimit(1).truncationMode(.middle)
                            }
                        }
                        .font(.callout)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background, in: RoundedRectangle(cornerRadius: 10))
                    }
                    if running {
                        ProgressView(value: Double(progress.page), total: Double(max(1, progress.total)))
                        Text("File \(progress.fileIndex) of \(sourceFiles.count) · Page \(progress.page) of \(progress.total)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Handles up to 500 pages and 150 MB per PDF. Password-protected, annotated and rotated PDFs need a different workflow to preserve their content correctly.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                if !message.isEmpty {
                    Label(message, systemImage: completedFiles.isEmpty ? "info.circle" : "checkmark.circle")
                        .font(.callout)
                }
                if !errors.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Files needing attention", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                        ForEach(errors, id: \.self) { Text($0).font(.callout) }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                if completedFiles.isEmpty && !running && message.isEmpty {
                    StudioCompactEmptyState(
                        title: "Searchable PDFs will appear here",
                        systemImage: "doc.text.magnifyingglass",
                        message: "Select a scanned PDF, then choose where to save the new version."
                    )
                }
                if !completedFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Created PDFs").font(.title2.bold())
                            Spacer()
                            Button("Show in Finder", systemImage: "folder") { reveal() }
                        }
                        ForEach(completedFiles, id: \.filename) { output in
                            HStack(spacing: 10) {
                                Image(systemName: "doc.text").foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(output.filename).lineLimit(1).truncationMode(.middle)
                                    Text("\(output.pageCount) pages · \(output.newlySearchablePages) scanned pages made searchable")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                            }
                        }
                    }
                    .padding(16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onDisappear { active?.cancel() }
    }

    private func choosePDFs() {
        let panel = NSOpenPanel()
        panel.title = "Choose scanned PDF files"
        panel.allowedContentTypes = [.pdf]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        if panel.urls.count > StudioSearchablePDFPolicy.maximumInputs {
            errors = ["Choose up to \(StudioSearchablePDFPolicy.maximumInputs) PDFs per batch."]
            return
        }
        sourceFiles = panel.urls
        completedFiles = []
        outputFolder = nil
        errors = []
        message = ""
    }

    private func start() {
        guard !running, !sourceFiles.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.title = "Where should the searchable PDFs be saved?"
        panel.prompt = "Choose Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        outputFolder = folder
        completedFiles = []
        errors = []
        message = ""
        running = true
        progress.reset()
        let input = sourceFiles
        let tracker = progress
        Task { @MainActor in
            for (index, url) in input.enumerated() {
                if tracker.stopRequested { break }
                tracker.fileIndex = index + 1
                let task = Task.detached(priority: .userInitiated) {
                    try StudioSearchablePDFBridge.create(input: url, destinationFolder: folder) { page, total in
                        Task { @MainActor in tracker.record(page, total) }
                    }
                }
                active = task
                do {
                    completedFiles.append(try await task.value)
                } catch is CancellationError {
                    tracker.stopRequested = true
                } catch {
                    errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
                active = nil
            }
            running = false
            message = "Created and verified \(completedFiles.count) searchable " +
                (completedFiles.count == 1 ? "PDF." : "PDFs.") +
                (tracker.stopRequested ? " Stopped after the current page." : "")
        }
    }

    private func reveal() {
        guard let folder = outputFolder else { return }
        NSWorkspace.shared.activateFileViewerSelecting(completedFiles.map { folder.appendingPathComponent($0.filename) })
    }
}

@MainActor
final class StudioSearchablePDFProgress: ObservableObject {
    @Published var page = 0
    @Published var total = 0
    @Published var fileIndex = 0
    var stopRequested = false
    func reset() { page = 0; total = 0; fileIndex = 0; stopRequested = false }
    func record(_ page: Int, _ total: Int) { self.page = page; self.total = total }
}
