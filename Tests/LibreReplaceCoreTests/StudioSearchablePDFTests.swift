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

final class StudioSearchablePDFTests: XCTestCase {
    func testSearchablePDFLimits() throws {
        XCTAssertNoThrow(try StudioSearchablePDFPolicy.validate(pageCount: 500, inputBytes: 1024))
        XCTAssertThrowsError(try StudioSearchablePDFPolicy.validate(pageCount: 501, inputBytes: 1024))
        XCTAssertThrowsError(try StudioSearchablePDFPolicy.validate(pageCount: 0, inputBytes: 1024))
        XCTAssertThrowsError(try StudioSearchablePDFPolicy.validate(pageCount: 1, inputBytes: 151 * 1024 * 1024))
    }

    func testRenderedSizePolicy() throws {
        let (w, h) = try StudioSearchablePDFPolicy.imageDimensions(for: 612, 792)
        XCTAssertEqual(w, 1224)
        XCTAssertEqual(h, 1584)
        XCTAssertThrowsError(try StudioSearchablePDFPolicy.imageDimensions(for: 3000, 792))
        XCTAssertThrowsError(try StudioSearchablePDFPolicy.imageDimensions(for: 0, 792))
        XCTAssertThrowsError(try StudioSearchablePDFPolicy.imageDimensions(for: .infinity, 100))
    }

    #if os(macOS)
    private func makeFolder() throws -> URL {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("lr-searchable-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }

    /// A scanned PDF generated entirely in the test: its visible text is only
    /// image pixels. This verifies PDF OCR, an invisible text layer and PDFKit
    /// extraction independently of the Vision recognition result itself.
    private func createScannedPDF(at url: URL) throws {
        let width = 1500, height = 300
        guard let imageContext = CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw NSError(domain: "Fixture", code: 1)
        }
        imageContext.setFillColor(CGColor(gray: 1, alpha: 1))
        imageContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
        imageContext.setFillColor(CGColor(gray: 0, alpha: 1))
        imageContext.textPosition = CGPoint(x: 75, y: 105)
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: "HELLO SEARCHABLE PDF",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 88)]))
        CTLineDraw(line, imageContext)
        guard let image = imageContext.makeImage() else { throw NSError(domain: "Fixture", code: 2) }
        var pageBox = CGRect(x: 0, y: 0, width: 900, height: 400)
        guard let pdf = CGContext(url as CFURL, mediaBox: &pageBox, nil) else {
            throw NSError(domain: "Fixture", code: 3)
        }
        pdf.beginPDFPage(nil)
        pdf.setFillColor(CGColor(gray: 1, alpha: 1))
        pdf.fill(pageBox)
        pdf.draw(image, in: CGRect(x: 40, y: 110, width: 820, height: 164))
        pdf.endPDFPage()
        pdf.closePDF()
        let initial = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(initial.pageCount, 1)
        XCTAssertTrue((initial.page(at: 0)?.string ?? "").isEmpty, "Fixture must be image-only")
    }

    func testScannedPDFBecomesSelectableAndOriginalIsUnchanged() throws {
        let directory = try makeFolder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("scan.pdf")
        try createScannedPDF(at: source)
        let before = try Data(contentsOf: source)
        let output = try StudioSearchablePDFBridge.create(input: source, destinationFolder: directory)
        XCTAssertEqual(output.pageCount, 1)
        XCTAssertEqual(output.newlySearchablePages, 1)
        let finished = directory.appendingPathComponent(output.filename)
        let parsed = try XCTUnwrap(PDFDocument(url: finished))
        let page = try XCTUnwrap(parsed.page(at: 0))
        XCTAssertTrue((page.string ?? "").localizedCaseInsensitiveContains("HELLO"),
                      "Independent PDFKit parser must see real searchable text")
        XCTAssertEqual(try Data(contentsOf: source), before, "Source bytes must be identical")
        XCTAssertNotEqual(finished, source)
    }

    func testCorruptedPDFIsRejectedWithoutOutput() throws {
        let directory = try makeFolder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("bad.pdf")
        let invalidData = Data("not a PDF".utf8)
        try invalidData.write(to: source)
        XCTAssertThrowsError(try StudioSearchablePDFBridge.create(input: source, destinationFolder: directory))
        XCTAssertEqual(try Data(contentsOf: source), invalidData)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil).count, 1)
    }
    #endif
}
