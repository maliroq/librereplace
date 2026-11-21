import Foundation
#if os(macOS)
import PDFKit
#endif

/// One deliverable assembled from digital and scanned PDFs, using the existing
/// PDFKit merger and on-device Vision OCR engine. No intermediate files escape
/// the disposable staging directory when processing fails or is cancelled.
public struct StudioPDFRescueOutput: Equatable, Sendable {
    public let filename: String
    public let sourceCount: Int
    public let pageCount: Int
    public let scannedPagesMadeSearchable: Int
    public let byteCount: Int

    public init(filename: String, sourceCount: Int, pageCount: Int,
                scannedPagesMadeSearchable: Int, byteCount: Int) {
        self.filename = filename
        self.sourceCount = sourceCount
        self.pageCount = pageCount
        self.scannedPagesMadeSearchable = scannedPagesMadeSearchable
        self.byteCount = byteCount
    }
}

public struct StudioPDFRescueInput: Equatable, Sendable {
    public let filename: String
    public let byteCount: Int
    public let pages: Int
    public init(filename: String, byteCount: Int, pages: Int) {
        self.filename = filename
        self.byteCount = byteCount
        self.pages = pages
    }
}

public enum StudioPDFRescueError: LocalizedError, Sendable {
    case unsupportedPlatform, needTwoPDFs, tooManyPDFs, repeatedInput
    case invalidInput, lockedPDF, unsupportedPage, tooManyPages, tooMuchData
    case badDestination, outputFailed, verificationFailed

    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform: "This tool requires macOS."
        case .needTwoPDFs: "Choose at least two PDF files to combine."
        case .tooManyPDFs: "Choose up to eight PDFs per workflow."
        case .repeatedInput: "Remove duplicate PDFs from your selection."
        case .invalidInput: "One of the chosen files isn't a readable PDF."
        case .lockedPDF: "Unlock the selected PDF before combining it."
        case .unsupportedPage: "A PDF has rotated pages, annotations or pages too large to process safely."
        case .tooManyPages: "Choose PDFs totaling no more than 500 pages."
        case .tooMuchData: "Choose PDFs totaling no more than 250 MB, with a maximum of 150 MB each."
        case .badDestination: "Choose a normal local folder where the new PDF can be saved."
        case .outputFailed: "LibreReplace couldn't create the new PDF. Your originals are unchanged."
        case .verificationFailed: "The combined PDF didn't pass the page and text verification. No output was saved."
        }
    }
}

/// Portable preflight checks run before PDFKit is accessed or staging begins.
public enum StudioPDFRescuePolicy {
    public static let maximumInputs = 8
    public static let maximumPages = 500
    public static let maximumFileBytes = 150 * 1024 * 1024
    public static let maximumCombinedBytes = 250 * 1024 * 1024

    public static func validate(_ inputs: [StudioPDFRescueInput]) throws {
        guard inputs.count >= 2 else { throw StudioPDFRescueError.needTwoPDFs }
        guard inputs.count <= maximumInputs else { throw StudioPDFRescueError.tooManyPDFs }
        var pages = 0
        var bytes = 0
        for input in inputs {
            guard (input.filename as NSString).pathExtension.lowercased() == "pdf",
                  input.pages > 0, input.byteCount > 0 else { throw StudioPDFRescueError.invalidInput }
            guard input.byteCount <= maximumFileBytes else { throw StudioPDFRescueError.tooMuchData }
            let (newPages, pageOverflow) = pages.addingReportingOverflow(input.pages)
            guard !pageOverflow, newPages <= maximumPages else { throw StudioPDFRescueError.tooManyPages }
            let (newBytes, byteOverflow) = bytes.addingReportingOverflow(input.byteCount)
            guard !byteOverflow, newBytes <= maximumCombinedBytes else { throw StudioPDFRescueError.tooMuchData }
            pages = newPages
            bytes = newBytes
        }
    }
}

