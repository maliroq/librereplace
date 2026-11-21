import Foundation
#if os(macOS)
import CoreGraphics
import PDFKit
import Vision
#endif

/// The output is in memory until the user explicitly chooses Save.
public struct StudioTextPage: Sendable, Equatable {
    public enum Origin: String, Sendable { case embeddedPDFText, visionOCR }
    public let number: Int
    public let text: String
    public let origin: Origin
    public let recognizedLineCount: Int
    public init(number: Int, text: String, origin: Origin, recognizedLineCount: Int) {
        self.number = number
        self.text = text
        self.origin = origin
        self.recognizedLineCount = recognizedLineCount
    }
}

public struct StudioDocumentResult: Sendable, Equatable {
    public let filename: String
    public let pages: [StudioTextPage]
    public init(filename: String, pages: [StudioTextPage]) {
        self.filename = filename
        self.pages = pages
    }
    public var text: String { pages.map(\.text).joined(separator: "\n\n") }
    public var recognizedPages: Int { pages.filter { $0.origin == .visionOCR }.count }
}

/// Resource limits are deliberately separate from extraction logic so they
/// can be reviewed and tested without a PDF parser or user files.
public enum StudioDocumentLimits {
    public static let maximumFiles = 16
    public static let maximumPDFPages = 500
    public static let maximumPDFBytes = 150 * 1024 * 1024
    public static let maximumImageBytes = 25 * 1024 * 1024
    public static let maximumExtractedTextBytes = 8 * 1024 * 1024

    public static func checkPDF(pages: Int, bytes: Int) throws {
        guard bytes > 0 && bytes <= maximumPDFBytes else { throw StudioDocumentError.tooLarge }
        guard pages > 0 else { throw StudioDocumentError.emptyDocument }
        guard pages <= maximumPDFPages else { throw StudioDocumentError.tooManyPages }
    }
}

public enum StudioDocumentError: LocalizedError, Sendable {
    case unsupportedPlatform
    case unsupportedFormat
    case invalidFile
    case tooLarge
    case invalidPDF
    case encryptedPDF
    case tooManyPages
    case imageTooLarge
    case emptyDocument
    case tooMuchText

    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform: "Document extraction is available on macOS only."
        case .unsupportedFormat: "Choose a PNG, JPEG, HEIC, TIFF or PDF."
        case .invalidFile: "The selected item is not a readable regular file."
        case .tooLarge: "This file is larger than the supported size (150 MB per PDF, 25 MB per image)."
        case .invalidPDF: "The PDF could not be opened or is not a valid PDF."
        case .encryptedPDF: "Locked or encrypted PDFs are not supported."
        case .tooManyPages: "This PDF exceeds 500 pages. Split it into smaller files to process the full document."
        case .imageTooLarge: "A PDF page would exceed the safe rendering limit."
        case .emptyDocument: "No selectable or recognizable text was found."
        case .tooMuchText: "This file contains more text than the editor can safely handle at once. Split it into smaller PDFs."
        }
    }
}

