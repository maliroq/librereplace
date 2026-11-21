import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LibreReplaceCore

/// User-facing native file operations. No Homebrew or account is required.
struct StudioFileToolsView: View {
    let isPDF: Bool
    @State private var format: StudioFileTask = .convertToPNG
    @State private var selectedFiles: [URL] = []
    @State private var resultFiles: [StudioFileOutput] = []
    @State private var outputFolder: URL?
    @State private var running = false
    @State private var status = ""
    @State private var failure: String?
    @State private var task: Task<[StudioFileOutput], Error>?
    @StateObject private var progress = StudioFileTaskProgress()

    private var operation: StudioFileTask { isPDF ? .mergePDFs : format }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(isPDF ? "Combine PDF files" : "Convert images")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(isPDF ? "Combine files in your preferred order and save a new PDF. Your originals stay unchanged." :
                         "Convert PNG, JPEG, HEIC and TIFF images into a format that's easier to share or use elsewhere.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 14) {
                    if !isPDF {
                        HStack(spacing: 16) {
                            Text("Output format").font(.headline)
                            Spacer(minLength: 8)
                            Picker("Output format", selection: $format) {
                                Text("PNG").tag(StudioFileTask.convertToPNG)
                                Text("JPEG").tag(StudioFileTask.convertToJPEG)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .accessibilityLabel("Output image format")
                            .frame(width: 190)
                        }
                        Text(format == .convertToJPEG ? "Smaller files for photos. JPEG may lose fine detail and transparency." :
                             "Great for screenshots and graphics. PNG keeps image detail and transparency.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        Button {
                            pickFiles()
                        } label: {
                            Label("Choose \(isPDF ? "PDFs" : "Images")…", systemImage: "plus")
                        }
                        .disabled(running)
                        Text(selectedFiles.isEmpty ? "No files selected" : "\(selectedFiles.count) selected")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    if !selectedFiles.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(selectedFiles.enumerated()), id: \.offset) { index, url in
                                HStack(spacing: 10) {
                                    Image(systemName: isPDF ? "doc.richtext" : "photo")
                                        .foregroundStyle(.secondary)
                                    Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 8)
                                    if isPDF {
                                        Text("\(index + 1)").foregroundStyle(.secondary).monospacedDigit()
                                        Button {
                                            selectedFiles.swapAt(index, index - 1)
                                        } label: { Image(systemName: "arrow.up") }
                                        .buttonStyle(.borderless)
                                        .disabled(running || index == 0)
                                        .help("Move PDF earlier")
                                        .accessibilityLabel("Move \(url.lastPathComponent) earlier")
                                        Button {
                                            selectedFiles.swapAt(index, index + 1)
                                        } label: { Image(systemName: "arrow.down") }
                                        .buttonStyle(.borderless)
                                        .disabled(running || index == selectedFiles.count - 1)
                                        .help("Move PDF later")
                                        .accessibilityLabel("Move \(url.lastPathComponent) later")
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    }
                    HStack {
                        Button {
                            start()
                        } label: {
                            Label(isPDF ? "Combine and save…" : "Convert and save…",
                                  systemImage: isPDF ? "doc.on.doc" : "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(running || selectedFiles.isEmpty || (isPDF && selectedFiles.count < 2))
                        if running {
                            Button("Cancel") { task?.cancel() }
                            if progress.total > 0 {
                                Text("\(progress.current) of \(progress.total)")
                                    .foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                    if isPDF {
                        Text("Choose 2–16 PDFs. Up to 500 pages and 250 MB combined. The original files are never modified.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Choose up to 16 images, each no more than 25 MB. New files are saved separately from the originals.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                if !status.isEmpty {
                    Label(status, systemImage: resultFiles.isEmpty ? "info.circle" : "checkmark.circle")
                        .font(.callout)
                }
                if resultFiles.isEmpty && !running && status.isEmpty {
                    StudioCompactEmptyState(
                        title: isPDF ? "Your combined PDF will appear here" : "Your converted images will appear here",
                        systemImage: isPDF ? "doc.on.doc" : "photo.on.rectangle.angled",
                        message: isPDF ?
                            "Add two or more PDFs, arrange their order, then combine." :
                            "Choose images, select a format, then convert."
                    )
                }
                if !resultFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Created files").font(.title2.bold())
                            Spacer()
                            Button("Show in Finder", systemImage: "folder") { reveal() }
                        }
                        ForEach(resultFiles, id: \.filename) { file in
                            HStack {
                                Image(systemName: file.pageCount == nil ? "photo" : "doc.richtext")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.filename).lineLimit(1).truncationMode(.middle)
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(file.byteCount), countStyle: .file) +
                                         (file.pageCount.map { " · \($0) pages" } ?? ""))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
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
        .onDisappear { task?.cancel() }
        .alert("Could not complete the operation", isPresented: Binding(
            get: { failure != nil }, set: { if !$0 { failure = nil } }
        )) {
            Button("OK", role: .cancel) { failure = nil }
        } message: { Text(failure ?? "") }
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.title = isPDF ? "Choose PDF files in the order to combine" : "Choose images to convert"
        panel.allowedContentTypes = isPDF ? [.pdf] : [.png, .jpeg, .heic, .tiff]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        if panel.urls.count > StudioFilePolicy.maximumInputs {
            failure = "Choose up to \(StudioFilePolicy.maximumInputs) files per batch."
            return
        }
        selectedFiles = panel.urls
        resultFiles = []
        outputFolder = nil
        status = ""
    }

    private func start() {
        guard !running else { return }
        let folderPicker = NSOpenPanel()
        folderPicker.title = "Where should LibreReplace save the new \(isPDF ? "PDF" : "images")?"
        folderPicker.prompt = "Choose Folder"
        folderPicker.canChooseFiles = false
        folderPicker.canChooseDirectories = true
        folderPicker.canCreateDirectories = true
        guard folderPicker.runModal() == .OK, let destination = folderPicker.url else { return }
        let chosen = selectedFiles
        let choice = operation
        resultFiles = []
        outputFolder = destination
        progress.reset()
        running = true
        status = "Creating new files…"
        let tracker = progress
        let runningTask = Task.detached(priority: .userInitiated) {
            try StudioNativeFileBridge.execute(task: choice, files: chosen, destinationFolder: destination) { current, total in
                Task { @MainActor in tracker.record(current, total) }
            }
        }
        task = runningTask
        Task { @MainActor in
            do {
                let result = try await runningTask.value
                resultFiles = result
                status = "Created and checked \(result.count) new \(result.count == 1 ? "file" : "files")."
            } catch is CancellationError {
                status = "Stopped. Your original files are unchanged. Check the selected folder for any already completed outputs."
            } catch {
                failure = error.localizedDescription
                status = "No changes were made to your original files. If conversion stopped partway, completed files may be in the destination folder."
            }
            running = false
            task = nil
        }
    }

    private func reveal() {
        guard let folder = outputFolder else { return }
        let paths = resultFiles.map { folder.appendingPathComponent($0.filename) }
        NSWorkspace.shared.activateFileViewerSelecting(paths)
    }
}

@MainActor
final class StudioFileTaskProgress: ObservableObject {
    @Published private(set) var current = 0
    @Published private(set) var total = 0
    func reset() { current = 0; total = 0 }
    func record(_ current: Int, _ total: Int) {
        self.current = current
        self.total = total
    }
}
