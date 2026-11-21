import XCTest
import Foundation
@testable import LibreReplaceCore

final class StudioDocumentPipelineTests: XCTestCase {
    func testZeroDocumentsNeverEnablesFalseExport() {
        XCTAssertEqual(StudioTextExporter.render([], as: .text), "")
        XCTAssertEqual(StudioTextExporter.render([], as: .markdown), "")
    }

    func testDocumentTextPreservesMultiplePages() {
        let result = StudioDocumentResult(filename: "sample.pdf", pages: [
            .init(number: 1, text: "First", origin: .embeddedPDFText, recognizedLineCount: 1),
            .init(number: 2, text: "Second", origin: .visionOCR, recognizedLineCount: 1)
        ])
        XCTAssertEqual(result.text, "First\n\nSecond")
        XCTAssertEqual(result.recognizedPages, 1)
        let plain = StudioTextExporter.render([result], as: .text)
        XCTAssertTrue(plain.contains("Page 1\nFirst"))
        XCTAssertTrue(plain.contains("Page 2\nSecond"))
    }

    func testMarkdownSafelyFencesUntrustedRecognizedText() {
        let result = StudioDocumentResult(filename: "#<scanned>.pdf", pages: [
            .init(number: 1, text: "before\n```\n<script>hi</script>\nafter", origin: .visionOCR, recognizedLineCount: 4)
        ])
        let markdown = StudioTextExporter.render([result], as: .markdown)
        XCTAssertTrue(markdown.contains("## \\#&lt;scanned&gt;.pdf"))
        XCTAssertTrue(markdown.contains("````\nbefore\n```"))
        XCTAssertTrue(markdown.contains("after\n````"))
    }

    func testMultiDocumentExportsStayInInputOrder() {
        let a = StudioDocumentResult(filename: "one.png", pages: [
            .init(number: 1, text: "ALPHA", origin: .visionOCR, recognizedLineCount: 1)])
        let b = StudioDocumentResult(filename: "two.png", pages: [
            .init(number: 1, text: "BETA", origin: .visionOCR, recognizedLineCount: 1)])
        let output = StudioTextExporter.render([a, b], as: .markdown)
        XCTAssertLessThan(try! XCTUnwrap(output.range(of: "ALPHA")?.lowerBound),
                          try! XCTUnwrap(output.range(of: "BETA")?.lowerBound))
        XCTAssertEqual(output, StudioTextExporter.render([a, b], as: .markdown))
    }

    func testRedundantOCRProviderIsNotRecommended() {
        let app = StudioComponent(id: "app", name: "App", kind: .openSourceApp,
            capabilities: [.init("capture", .full, evidence: .documented), .init("ocr", .full, evidence: .documented)])
        let bridge = StudioComponent(id: "bridge", name: "Bridge", kind: .builtInBridge,
            capabilities: [.init("ocr", .full, evidence: .documented)])
        let result = StudioFreeStackComposer.compose(components: [app, bridge], request: .init(requirements: [
            .init("capture"), .init("ocr")], macOSMajor: 14))
        XCTAssertFalse(result.contains { Set($0.components.map(\.id)) == ["app", "bridge"] })
        XCTAssertTrue(result.contains { $0.components.map(\.id) == ["app"] })
    }

    func testDistinctLocalOCRRequirementJustifiesBridge() {
        let app = StudioComponent(id: "app", name: "App", kind: .openSourceApp,
            capabilities: [.init("capture", .full, evidence: .documented), .init("ocr", .full, evidence: .documented)])
        let bridge = StudioComponent(id: "bridge", name: "Bridge", kind: .builtInBridge,
            capabilities: [.init("ocr", .full, evidence: .documented), .init("local-image-ocr", .full, evidence: .documented)])
        let result = StudioFreeStackComposer.compose(components: [app, bridge], request: .init(requirements: [
            .init("capture"), .init("ocr"), .init("local-image-ocr")], macOSMajor: 14))
        XCTAssertTrue(result.contains { $0.readiness == .eligibleForTrial && $0.components.count == 2 })
    }

    func testPreflightIsExplicitlyNonExecuting() throws {
        let app = StudioComponent(id: "app", name: "App", kind: .openSourceApp,
            capabilities: [.init("capture", .full, evidence: .documented)],
            installation: .homebrewCask, packageToken: "safe-app")
        let plan = try XCTUnwrap(StudioFreeStackComposer.compose(components: [app],
            request: .init(requirements: [.init("capture")], macOSMajor: 14)).first)
        let preview = StudioSwitchPlanner.preview(plan)
        XCTAssertFalse(preview.hasAutomaticChanges)
        XCTAssertTrue(preview.readyForUserReview)
        XCTAssertTrue(preview.steps.contains { $0.detail.contains("brew install --cask safe-app") })
    }

    func testUntrustedPackageIdentifierBlocksPreflight() throws {
        let app = StudioComponent(id: "app", name: "App", kind: .openSourceApp,
            capabilities: [.init("capture", .full, evidence: .documented)],
            installation: .homebrewCask, packageToken: "foo;rm -rf /tmp")
        let plan = try XCTUnwrap(StudioFreeStackComposer.compose(components: [app],
            request: .init(requirements: [.init("capture")], macOSMajor: 14)).first)
        XCTAssertFalse(StudioSwitchPlanner.preview(plan).readyForUserReview)
    }

    func testRecipeExportIsDeterministicAndRoundTrips() throws {
        let app = StudioComponent(id: "app", name: "App", kind: .openSourceApp,
            capabilities: [.init("capture", .full, evidence: .documented)],
            installation: .homebrewCask, packageToken: "safe-app")
        let plan = try XCTUnwrap(StudioFreeStackComposer.compose(components: [app],
            request: .init(requirements: [.init("capture")], macOSMajor: 14)).first)
        let a = try StudioRecipeFactory.makeDraft(for: plan, workflow: "Capture a screenshot")
        let b = try StudioRecipeFactory.makeDraft(for: plan, workflow: "Capture a screenshot")
        XCTAssertEqual(a.data, b.data)
        XCTAssertEqual(a.recipe.id, b.recipe.id)
        XCTAssertEqual(a.recipe.actions.first?.kind, .installHomebrewCask)
        let read = try StudioSafeRecipeLoader.decodeAndValidate(a.data, catalog: [app])
        XCTAssertEqual(read.componentIDs, ["app"])
    }

    #if os(macOS)
    func testInvalidDocumentFailsClosed() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not a PDF".utf8).write(to: url)
        XCTAssertThrowsError(try StudioDocumentBridge.extract(url: url))
    }
    #endif
}
