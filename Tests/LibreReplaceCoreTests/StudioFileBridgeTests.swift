import Foundation
import XCTest
@testable import LibreReplaceCore
#if os(macOS)
import AppKit
import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers
#endif

final class StudioFileBridgeTests: XCTestCase {
    func testPDFSelectionRequiresTwoInputs() {
        XCTAssertThrowsError(try StudioFilePolicy.validate([.init(filename: "x.pdf", byteCount: 100)], for: .mergePDFs))
    }
    func testPDFSelectionRejectsNonPDF() {
        XCTAssertThrowsError(try StudioFilePolicy.validate([.init(filename: "x.pdf", byteCount: 100), .init(filename: "z.png", byteCount: 100)], for: .mergePDFs))
    }
    func testCombinedPDFSizeBudget() {
        let a = StudioFileInput(filename: "a.pdf", byteCount: 145 * 1024 * 1024)
        let b = StudioFileInput(filename: "b.pdf", byteCount: 145 * 1024 * 1024)
        XCTAssertThrowsError(try StudioFilePolicy.validate([a,b], for: .mergePDFs))
    }
    func testImageFormatsAndLimit() {
        for suffix in ["png", "jpeg", "jpg", "heic", "tif", "tiff"] {
            XCTAssertNoThrow(try StudioFilePolicy.validate([.init(filename: "photo.\(suffix)", byteCount: 200)], for: .convertToPNG))
        }
        XCTAssertThrowsError(try StudioFilePolicy.validate([.init(filename: "photo.svg", byteCount: 200)], for: .convertToJPEG))
        XCTAssertThrowsError(try StudioFilePolicy.validate([.init(filename: "photo.png", byteCount: StudioFilePolicy.maximumImageBytes + 1)], for: .convertToPNG))
    }
    func testInputCountLimit() {
        XCTAssertThrowsError(try StudioFilePolicy.validate((0..<17).map { .init(filename: "\($0).png", byteCount: 10) }, for: .convertToPNG))
    }
    func testFilenamesAreDerivedWithoutPaths() {
        XCTAssertEqual(StudioFilePolicy.resultFilename(for: "my photo.heic", task: .convertToJPEG), "my photo-LibreReplace.jpg")
        XCTAssertEqual(StudioFilePolicy.resultFilename(for: "scan.png", task: .convertToPNG), "scan-LibreReplace.png")
        XCTAssertEqual(StudioFilePolicy.resultFilename(for: "../../secret.png", task: .convertToJPEG), "secret-LibreReplace.jpg")
    }
    func testImageWithoutFiles() {
        XCTAssertThrowsError(try StudioFilePolicy.validate([], for: .convertToJPEG))
    }
    #if os(macOS)
    func testRealPDFMergePreservesSourceAndPageOrder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lr-merge-test-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var sourceURLs: [URL] = []
        for index in 0..<2 {
            let doc = PDFDocument()
            let pageImage = NSImage(size: NSSize(width: CGFloat(100 + index * 50), height: 90), flipped: false) { rect in
                NSColor.white.setFill(); NSBezierPath(rect: rect).fill(); return true
            }
            guard let page = PDFPage(image: pageImage) else { XCTFail("Could not create fixture page"); return }
            doc.insert(page, at: 0)
            let url = folder.appendingPathComponent("source\(index).pdf")
            XCTAssertTrue(doc.write(to: url))
            sourceURLs.append(url)
        }
        let originals = try sourceURLs.map { try Data(contentsOf: $0) }
        let outputs = try StudioNativeFileBridge.execute(task: .mergePDFs, files: sourceURLs, destinationFolder: folder)
        XCTAssertEqual(outputs.count, 1)
        XCTAssertEqual(outputs.first?.pageCount, 2)
        let doc = try XCTUnwrap(PDFDocument(url: folder.appendingPathComponent(try XCTUnwrap(outputs.first?.filename))))
        XCTAssertEqual(doc.pageCount, 2)
        XCTAssertEqual(doc.page(at: 0)?.bounds(for: .mediaBox).width, 100)
        XCTAssertEqual(doc.page(at: 1)?.bounds(for: .mediaBox).width, 150)
        XCTAssertEqual(try sourceURLs.map { try Data(contentsOf: $0) }, originals)
    }
    func testRealPNGtoJPEGAndUniqueOutput() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lr-image-test-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appendingPathComponent("test.png")
        guard let context = CGContext(data: nil, width: 20, height: 30, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let dest = CGImageDestinationCreateWithURL(original as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { XCTFail("Could not create image fixture"); return }
        context.setFillColor(CGColor(red: 0.4, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
        guard let image = context.makeImage() else { XCTFail("No image"); return }
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        let originalBytes = try Data(contentsOf: original)
        let first = try StudioNativeFileBridge.execute(task: .convertToJPEG, files: [original], destinationFolder: folder)
        let second = try StudioNativeFileBridge.execute(task: .convertToJPEG, files: [original], destinationFolder: folder)
        XCTAssertNotEqual(first[0].filename, second[0].filename)
        XCTAssertEqual(try Data(contentsOf: original), originalBytes)
    }
    #endif
}
