import Foundation
#if os(macOS)
import ImageIO
import Vision
#endif

public struct StudioOCRResult: Sendable, Equatable {
    public let text: String
    public let recognizedLineCount: Int
    public init(text: String, recognizedLineCount: Int) {
        self.text = text
        self.recognizedLineCount = recognizedLineCount
    }
}

public enum StudioOCRError: LocalizedError, Sendable {
    case unsupportedPlatform
    case invalidInput
    case fileTooLarge
    case imageTooLarge
    case unreadableImage
    case noText

    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform: "Image OCR is supported on macOS only."
        case .invalidInput: "Choose a regular PNG, JPEG, HEIC, or TIFF image file."
        case .fileTooLarge: "Image exceeds the 25 MB input limit."
        case .imageTooLarge: "Image dimensions exceed the 40-megapixel safety limit."
        case .unreadableImage: "This image cannot be decoded. Try a PNG or JPEG instead."
        case .noText: "No readable text was found in this image."
        }
    }
}

/// First real Missing-Feature Bridge. It reads only a user-selected image and
/// returns text in memory. It never uploads, installs software, or writes a file.
public enum StudioOCRBridge {
    public static func recognize(imageAt url: URL) throws -> StudioOCRResult {
        #if os(macOS)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw StudioOCRError.invalidInput }
        guard let size = values.fileSize, size > 0, size <= 25 * 1024 * 1024 else { throw StudioOCRError.fileTooLarge }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?,
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              w > 0, h > 0 else { throw StudioOCRError.unreadableImage }
        guard w <= 40_000_000 / h else { throw StudioOCRError.imageTooLarge }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw StudioOCRError.unreadableImage }
        try Task<Never, Never>.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        try Task<Never, Never>.checkCancellation()
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw StudioOCRError.noText }
        return StudioOCRResult(text: text, recognizedLineCount: lines.count)
        #else
        throw StudioOCRError.unsupportedPlatform
        #endif
    }
}