public enum StudioPDFRescueBridge {
    /// Process PDFs in the chosen order. Each scanned page gains an OCR text
    /// layer before the PDFs are combined into a single verified output.
    /// The only user-visible write is an atomic, no-overwrite publication.
    public static func create(inputs: [URL], destinationFolder: URL,
                              progress: (@Sendable (Int, Int) -> Void)? = nil) throws -> StudioPDFRescueOutput {
        #if os(macOS)
        try Task<Never, Never>.checkCancellation()
        guard destinationFolder.isFileURL else { throw StudioPDFRescueError.badDestination }
        let folderProperties = try destinationFolder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard folderProperties.isDirectory == true, folderProperties.isSymbolicLink != true else {
            throw StudioPDFRescueError.badDestination
        }
        guard Set(inputs.map { $0.standardizedFileURL.path }).count == inputs.count else {
            throw StudioPDFRescueError.repeatedInput
        }

        var inputInfo: [StudioPDFRescueInput] = []
        var scanned: [Bool] = []
        var expectedDigitalText: [String?] = []
        var documents: [PDFDocument] = []
        for input in inputs {
            try Task<Never, Never>.checkCancellation()
            guard input.isFileURL, input.pathExtension.lowercased() == "pdf" else {
                throw StudioPDFRescueError.invalidInput
            }
            let attributes = try input.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard attributes.isRegularFile == true, attributes.isSymbolicLink != true,
                  let length = attributes.fileSize,
                  let document = PDFDocument(url: input), document.pageCount > 0 else {
                throw StudioPDFRescueError.invalidInput
            }
            guard !document.isEncrypted, !document.isLocked else { throw StudioPDFRescueError.lockedPDF }
            inputInfo.append(StudioPDFRescueInput(filename: input.lastPathComponent, byteCount: length, pages: document.pageCount))
            documents.append(document)
            for pageIndex in 0..<document.pageCount {
                try Task<Never, Never>.checkCancellation()
                guard let page = document.page(at: pageIndex), page.pageRef != nil,
                      page.annotations.isEmpty, page.rotation == 0 else {
                    throw StudioPDFRescueError.unsupportedPage
                }
                let size = page.bounds(for: .mediaBox).size
                do { _ = try StudioSearchablePDFPolicy.imageDimensions(for: size.width, size.height) }
                catch { throw StudioPDFRescueError.unsupportedPage }
                let text = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                scanned.append(text.isEmpty)
                expectedDigitalText.append(text.isEmpty ? nil : normalized(String(text.prefix(80))))
            }
        }
        try StudioPDFRescuePolicy.validate(inputInfo)
        let totalPages = scanned.count

        // Keep all intermediate files next to the output so publication can
        // use a same-volume hard link. The folder is temporary and removed
        // even if recognition, joining, verification or cancellation fails.
        let working = destinationFolder.appendingPathComponent(".lr-pdf-rescue-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: working, withIntermediateDirectories: false)
        } catch { throw StudioPDFRescueError.badDestination }
        defer { try? FileManager.default.removeItem(at: working) }

        var prepared: [URL] = []
        var processedPages = 0
        var rescuedPages = 0
        for (position, input) in inputs.enumerated() {
            try Task<Never, Never>.checkCancellation()
            let document = documents[position]
            let startsAt = processedPages
            let hasScans = (0..<document.pageCount).contains { scanned[startsAt + $0] }
            if hasScans {
                let output = try StudioSearchablePDFBridge.create(input: input, destinationFolder: working) { page, _ in
                    progress?(startsAt + page, totalPages)
                }
                prepared.append(working.appendingPathComponent(output.filename))
                rescuedPages += output.newlySearchablePages
            } else {
                prepared.append(input)
                progress?(startsAt + document.pageCount, totalPages)
            }
            processedPages += document.pageCount
        }
        try Task<Never, Never>.checkCancellation()

        let combined = try StudioNativeFileBridge.execute(task: .mergePDFs, files: prepared,
                                                            destinationFolder: working)
        guard let created = combined.first else { throw StudioPDFRescueError.outputFailed }
        let candidate = working.appendingPathComponent(created.filename)
        guard let verified = PDFDocument(url: candidate), !verified.isLocked,
              verified.pageCount == totalPages else { throw StudioPDFRescueError.verificationFailed }
        for index in 0..<totalPages {
            try Task<Never, Never>.checkCancellation()
            guard let finalText = verified.page(at: index)?.string,
                  !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw StudioPDFRescueError.verificationFailed
            }
            if let expected = expectedDigitalText[index], !expected.isEmpty,
               !normalized(finalText).contains(expected) {
                throw StudioPDFRescueError.verificationFailed
            }
        }
        let outputSize = try candidate.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard outputSize > 0, outputSize <= StudioFilePolicy.maximumCombinedPDFBytes else {
            throw StudioPDFRescueError.tooMuchData
        }
        try Task<Never, Never>.checkCancellation()
        let published = try publishUnique(candidate, destinationFolder)
        return StudioPDFRescueOutput(filename: published.lastPathComponent,
                                     sourceCount: inputs.count,
                                     pageCount: totalPages,
                                     scannedPagesMadeSearchable: rescuedPages,
                                     byteCount: outputSize)
        #else
        throw StudioPDFRescueError.unsupportedPlatform
        #endif
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
    }

    #if os(macOS)
    private static func publishUnique(_ temp: URL, _ folder: URL) throws -> URL {
        for number in 1...1000 {
            try Task<Never, Never>.checkCancellation()
            let filename = number == 1 ? "PDF-Rescue-LibreReplace.pdf" : "PDF-Rescue-LibreReplace-\(number).pdf"
            let candidate = folder.appendingPathComponent(filename)
            do {
                try FileManager.default.linkItem(at: temp, to: candidate)
                return candidate
            } catch {
                if FileManager.default.fileExists(atPath: candidate.path) ||
                   (try? FileManager.default.destinationOfSymbolicLink(atPath: candidate.path)) != nil {
                    continue
                }
                throw StudioPDFRescueError.outputFailed
            }
        }
        throw StudioPDFRescueError.outputFailed
    }
    #endif
}
