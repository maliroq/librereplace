import Foundation
import XCTest
@testable import LibreReplaceCore

#if os(macOS)
import AppKit
import CoreGraphics
import CoreText
import ImageIO
import PDFKit
import UniformTypeIdentifiers
#endif

/// Real functional acceptance tests. Each test generates its own disposable
/// images/PDFs and checks real outputs; no sample uploads or network are needed.
final class StudioGeneratedFixtureTests: XCTestCase {
    func testPolicyAllows500PagesAndRejects501() {
        XCTAssertNoThrow(try StudioDocumentLimits.checkPDF(pages: 500, bytes: 1000))
        XCTAssertThrowsError(try StudioDocumentLimits.checkPDF(pages: 501, bytes: 1000))
    }

    func testPolicyRejectsOversizedImageAndExcessiveBatch() {
        XCTAssertThrowsError(try StudioFilePolicy.validate(
            [.init(filename: "photo.png", byteCount: StudioFilePolicy.maximumImageBytes + 1)],
            for: .convertToJPEG))
        let files = (0..<17).map { StudioFileInput(filename: "photo-\($0).png", byteCount: 100) }
        XCTAssertThrowsError(try StudioFilePolicy.validate(files, for: .convertToPNG))
    }

    #if os(macOS)
    private func workingDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("libreplace-generated-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// CoreText creates real selectable characters in PDF pages, avoiding
    /// reliance on a fixture download or recognizing a rasterized text image.
    private func makePDF(at url: URL, pages: Int, token: String, width: CGFloat) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: width, height: 540)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "Fixture", code: 1)
        }
        for index in 1...pages {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.textPosition = CGPoint(x: 28, y: 260)
            let line = CTLineCreateWithAttributedString(NSAttributedString(
                string: "\(token) PAGE \(index)",
                attributes: [.font: NSFont.systemFont(ofSize: 24, weight: .medium)]))
            CTLineDraw(line, context)
            context.endPDFPage()
        }
        context.closePDF()
        guard let pdf = PDFDocument(url: url), pdf.pageCount == pages,
              pdf.page(at: 0)?.string?.contains(token) == true else {
            throw NSError(domain: "Fixture", code: 2)
        }
    }

    private func makeImage(at url: URL, text: String? = nil, withGPS: Bool = false) throws {
        let width = 1500
        let height = 300
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw NSError(domain: "Fixture", code: 3)
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        if let text {
            context.textPosition = CGPoint(x: 75, y: 105)
            let line = CTLineCreateWithAttributedString(NSAttributedString(
                string: text, attributes: [.font: NSFont.boldSystemFont(ofSize: 95)]))
            CTLineDraw(line, context)
        } else {
            context.fill(CGRect(x: 30, y: 50, width: 640, height: 170))
        }
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "Fixture", code: 4)
        }
        let metadata: [String: Any] = withGPS ? [
            kCGImagePropertyGPSDictionary as String: [
                kCGImagePropertyGPSLatitude as String: 37.0,
                kCGImagePropertyGPSLongitude as String: 122.0
            ]
        ] : [:]
        CGImageDestinationAddImage(destination, image, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "Fixture", code: 5) }
    }

    func testGeneratedFortyPagePDFMergeAndTextExtraction() throws {
        let folder = try workingDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("part-one.pdf")
        let second = folder.appendingPathComponent("part-two.pdf")
        try makePDF(at: first, pages: 23, token: "ALPHA", width: 425)
        try makePDF(at: second, pages: 17, token: "BETA", width: 485)
        let originalData = try [first, second].map { try Data(contentsOf: $0) }
        let outputs = try StudioNativeFileBridge.execute(
            task: .mergePDFs, files: [first, second], destinationFolder: folder)
        let output = try XCTUnwrap(outputs.first)
        XCTAssertEqual(outputs.count, 1)
        XCTAssertEqual(output.pageCount, 40)
        let mergedURL = folder.appendingPathComponent(output.filename)
        let pdf = try XCTUnwrap(PDFDocument(url: mergedURL))
        XCTAssertEqual(pdf.pageCount, 40)
        XCTAssertEqual(pdf.page(at: 0)?.bounds(for: .mediaBox).width, 425)
        XCTAssertEqual(pdf.page(at: 23)?.bounds(for: .mediaBox).width, 485)
        let result = try StudioDocumentBridge.extract(url: mergedURL)
        XCTAssertEqual(result.pages.count, 40)
        XCTAssertEqual(result.recognizedPages, 0, "Selectable text should not require OCR")
        XCTAssertTrue(result.pages.first?.text.contains("ALPHA") == true)
        XCTAssertTrue(result.pages.last?.text.contains("BETA") == true)
        XCTAssertEqual(try [first, second].map { try Data(contentsOf: $0) }, originalData)
    }

    func testUniqueNamesNeverOverwritePriorPDFOutput() throws {
        let folder = try workingDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let a = folder.appendingPathComponent("one.pdf")
        let b = folder.appendingPathComponent("two.pdf")
        try makePDF(at: a, pages: 1, token: "ONE", width: 400)
        try makePDF(at: b, pages: 1, token: "TWO", width: 400)
        let first = try XCTUnwrap(StudioNativeFileBridge.execute(
            task: .mergePDFs, files: [a,b], destinationFolder: folder).first)
        let firstData = try Data(contentsOf: folder.appendingPathComponent(first.filename))
        let second = try XCTUnwrap(StudioNativeFileBridge.execute(
            task: .mergePDFs, files: [a,b], destinationFolder: folder).first)
        XCTAssertNotEqual(first.filename, second.filename)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(first.filename)), firstData)
    }

    func testGeneratedImageConversionAndPrivateMetadataRemoval() throws {
        let folder = try workingDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("fixture.png")
        try makeImage(at: source, withGPS: true)
        let original = try Data(contentsOf: source)
        let jpg = try XCTUnwrap(StudioNativeFileBridge.execute(
            task: .convertToJPEG, files: [source], destinationFolder: folder).first)
        let jpgURL = folder.appendingPathComponent(jpg.filename)
        let jpgSource = try XCTUnwrap(CGImageSourceCreateWithURL(jpgURL as CFURL, nil))
        let jpgProperties = CGImageSourceCopyPropertiesAtIndex(jpgSource, 0, nil) as? [String: Any] ?? [:]
        XCTAssertNil(jpgProperties[kCGImagePropertyGPSDictionary as String])
        let jpegType = try XCTUnwrap(CGImageSourceGetType(jpgSource))
        XCTAssertTrue(CFEqual(jpegType, UTType.jpeg.identifier as CFString))
        let png = try XCTUnwrap(StudioNativeFileBridge.execute(
            task: .convertToPNG, files: [jpgURL], destinationFolder: folder).first)
        let pngSource = try XCTUnwrap(CGImageSourceCreateWithURL(
            folder.appendingPathComponent(png.filename) as CFURL, nil))
        let pngType = try XCTUnwrap(CGImageSourceGetType(pngSource))
        XCTAssertTrue(CFEqual(pngType, UTType.png.identifier as CFString))
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testGeneratedLargePrintImageOCR() throws {
        let folder = try workingDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("printed-text.png")
        try makeImage(at: url, text: "HELLO WORLD 2026")
        let result = try StudioDocumentBridge.extract(url: url)
        XCTAssertEqual(result.pages.count, 1)
        XCTAssertEqual(result.pages.first?.origin, .visionOCR)
        XCTAssertTrue(result.text.localizedCaseInsensitiveContains("HELLO"),
                      "Generated high-contrast text should be recognized")
    }

    func testScannedPDFUsesOCRRatherThanClaimingEmbeddedText() throws {
        let folder = try workingDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let imageURL = folder.appendingPathComponent("scan.png")
        try makeImage(at: imageURL, text: "HELLO WORLD 2026")

        // Produce a scanned page directly with Core Graphics. Its only
        // content is an embedded raster image: no hidden/selectable text.
        // This also makes its size and orientation explicit rather than
        // depending on PDFKit's NSImage -> PDFPage sizing behavior.
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(imageURL as CFURL, nil))
        let bitmap = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        let url = folder.appendingPathComponent("scan.pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let pdfContext = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &mediaBox, nil))
        pdfContext.beginPDFPage(nil)
        pdfContext.setFillColor(CGColor(gray: 1, alpha: 1))
        pdfContext.fill(mediaBox)
        pdfContext.draw(bitmap, in: CGRect(x: 50, y: 160, width: 900, height: 180))
        pdfContext.endPDFPage()
        pdfContext.closePDF()

        let saved = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(saved.pageCount, 1)
        let savedPage = try XCTUnwrap(saved.page(at: 0))
        XCTAssertTrue((savedPage.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      "The fixture must contain an image, not a selectable text layer")

        let original = try Data(contentsOf: url)
        let result = try StudioDocumentBridge.extract(url: url)
        XCTAssertEqual(result.pages.count, 1)
        XCTAssertEqual(result.pages.first?.origin, .visionOCR)
        XCTAssertTrue(result.text.localizedCaseInsensitiveContains("HELLO"),
                      "Raster-only PDF OCR returned: \(String(result.text.prefix(300)).debugDescription)")
        XCTAssertEqual(try Data(contentsOf: url), original, "OCR must not edit the source PDF")
    }

    func testCorruptPDFIsRejectedWithoutChangingInputs() throws {
        let folder = try workingDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let good = folder.appendingPathComponent("good.pdf")
        let broken = folder.appendingPathComponent("broken.pdf")
        try makePDF(at: good, pages: 1, token: "GOOD", width: 400)
        try Data("not a real PDF".utf8).write(to: broken)
        let original = try Data(contentsOf: good)
        XCTAssertThrowsError(try StudioNativeFileBridge.execute(
            task: .mergePDFs, files: [good, broken], destinationFolder: folder))
        XCTAssertEqual(try Data(contentsOf: good), original)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: folder.appendingPathComponent("Combined-LibreReplace.pdf").path))
    }
    #endif
}
