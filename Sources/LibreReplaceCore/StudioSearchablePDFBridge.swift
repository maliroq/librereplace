import Foundation
#if os(macOS)
import AppKit
import CoreGraphics
import CoreText
import PDFKit
import Vision
#endif

/// A verified new PDF, never an in-place change to the supplied document.
public struct StudioSearchablePDFOutput: Equatable, Sendable {
    public let filename: String
    public let pageCount: Int
    public let newlySearchablePages: Int
    public let bytes: Int

    public init(filename: String, pageCount: Int, newlySearchablePages: Int, bytes: Int) {
        self.filename = filename
        self.pageCount = pageCount
        self.newlySearchablePages = newlySearchablePages
        self.bytes = bytes
    }
}

public enum StudioSearchablePDFError: LocalizedError, Sendable {
    case unsupportedPlatform, badInput, badDestination, invalidPDF, encryptedPDF, annotatedPDF
    case rotatedPage, oversizedPage, noRecognizedText, creationFailed, verificationFailed, outputTooLarge

    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform: "This tool requires macOS."
        case .badInput: "Choose an existing, readable PDF file."
        case .badDestination: "Choose an existing folder where the new PDF can be saved."
        case .invalidPDF: "This PDF cannot be opened or has no pages."
        case .encryptedPDF: "Unlock the PDF before processing it."
        case .annotatedPDF: "This PDF has forms or annotations that cannot safely be preserved by this workflow."
        case .rotatedPage: "This PDF contains rotated pages that this workflow cannot yet preserve correctly."
        case .oversizedPage: "One page is too large to scan safely."
        case .noRecognizedText: "No searchable text could be recovered from the selected PDF."
        case .creationFailed: "LibreReplace could not create the new searchable PDF."
        case .verificationFailed: "The new PDF did not pass text-layer or page-count verification. No output was published."
        case .outputTooLarge: "The new PDF exceeds the supported 250 MB output limit."
        }
    }
}

/// Testable, conservative limits for the OCR-backed searchable-PDF workflow.
public enum StudioSearchablePDFPolicy {
    public static let maximumInputs = 8
    public static let maximumOutputBytes = 250 * 1024 * 1024
    public static let maximumRenderedPixels = 16_000_000

    public static func validate(pageCount: Int, inputBytes: Int) throws {
        try StudioDocumentLimits.checkPDF(pages: pageCount, bytes: inputBytes)
    }

    public static func imageDimensions(for pageWidth: CGFloat, _ pageHeight: CGFloat) throws -> (Int, Int) {
        guard pageWidth.isFinite, pageHeight.isFinite, pageWidth > 0, pageHeight > 0,
              pageWidth <= 2_048, pageHeight <= 2_048 else { throw StudioSearchablePDFError.oversizedPage }
        let width = Int(ceil(pageWidth * 2))
        let height = Int(ceil(pageHeight * 2))
        guard width > 0, height > 0, width <= 4_096, height <= 4_096,
              width <= maximumRenderedPixels / height else { throw StudioSearchablePDFError.oversizedPage }
        return (width, height)
    }
}

