import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers
import LibreReplaceCore

/// A single workflow that combines two established engines: Vision-backed
/// searchable PDF generation followed by PDFKit page assembly and verification.
struct StudioPDFRescueView: View {
    @State private var chosenFiles: [URL] = []
    @State private var outputFolder: URL?
    @State private var result: StudioPDFRescueOutput?
    @State private var running = false
    @State private var status = ""
    @State private var errorText: String?
    @State private var active: Task<StudioPDFRescueOutput, Error>?
    @StateObject private var progress = StudioPDFRescueProgress()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PDF Rescue").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    Text("Combine ordinary and scanned PDFs into one searchable document. LibreReplace recognizes scanned text, keeps your page order, and checks the saved result.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.title).foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Choose the documents to combine").font(.headline)
                            Text("Select 2–8 PDFs. Arrange them in the order you want in the final file.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                    }
                    HStack(spacing: 12) {
                        Button { choosePDFs() } label: {
                            Label("Choose PDFs…", systemImage: "plus")
                        }.disabled(running)
                        Text(chosenFiles.isEmpty ? "No PDFs selected" : "\(chosenFiles.count) PDFs selected")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Button { start() } label: {
                            Label(running ? "Creating…" : "Create searchable PDF…", systemImage: "doc.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(running || chosenFiles.count < 2)
                    }
                    if !chosenFiles.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(chosenFiles.indices, id: \.self) { index in
                                HStack(spacing: 10) {
                                    Text("\(index + 1)").font(.callout.monospacedDigit())
                                        .foregroundStyle(.secondary).frame(width: 24)
                                    Image(systemName: "doc.richtext").foregroundStyle(.secondary)
                                    Text(chosenFiles[index].lastPathComponent)
                                        .font(.callout).lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 6)
                                    Button { move(index, by: -1) } label: {
                                        Image(systemName: "arrow.up")
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(running || index == 0)
                                    .accessibilityLabel("Move \(chosenFiles[index].lastPathComponent) earlier")
                                    Button { move(index, by: 1) } label: {
                                        Image(systemName: "arrow.down")
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(running || index == chosenFiles.count - 1)
                                    .accessibilityLabel("Move \(chosenFiles[index].lastPathComponent) later")
                                }
                                .padding(.horizontal, 10).padding(.vertical, 9)
                                if index < chosenFiles.count - 1 { Divider() }
                            }
                        }
                        .background(.background, in: RoundedRectangle(cornerRadius: 10))
                    }
                    if running {
                        ProgressView(value: Double(progress.pagesDone), total: Double(max(1, progress.totalPages)))
                            .accessibilityLabel("PDF pages processed")
                        HStack {
                            Text("Processing page \(progress.pagesDone) of \(max(1, progress.totalPages))")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Stop") { active?.cancel() }
                        }
                    }
                    Text("Up to 500 pages and 250 MB combined. Encrypted PDFs, interactive forms and rotated pages aren't changed or silently flattened.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }
                if let result, let folder = outputFolder {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Your combined PDF is ready", systemImage: "checkmark.circle.fill")
                            .font(.headline).foregroundStyle(.green)
                        Text(result.filename).font(.callout.weight(.semibold))
                            .lineLimit(2).truncationMode(.middle)
                        Text("\(result.sourceCount) documents · \(result.pageCount) pages · \(result.scannedPagesMadeSearchable) scanned pages made searchable")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button("Open PDF", systemImage: "doc.text") {
                                NSWorkspace.shared.open(folder.appendingPathComponent(result.filename))
                            }.buttonStyle(.borderedProminent)
                            Button("Show in Finder", systemImage: "folder") {
                                NSWorkspace.shared.activateFileViewerSelecting([
                                    folder.appendingPathComponent(result.filename)
                                ])
                            }
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
                } else if !running {
                    StudioCompactEmptyState(
                        title: "One searchable PDF, ready to use",
                        systemImage: "doc.on.doc",
                        message: "Choose your PDFs, set their order, and create one new document."
                    )
                }
                if !status.isEmpty {
                    Text(status).font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onDisappear { active?.cancel() }
    }

    private func choosePDFs() {
        let panel = NSOpenPanel()
        panel.title = "Choose PDFs to combine and make searchable"
        panel.allowedContentTypes = [.pdf]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        if panel.urls.count > StudioPDFRescuePolicy.maximumInputs {
            errorText = "Choose no more than \(StudioPDFRescuePolicy.maximumInputs) PDFs at once."
            return
        }
        chosenFiles = panel.urls
        result = nil
        outputFolder = nil
        errorText = nil
        status = ""
    }

    private func move(_ index: Int, by offset: Int) {
        let other = index + offset
        guard !running, chosenFiles.indices.contains(index), chosenFiles.indices.contains(other) else { return }
        chosenFiles.swapAt(index, other)
        result = nil
    }

    private func start() {
        guard !running, chosenFiles.count >= 2 else { return }
        let picker = NSOpenPanel()
        picker.title = "Where should the finished PDF be saved?"
        picker.prompt = "Choose Folder"
        picker.canChooseFiles = false
        picker.canChooseDirectories = true
        picker.canCreateDirectories = true
        guard picker.runModal() == .OK, let folder = picker.url else { return }
        outputFolder = folder
        result = nil
        status = ""
        errorText = nil
        running = true
        progress.reset()
        let selected = chosenFiles
        let tracker = progress
        let task = Task.detached(priority: .userInitiated) {
            try StudioPDFRescueBridge.create(inputs: selected, destinationFolder: folder) { current, total in
                Task { @MainActor in tracker.record(current, total) }
            }
        }
        active = task
        Task { @MainActor in
            do {
                result = try await task.value
                status = "The saved PDF passed page-count and searchable-text checks. Your originals were not modified."
            } catch is CancellationError {
                status = "Stopped without saving a new PDF. Your originals were not modified."
            } catch {
                errorText = error.localizedDescription
                status = "No finished file was published. Your originals were not modified."
            }
            active = nil
            running = false
        }
    }
}

@MainActor
final class StudioPDFRescueProgress: ObservableObject {
    @Published private(set) var pagesDone = 0
    @Published private(set) var totalPages = 0
    func reset() { pagesDone = 0; totalPages = 0 }
    func record(_ completed: Int, _ total: Int) {
        pagesDone = completed
        totalPages = total
    }
}