/// Native document reader: passes selectable PDF text through unchanged and uses
/// on-device Vision when a PDF page is an image. It never edits the source PDF.
public enum StudioDocumentBridge {
    public static func extract(url: URL, onProgress: (@Sendable (Int, Int) -> Void)? = nil) throws -> StudioDocumentResult {
        #if os(macOS)
        try Task<Never, Never>.checkCancellation()
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw StudioDocumentError.invalidFile }
        guard let size = values.fileSize, size > 0 else { throw StudioDocumentError.tooLarge }
        let suffix = url.pathExtension.lowercased()
        if suffix == "pdf" {
            guard size <= StudioDocumentLimits.maximumPDFBytes else { throw StudioDocumentError.tooLarge }
            return try extractPDF(url: url, size: size, onProgress: onProgress)
        }
        guard ["png", "jpg", "jpeg", "heic", "tif", "tiff"].contains(suffix) else { throw StudioDocumentError.unsupportedFormat }
        guard size <= StudioDocumentLimits.maximumImageBytes else { throw StudioDocumentError.tooLarge }
        let ocr = try StudioOCRBridge.recognize(imageAt: url)
        onProgress?(1, 1)
        return StudioDocumentResult(filename: url.lastPathComponent, pages: [
            StudioTextPage(number: 1, text: ocr.text, origin: .visionOCR, recognizedLineCount: ocr.recognizedLineCount)
        ])
        #else
        throw StudioDocumentError.unsupportedPlatform
        #endif
    }

    #if os(macOS)
    private static func extractPDF(url: URL, size: Int, onProgress: (@Sendable (Int, Int) -> Void)?) throws -> StudioDocumentResult {
        // Parse one page at a time and avoid retaining page bitmaps. Bound the
        // file, page count, output text and individual rendered pages.
        guard let document = PDFDocument(url: url) else { throw StudioDocumentError.invalidPDF }
        guard !document.isEncrypted, !document.isLocked else { throw StudioDocumentError.encryptedPDF }
        try StudioDocumentLimits.checkPDF(pages: document.pageCount, bytes: size)
        var pages: [StudioTextPage] = []
        pages.reserveCapacity(document.pageCount)
        var accumulatedTextBytes = 0
        for pageIndex in 0..<document.pageCount {
            try Task<Never, Never>.checkCancellation()
            guard let page = document.page(at: pageIndex) else { throw StudioDocumentError.invalidPDF }
            let embeddedText = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !embeddedText.isEmpty {
                accumulatedTextBytes += embeddedText.utf8.count
                guard accumulatedTextBytes <= StudioDocumentLimits.maximumExtractedTextBytes else { throw StudioDocumentError.tooMuchText }
                pages.append(StudioTextPage(number: pageIndex + 1, text: embeddedText,
                    origin: .embeddedPDFText, recognizedLineCount: embeddedText.components(separatedBy: .newlines).count))
                onProgress?(pageIndex + 1, document.pageCount)
                continue
            }
            let image = try render(page: page)
            // A scanned page may be blank; preserve page numbering without
            // aborting extraction of the other pages.
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            let text = lines.joined(separator: "\n")
            accumulatedTextBytes += text.utf8.count
            guard accumulatedTextBytes <= StudioDocumentLimits.maximumExtractedTextBytes else { throw StudioDocumentError.tooMuchText }
            pages.append(StudioTextPage(number: pageIndex + 1,
                text: text, origin: .visionOCR, recognizedLineCount: lines.count))
            onProgress?(pageIndex + 1, document.pageCount)
        }
        guard pages.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { throw StudioDocumentError.emptyDocument }
        return StudioDocumentResult(filename: url.lastPathComponent, pages: pages)
    }

    private static func render(page: PDFPage) throws -> CGImage {
        guard let cgPage = page.pageRef else { throw StudioDocumentError.invalidPDF }
        let bounds = cgPage.getBoxRect(.mediaBox)
        guard bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0 else { throw StudioDocumentError.invalidPDF }
        let scale: CGFloat = 2 // ~144 dpi before the limit below.
        let width = Int(ceil(bounds.width * scale))
        let height = Int(ceil(bounds.height * scale))
        guard width > 0, height > 0, width <= 4096, height <= 4096,
              width <= 16_000_000 / height else { throw StudioDocumentError.imageTooLarge }
        guard let context = CGContext(data: nil, width: width, height: height,
              bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw StudioDocumentError.imageTooLarge }
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(canvas)
        context.concatenate(cgPage.getDrawingTransform(.mediaBox, rect: canvas, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(cgPage)
        guard let image = context.makeImage() else { throw StudioDocumentError.invalidPDF }
        return image
    }
    #endif
}

public enum StudioTextExportFormat: String, CaseIterable, Sendable {
    case markdown = "Markdown"
    case text = "Plain text"
    public var filenameExtension: String { self == .markdown ? "md" : "txt" }
}

/// Pure, deterministic formatting is testable without PDFKit or Vision.
public enum StudioTextExporter {
    public static func render(_ documents: [StudioDocumentResult], as format: StudioTextExportFormat) -> String {
        guard !documents.isEmpty else { return "" }
        switch format {
        case .text:
            return documents.map { doc in
                (["=== \(doc.filename) ==="] + doc.pages.map { page in
                    "Page \(page.number)\n\(page.text)"
                }).joined(separator: "\n\n")
            }.joined(separator: "\n\n")
        case .markdown:
            return "# LibreReplace document text\n\n" + documents.map { doc in
                let title = doc.filename.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "#", with: "\\#")
                    .replacingOccurrences(of: "[", with: "\\[")
                    .replacingOccurrences(of: "]", with: "\\]")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")
                return "## \(title)\n\n" + doc.pages.map { page in
                    let fenceLength = max(3, longestBacktickRun(in: page.text) + 1)
                    let fence = String(repeating: "`", count: fenceLength)
                    return "### Page \(page.number) — \(page.origin == .visionOCR ? "local OCR" : "embedded text")\n\n\(fence)\n\(page.text)\n\(fence)"
                }.joined(separator: "\n\n")
            }.joined(separator: "\n\n---\n\n") + "\n"
        }
    }
    private static func longestBacktickRun(in text: String) -> Int {
        var current = 0, longest = 0
        for character in text {
            if character == "`" { current += 1; longest = max(longest, current) }
            else { current = 0 }
        }
        return longest
    }
}
