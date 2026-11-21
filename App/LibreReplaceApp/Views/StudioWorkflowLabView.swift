import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers
import LibreReplaceCore

/// Documents remain local. The Lab produces editable text and an optional
/// Markdown export; it does not edit source files or silently create output.
struct StudioWorkflowLabView: View {
    @State private var inputURLs: [URL] = []
    @State private var outputs: [StudioDocumentResult] = []
    @State private var failures: [String] = []
    @State private var exportFormat: StudioTextExportFormat = .markdown
    @State private var editableText = ""
    @State private var isRunning = false
    @State private var stopRequested = false
    @StateObject private var progress = StudioDocumentProgressState()
    @State private var runningTask: Task<StudioDocumentResult, Error>?
    @State private var completed = 0
    @State private var currentFile = ""
    @State private var message = ""
    @State private var saveError: String?

    enum LabMode: String, CaseIterable, Identifiable {
        case extract = "Extract text"
        case merge = "Combine PDFs"
        case searchable = "Searchable PDF"
        case rescue = "PDF Rescue"
        case convert = "Convert images"
        var id: String { rawValue }
    }
    @State private var labMode: LabMode
    let imageOnly: Bool

    init(initialMode: LabMode = .extract, imageOnly: Bool = false) {
        _labMode = State(initialValue: initialMode)
        self.imageOnly = imageOnly
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 15) {
                Text("Free tools")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Picker("Choose a workflow", selection: $labMode) {
                    ForEach(LabMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Choose a workflow")
                .frame(maxWidth: 800, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 8)

            if labMode == .extract {
                extractionView
            } else if labMode == .searchable {
                StudioSearchablePDFView().id(labMode)
            } else if labMode == .rescue {
                StudioPDFRescueView().id(labMode)
            } else {
                // A fresh mode gets fresh inputs and outputs: PDFs selected for
                // merging must never silently carry into image conversion.
                StudioFileToolsView(isPDF: labMode == .merge)
                    .id(labMode)
            }
        }
        .frame(maxWidth: 960, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var extractionView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(imageOnly ? "Extract text from images" : "Extract text from documents")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(imageOnly ? "Choose a screenshot or photo to turn into editable text." : "Turn screenshots, photos and PDFs into text you can edit and export.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text.viewfinder")
                            .font(.title).foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(imageOnly ? "Choose screenshots or photos" : "Choose documents or images").font(.headline)
                            Text(imageOnly ? "You can select several images at once." : "Process documents and images in batches.")
                                .foregroundStyle(.secondary).font(.callout)
                        }
                    }
                    HStack(spacing: 12) {
                        Button {
                            chooseFiles()
                        } label: {
                            Label("Choose Files…", systemImage: "plus")
                        }.disabled(isRunning)
                        Text(inputURLs.isEmpty ? "No files selected" : "\(inputURLs.count) files selected")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            run()
                        } label: {
                            Label(isRunning ? "Processing…" : "Extract Text", systemImage: "text.viewfinder")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRunning || inputURLs.isEmpty)
                        if isRunning {
                            Button("Stop") {
                                stopRequested = true
                                runningTask?.cancel()
                            }.disabled(stopRequested)
                        }
                    }
                    if !inputURLs.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(inputURLs, id: \.self) { url in
                                Label(url.lastPathComponent, systemImage: url.pathExtension.lowercased() == "pdf" ? "doc.richtext" : "photo")
                                    .font(.callout).lineLimit(1)
                            }
                        }
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    }
                    if isRunning {
                        ProgressView(value: Double(completed), total: Double(max(1, inputURLs.count)))
                            .accessibilityLabel("Files processed")
                        Text("Completed \(completed) of \(inputURLs.count) files. \(currentFile)" +
                             (progress.totalPages > 1 ? " · Page \(progress.currentPage) of \(progress.totalPages)" : ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                if !message.isEmpty {
                    Label(message, systemImage: "info.circle").font(.callout)
                }
                if !failures.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Files needing attention", systemImage: "exclamationmark.triangle").font(.headline)
                        ForEach(failures, id: \.self) { item in Text(item).font(.callout) }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }

                HStack {
                    Text("Result").font(.title2.bold())
                    Spacer()
                    if !outputs.isEmpty {
                        Picker("Format", selection: $exportFormat) {
                            ForEach(StudioTextExportFormat.allCases, id: \.self) { format in
                                Text(format.rawValue).tag(format)
                            }
                        }
                        .frame(width: 205)
                        .onChange(of: exportFormat) { _, value in
                            editableText = StudioTextExporter.render(outputs, as: value)
                        }
                        Button {
                            saveResult()
                        } label: {
                            Label("Save \(exportFormat.rawValue)…", systemImage: "square.and.arrow.down")
                        }.disabled(isRunning || editableText.isEmpty)
                    }
                }
                if editableText.isEmpty {
                    StudioCompactEmptyState(
                        title: "Your extracted text will appear here",
                        systemImage: "doc.text.viewfinder",
                        message: "Choose a file above, then select Extract Text."
                    )
                } else {
                    TextEditor(text: $editableText)
                        .font(.body.monospaced())
                        .frame(minHeight: 330)
                        .padding(8)
                        .background(.background, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
                        .accessibilityLabel("Extracted text, editable before saving")
                    Text("\(outputs.count) successful file(s) · \(outputs.reduce(0) { $0 + $1.pages.count }) page(s) · \(outputs.reduce(0) { $0 + $1.recognizedPages }) page(s) processed with Vision OCR")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("16 files per batch · 500 pages per PDF · 150 MB per PDF · 25 MB per image")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onDisappear {
            stopRequested = true
            runningTask?.cancel()
        }
        .alert("Could not save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = imageOnly ? "Choose screenshots or images" : "Choose screenshots, images or PDFs"
        panel.allowedContentTypes = imageOnly ? [.png, .jpeg, .heic, .tiff] : [.png, .jpeg, .heic, .tiff, .pdf]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        inputURLs = Array(panel.urls.prefix(StudioDocumentLimits.maximumFiles))
        outputs = []
        failures = []
        completed = 0
        editableText = ""
        message = panel.urls.count > StudioDocumentLimits.maximumFiles ? "Selected the first \(StudioDocumentLimits.maximumFiles) files. You can process more in another batch." : ""
    }

    private func run() {
        guard !isRunning, !inputURLs.isEmpty else { return }
        outputs = []
        failures = []
        editableText = ""
        completed = 0
        stopRequested = false
        progress.reset()
        isRunning = true
        message = ""
        Task { @MainActor in
            for url in inputURLs {
                if stopRequested { break }
                currentFile = "Reading \(url.lastPathComponent)"
                let progressID = progress.reset()
                let progressTracker = progress
                do {
                    let task = Task.detached(priority: .userInitiated) {
                        try StudioDocumentBridge.extract(url: url) { page, total in
                            Task { @MainActor in
                                progressTracker.record(page: page, total: total, for: progressID)
                            }
                        }
                    }
                    runningTask = task
                    let output = try await task.value
                    let totalBytes = outputs.reduce(0) { $0 + $1.text.utf8.count } + output.text.utf8.count
                    if totalBytes > 16 * 1024 * 1024 {
                        failures.append("\(url.lastPathComponent): This batch has reached the 16 MB text preview limit. Save these results and start a new batch.")
                        stopRequested = true
                    } else {
                        outputs.append(output)
                    }
                } catch is CancellationError {
                    stopRequested = true
                } catch {
                    if !stopRequested { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
                }
                runningTask = nil
                completed += 1
            }
            editableText = StudioTextExporter.render(outputs, as: exportFormat)
            isRunning = false
            currentFile = ""
            message = "Processed \(completed) files · \(outputs.count) completed" +
                (failures.isEmpty ? "." : " · \(failures.count) need attention.") +
                (stopRequested ? " Processing stopped." : "")
        }
    }

    private func saveResult() {
        guard !isRunning, !editableText.isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = "Save extracted document text"
        panel.allowedContentTypes = exportFormat == .markdown ? [UTType(filenameExtension: "md") ?? .plainText] : [.plainText]
        panel.nameFieldStringValue = "LibreReplace-Text.\(exportFormat.filenameExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = Data(editableText.utf8)
            try data.write(to: url, options: .atomic)
            // Read-back verifies that the export contains the exact edited bytes.
            guard try Data(contentsOf: url) == data else {
                throw CocoaError(.fileWriteUnknown)
            }
            message = "Saved and read-back checked \(url.lastPathComponent). Text accuracy still requires review."
        } catch {
            saveError = "The exported file could not be verified: \(error.localizedDescription)"
        }
    }
}

@MainActor
final class StudioDocumentProgressState: ObservableObject {
    @Published private(set) var currentPage = 0
    @Published private(set) var totalPages = 0
    private var activeID = UUID()

    @discardableResult
    func reset() -> UUID {
        activeID = UUID()
        currentPage = 0
        totalPages = 0
        return activeID
    }
    func record(page: Int, total: Int, for id: UUID) {
        guard id == activeID else { return }
        currentPage = page
        totalPages = total
    }
}
