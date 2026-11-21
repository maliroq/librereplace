import Foundation

/// A built-in tool is offered only for a bridge that explicitly exists in the
/// selected plan. This is navigation, not evidence that the task succeeded.
public struct StudioLocalToolRoute: Equatable, Sendable {
    public enum Mode: String, Sendable {
        case extract, merge, searchable, rescue, convert
    }

    public let mode: Mode
    public let buttonTitle: String
    public let detail: String

    public static func forPlan(_ plan: StudioComposedPlan) -> StudioLocalToolRoute? {
        let bridgeIDs = Set(plan.components.filter { $0.kind == .builtInBridge }.map(\.id))
        if bridgeIDs.contains("bridge.image-ocr") {
            return StudioLocalToolRoute(mode: .extract,
                buttonTitle: "Try image text extraction",
                detail: "Choose a sample screenshot or image. Save the extracted text in Tools before returning here.")
        }
        if bridgeIDs.contains("bridge.document-text-ocr") {
            return StudioLocalToolRoute(mode: .extract,
                buttonTitle: "Try document text extraction",
                detail: "Choose a sample PDF in Tools. It can extract text, but this isn't a full Acrobat replacement.")
        }
        return nil
    }
}
