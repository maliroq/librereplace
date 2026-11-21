import Foundation
import XCTest
@testable import LibreReplaceCore
#if os(macOS)
import AppKit
import CoreGraphics
import CoreText
import PDFKit
#endif

final class StudioPDFRescueTests: XCTestCase {
    func testPortablePDFRescuePolicy() throws {
        let small = StudioPDFRescueInput(filename: "a.PDF", byteCount: 1024, pages: 250)
        let second = StudioPDFRescueInput(filename: "b.pdf", byteCount: 1024, pages: 250)
        XCTAssertNoThrow(try StudioPDFRescuePolicy.validate([small, second]))
        XCTAssertThrowsError(try StudioPDFRescuePolicy.validate([small]))
        XCTAssertThrowsError(try StudioPDFRescuePolicy.validate(Array(repeating: small, count: 9)))
        XCTAssertThrowsError(try StudioPDFRescuePolicy.validate([small, .init(filename: "b.pdf", byteCount: 512, pages: 251)]))
        XCTAssertThrowsError(try StudioPDFRescuePolicy.validate([small, .init(filename: "image.png", byteCount: 512, pages: 1)]))
        XCTAssertThrowsError(try StudioPDFRescuePolicy.validate([small, .init(filename: "b.pdf", byteCount: 151 * 1024 * 1024, pages: 1)]))
    }

    func testPortableSizeOverflowIsRejected() throws {
        let huge = StudioPDFRescueInput(filename: "a.pdf", byteCount: Int.max, pages: Int.max)
        let normal = StudioPDFRescueInput(filename: "b.pdf", byteCount: 512, pages: 2)
        XCTAssertThrowsError(try StudioPDFRescuePolicy.validate([huge, normal]))
    }

    #if os(macOS)
    private func folder() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lr-rescue-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func createDigitalPDF(at file: URL, token: String) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(file as CFURL, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.textPosition = CGPoint(x: 54, y: 450)
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: token,
            attributes: [.font: NSFont.boldSystemFont(ofSize: 38)]))
        CTLineDraw(line, context)
        context.endPDFPage()
        context.closePDF()
        let doc = try XCTUnwrap(PDFDocument(url: file))
        XCTAssertEqual(doc.pageCount, 1)
        XCTAssertTrue(doc.page(at: 0)?.string?.contains(token) == true)
    }

    private func createScannedPDF(at file: URL) throws {
        let w = 1500, h = 300
        let graphics = try XCTUnwrap(CGContext(data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        graphics.setFillColor(CGColor(gray: 1, alpha: 1))
        graphics.fill(CGRect(x: 0, y: 0, width: w, height: h))
        graphics.setFillColor(CGColor(gray: 0, alpha: 1))
        graphics.textPosition = CGPoint(x: 75, y: 105)
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: "HELLO SEARCHABLE PDF",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 88)]))
        CTLineDraw(line, graphics)
        let image = try XCTUnwrap(graphics.makeImage())
        var pageBox = CGRect(x: 0, y: 0, width: 900, height: 400)
        let pdf = try XCTUnwrap(CGContext(file as CFURL, mediaBox: &pageBox, nil))
        pdf.beginPDFPage(nil)
        pdf.setFillColor(CGColor(gray: 1, alpha: 1))
        pdf.fill(pageBox)
        pdf.draw(image, in: CGRect(x: 40, y: 110, width: 820, height: 164))
        pdf.endPDFPage()
        pdf.closePDF()
        let source = try XCTUnwrap(PDFDocument(url: file))
        XCTAssertTrue((source.page(at: 0)?.string ?? "").isEmpty, "Fixture must contain only raster pixels")
    }

    func testScannedAndDigitalBecomeOneVerifiedSearchablePDF() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let digital = directory.appendingPathComponent("first.pdf")
        let scanned = directory.appendingPathComponent("second.pdf")
        try createDigitalPDF(at: digital, token: "DIGITAL FIRST PAGE")
        try createScannedPDF(at: scanned)
        let originals = try [digital, scanned].map { try Data(contentsOf: $0) }
        let result = try StudioPDFRescueBridge.create(inputs: [digital, scanned], destinationFolder: directory)
        XCTAssertEqual(result.pageCount, 2)
        XCTAssertEqual(result.sourceCount, 2)
        XCTAssertEqual(result.scannedPagesMadeSearchable, 1)
        let created = directory.appendingPathComponent(result.filename)
        let output = try XCTUnwrap(PDFDocument(url: created))
        XCTAssertEqual(output.pageCount, 2)
        XCTAssertTrue(output.page(at: 0)?.string?.contains("DIGITAL") == true)
        XCTAssertTrue(output.page(at: 1)?.string?.localizedCaseInsensitiveContains("HELLO") == true)
        XCTAssertEqual(try [digital, scanned].map { try Data(contentsOf: $0) }, originals)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(leftovers.contains { $0.hasPrefix(".lr-pdf-rescue-") })
        XCTAssertEqual(leftovers.count, 3, "Only the two originals and one complete output should remain")
    }

    func testDigitalOnlyCombinesAndNeverOverwritesEarlierOutput() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("one.pdf")
        let second = directory.appendingPathComponent("two.pdf")
        try createDigitalPDF(at: first, token: "FIRST DIGITAL")
        try createDigitalPDF(at: second, token: "SECOND DIGITAL")
        let firstResult = try StudioPDFRescueBridge.create(inputs: [first, second], destinationFolder: directory)
        XCTAssertEqual(firstResult.scannedPagesMadeSearchable, 0)
        let originalOutput = directory.appendingPathComponent(firstResult.filename)
        let firstOutputBytes = try Data(contentsOf: originalOutput)
        let secondResult = try StudioPDFRescueBridge.create(inputs: [second, first], destinationFolder: directory)
        XCTAssertNotEqual(firstResult.filename, secondResult.filename)
        XCTAssertEqual(try Data(contentsOf: originalOutput), firstOutputBytes)
        let checked = try XCTUnwrap(PDFDocument(url: directory.appendingPathComponent(secondResult.filename)))
        XCTAssertTrue(checked.page(at: 0)?.string?.contains("SECOND") == true)
        XCTAssertTrue(checked.page(at: 1)?.string?.contains("FIRST") == true)
    }

    func testCorruptPDFDoesNotPublishPartialOutputOrModifySource() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let good = directory.appendingPathComponent("good.pdf")
        let broken = directory.appendingPathComponent("broken.pdf")
        try createDigitalPDF(at: good, token: "GOOD")
        try Data("not a pdf".utf8).write(to: broken)
        let saved = try Data(contentsOf: good)
        XCTAssertThrowsError(try StudioPDFRescueBridge.create(inputs: [good, broken], destinationFolder: directory))
        XCTAssertEqual(try Data(contentsOf: good), saved)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(names.count, 2)
        XCTAssertFalse(names.contains { $0.hasPrefix(".lr-pdf-rescue-") })
    }

    func testRepeatedInputIsRejectedWithoutAnyChanges() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let good = directory.appendingPathComponent("good.pdf")
        try createDigitalPDF(at: good, token: "SINGLE SOURCE")
        XCTAssertThrowsError(try StudioPDFRescueBridge.create(inputs: [good, good], destinationFolder: directory))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
    }
    #endif
}
