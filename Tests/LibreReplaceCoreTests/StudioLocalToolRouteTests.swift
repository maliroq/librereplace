import Foundation
import XCTest
@testable import LibreReplaceCore

final class StudioLocalToolRouteTests: XCTestCase {
    private func plan(_ components: [StudioComponent]) -> StudioComposedPlan {
        let requirements = [StudioCapabilityRequirement("ocr")]
        guard let result = StudioFreeStackComposer.assessExact(components: components,
            request: StudioComposeRequest(requirements: requirements, macOSMajor: 14)) else {
            preconditionFailure("Unexpected invalid test plan")
        }
        return result
    }

    func testImageOCRRoutesToExtractText() {
        let bridge = StudioComponent(id: "bridge.image-ocr", name: "LibreReplace Image OCR",
            kind: .builtInBridge, capabilities: [StudioCapabilityClaim("ocr", .full, evidence: .documented)])
        let route = StudioLocalToolRoute.forPlan(plan([bridge]))
        XCTAssertEqual(route?.mode, .extract)
        XCTAssertEqual(route?.buttonTitle, "Try image text extraction")
    }

    func testDocumentOCRRoutesToExtractTextNotPDFRescue() {
        let bridge = StudioComponent(id: "bridge.document-text-ocr", name: "LibreReplace Document OCR",
            kind: .builtInBridge, capabilities: [StudioCapabilityClaim("ocr", .partial, evidence: .documented)])
        let route = StudioLocalToolRoute.forPlan(plan([bridge]))
        XCTAssertEqual(route?.mode, .extract)
        XCTAssertEqual(route?.buttonTitle, "Try document text extraction")
    }

    func testNoMadeUpToolForUnsupportedComponent() {
        let app = StudioComponent(id: "app.test", name: "Test", kind: .openSourceApp,
            capabilities: [StudioCapabilityClaim("ocr", .full, evidence: .documented)])
        XCTAssertNil(StudioLocalToolRoute.forPlan(plan([app])))
    }

    func testUnknownBridgeCannotTriggerUnrelatedTool() {
        let bridge = StudioComponent(id: "bridge.unknown", name: "Unknown", kind: .builtInBridge,
            capabilities: [StudioCapabilityClaim("ocr", .full, evidence: .documented)])
        XCTAssertNil(StudioLocalToolRoute.forPlan(plan([bridge])))
    }
}