/// Converts scanned PDF pages to genuinely selectable/searchable PDF text.
/// It draws the original page first, then adds invisible positioned CoreText
/// from on-device Vision OCR. PDFKit independently checks the saved text layer.
/// Form annotations and rotated source pages are deliberately refused rather
/// than silently discarded or incorrectly transformed.
public enum StudioSearchablePDFBridge {
    public static func create(input: URL, destinationFolder: URL,
                              progress: (@Sendable (Int, Int) -> Void)? = nil) throws -> StudioSearchablePDFOutput {
        #if os(macOS)
        try Task<Never, Never>.checkCancellation()
        guard input.isFileURL, input.pathExtension.lowercased() == "pdf" else {
            throw StudioSearchablePDFError.badInput
        }
        let inputInfo = try input.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard inputInfo.isRegularFile == true, inputInfo.isSymbolicLink != true,
              let bytes = inputInfo.fileSize else { throw StudioSearchablePDFError.badInput }
        guard destinationFolder.isFileURL else { throw StudioSearchablePDFError.badDestination }
        let directoryInfo = try destinationFolder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard directoryInfo.isDirectory == true, directoryInfo.isSymbolicLink != true else {
            throw StudioSearchablePDFError.badDestination
        }
        guard let pdf = PDFDocument(url: input), pdf.pageCount > 0 else {
            throw StudioSearchablePDFError.invalidPDF
        }
        guard !pdf.isEncrypted, !pdf.isLocked else { throw StudioSearchablePDFError.encryptedPDF }
        try StudioSearchablePDFPolicy.validate(pageCount: pdf.pageCount, inputBytes: bytes)

        // Inspect all pages before producing any output. A CoreGraphics-only
        // page copy does not preserve PDF annotations and form interactivity.
        for index in 0..<pdf.pageCount {
            try Task<Never, Never>.checkCancellation()
            guard let page = pdf.page(at: index), page.pageRef != nil else { throw StudioSearchablePDFError.invalidPDF }
            guard page.annotations.isEmpty else { throw StudioSearchablePDFError.annotatedPDF }
            guard page.rotation == 0 else { throw StudioSearchablePDFError.rotatedPage }
            let box = page.bounds(for: .mediaBox)
            _ = try StudioSearchablePDFPolicy.imageDimensions(for: box.width, box.height)
        }

        let temp = destinationFolder.appendingPathComponent(".lr-searchable-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: temp) }
        var defaultBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let output = CGContext(temp as CFURL, mediaBox: &defaultBox, nil) else {
            throw StudioSearchablePDFError.creationFailed
        }
        var newlySearchable = 0
        var expectedPageTokens: [Int: String] = [:]
        for index in 0..<pdf.pageCount {
            try Task<Never, Never>.checkCancellation()
            guard let sourcePage = pdf.page(at: index), let cgPage = sourcePage.pageRef else {
                throw StudioSearchablePDFError.invalidPDF
            }
            let mediaBox = sourcePage.bounds(for: .mediaBox)
            let targetBox = CGRect(origin: .zero, size: mediaBox.size)
            output.beginPDFPage([kCGPDFContextMediaBox as String: targetBox] as CFDictionary)
            output.saveGState()
            output.concatenate(cgPage.getDrawingTransform(.mediaBox, rect: targetBox,
                                                         rotate: 0, preserveAspectRatio: true))
            output.drawPDFPage(cgPage)
            output.restoreGState()

            if (sourcePage.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let bitmap = try render(cgPage: cgPage, size: mediaBox.size)
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = true
                try VNImageRequestHandler(cgImage: bitmap, options: [:]).perform([request])
                let observations = (request.results ?? []).compactMap { observation -> (String, CGRect)? in
                    guard let text = observation.topCandidates(1).first?.string,
                          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                    return (text, observation.boundingBox)
                }
                if let first = observations.first {
                    expectedPageTokens[index] = first.0
                    newlySearchable += 1
                }
                for (recognizedText, bounds) in observations {
                    addInvisibleText(recognizedText, at: bounds, pageSize: targetBox.size, to: output)
                }
            }
            output.endPDFPage()
            progress?(index + 1, pdf.pageCount)
        }
        output.closePDF()
        try Task<Never, Never>.checkCancellation()
        guard newlySearchable > 0 else { throw StudioSearchablePDFError.noRecognizedText }
        let savedBytes = try temp.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard savedBytes > 0, savedBytes <= StudioSearchablePDFPolicy.maximumOutputBytes else {
            throw StudioSearchablePDFError.outputTooLarge
        }
        guard let checked = PDFDocument(url: temp), checked.pageCount == pdf.pageCount,
              !checked.isLocked else { throw StudioSearchablePDFError.verificationFailed }
        for (index, text) in expectedPageTokens {
            guard let selectable = checked.page(at: index)?.string,
                  !selectable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  // Compare normalized letters so PDFKit's font encoding and
                  // legitimate line wrapping won't cause false negatives.
                  normalized(selectable).contains(normalized(text)) else {
                throw StudioSearchablePDFError.verificationFailed
            }
        }
        let originalStem = input.deletingPathExtension().lastPathComponent
        let cleaned = String(String.UnicodeScalarView(
            originalStem.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }))
        let stem = String(cleaned.prefix(75))
        let name = (stem.isEmpty || stem == "." || stem == ".." ? "Document" : stem)
            + "-Searchable-LibreReplace.pdf"
        let target = try publishUnique(from: temp, to: destinationFolder, name: name)
        return StudioSearchablePDFOutput(filename: target.lastPathComponent,
                                         pageCount: checked.pageCount,
                                         newlySearchablePages: newlySearchable,
                                         bytes: savedBytes)
        #else
        throw StudioSearchablePDFError.unsupportedPlatform
        #endif
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
    }

    #if os(macOS)
    private static func render(cgPage: CGPDFPage, size: CGSize) throws -> CGImage {
        let (width, height) = try StudioSearchablePDFPolicy.imageDimensions(for: size.width, size.height)
        guard let context = CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw StudioSearchablePDFError.oversizedPage
        }
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(canvas)
        context.concatenate(cgPage.getDrawingTransform(.mediaBox, rect: canvas,
                                                       rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(cgPage)
        guard let result = context.makeImage() else { throw StudioSearchablePDFError.creationFailed }
        return result
    }

    private static func addInvisibleText(_ text: String, at bbox: CGRect, pageSize: CGSize,
                                         to context: CGContext) {
        guard bbox.width > 0, bbox.height > 0 else { return }
        let height = bbox.height * pageSize.height
        let fontSize = max(5, min(100, height * 0.90))
        let font = NSFont.systemFont(ofSize: fontSize)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let textWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        guard textWidth > 0 else { return }
        let wantedWidth = bbox.width * pageSize.width
        let scale = max(0.1, min(3, wantedWidth / textWidth))
        context.saveGState()
        context.setTextDrawingMode(.invisible)
        context.textMatrix = CGAffineTransform(scaleX: scale, y: 1)
        context.textPosition = CGPoint(x: bbox.minX * pageSize.width,
                                       y: bbox.minY * pageSize.height + height * 0.10)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// Atomic no-replace publication; never overwrite an existing output.
    private static func publishUnique(from temp: URL, to folder: URL, name: String) throws -> URL {
        let stem = (name as NSString).deletingPathExtension
        for index in 0..<1000 {
            try Task<Never, Never>.checkCancellation()
            let candidateName = index == 0 ? name : "\(stem)-\(index + 1).pdf"
            let url = folder.appendingPathComponent(candidateName)
            do {
                try FileManager.default.linkItem(at: temp, to: url)
                return url
            } catch {
                if FileManager.default.fileExists(atPath: url.path) ||
                    (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil {
                    continue
                }
                throw StudioSearchablePDFError.creationFailed
            }
        }
        throw StudioSearchablePDFError.creationFailed
    }
    #endif
}
