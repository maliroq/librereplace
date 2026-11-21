import Foundation
#if os(macOS)
import CoreGraphics
import CoreImage
import ImageIO
import PDFKit
import UniformTypeIdentifiers
#endif

/// Native file actions are intentionally constrained: no shell, no network,
/// no third-party executables, and never overwrite an input file.
public enum StudioFileTask: String, CaseIterable, Sendable {
    case mergePDFs = "Combine PDFs"
    case convertToPNG = "Images to PNG"
    case convertToJPEG = "Images to JPEG"

    public var isPDF: Bool { self == .mergePDFs }
    public var outputExtension: String { self == .mergePDFs ? "pdf" : (self == .convertToPNG ? "png" : "jpg") }
}

public struct StudioFileInput: Sendable, Equatable {
    public let filename: String
    public let byteCount: Int
    public init(filename: String, byteCount: Int) {
        self.filename = filename
        self.byteCount = byteCount
    }
    public var extensionLowercased: String { (filename as NSString).pathExtension.lowercased() }
}

public struct StudioFileOutput: Sendable, Equatable {
    public let filename: String
    public let byteCount: Int
    public let pageCount: Int?
    public init(filename: String, byteCount: Int, pageCount: Int? = nil) {
        self.filename = filename
        self.byteCount = byteCount
        self.pageCount = pageCount
    }
}

public enum StudioFileError: LocalizedError, Sendable {
    case unsupportedPlatform, noFiles, tooManyFiles, invalidInput, inputTooLarge
    case tooManyPages, invalidPDF, lockedPDF, cannotDecodeImage
    case invalidDestination, outputFailed, verificationFailed
    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform: "This local tool requires macOS."
        case .noFiles: "Choose files to work with first."
        case .tooManyFiles: "Choose no more than 16 files at a time."
        case .invalidInput: "One of these files is not supported or cannot be read."
        case .inputTooLarge: "A file or the combined selection exceeds the processing limit."
        case .tooManyPages: "This selection contains more than 500 PDF pages. Try smaller groups."
        case .invalidPDF: "A PDF could not be opened."
        case .lockedPDF: "Password-protected PDFs cannot be combined here."
        case .cannotDecodeImage: "An image could not be decoded or contains an unsupported format."
        case .invalidDestination: "Choose a writable output folder that isn't one of the source files."
        case .outputFailed: "LibreReplace could not create the new file. Your originals were not changed."
        case .verificationFailed: "The new file failed the output check. Your originals were not changed."
        }
    }
}

/// Pure input policy: used by the UI, the native executor and Linux/macOS tests.
public enum StudioFilePolicy {
    public static let maximumInputs = 16
    public static let maximumPDFPages = 500
    public static let maximumPDFBytes = 150 * 1024 * 1024
    public static let maximumCombinedPDFBytes = 250 * 1024 * 1024
    public static let maximumImageBytes = 25 * 1024 * 1024
    public static let maximumImagePixels = 40_000_000

    public static func validate(_ files: [StudioFileInput], for task: StudioFileTask) throws {
        guard !files.isEmpty else { throw StudioFileError.noFiles }
        guard files.count <= maximumInputs else { throw StudioFileError.tooManyFiles }
        if task.isPDF {
            guard files.count >= 2 else { throw StudioFileError.noFiles }
            var total = 0
            for file in files {
                guard file.extensionLowercased == "pdf", file.byteCount > 0 else { throw StudioFileError.invalidInput }
                guard file.byteCount <= maximumPDFBytes else { throw StudioFileError.inputTooLarge }
                let (sum, overflow) = total.addingReportingOverflow(file.byteCount)
                guard !overflow, sum <= maximumCombinedPDFBytes else { throw StudioFileError.inputTooLarge }
                total = sum
            }
        } else {
            let supported = Set(["png", "jpg", "jpeg", "heic", "tif", "tiff"])
            for file in files {
                guard supported.contains(file.extensionLowercased), file.byteCount > 0 else { throw StudioFileError.invalidInput }
                guard file.byteCount <= maximumImageBytes else { throw StudioFileError.inputTooLarge }
            }
        }
    }

    public static func resultFilename(for original: String, task: StudioFileTask) -> String {
        let base = (original as NSString).lastPathComponent
        let stem = (base as NSString).deletingPathExtension
        let normalized = String(stem.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        let safe = normalized.isEmpty || normalized == "." || normalized == ".." ? "Converted" : normalized
        return String(safe.prefix(90)) + "-LibreReplace." + task.outputExtension
    }
}

public enum StudioNativeFileBridge {
    /// The selected output folder is used solely to save newly created files.
    /// The original inputs are never edited, moved or removed.
    public static func execute(task: StudioFileTask, files: [URL], destinationFolder: URL,
                               progress: (@Sendable (Int, Int) -> Void)? = nil) throws -> [StudioFileOutput] {
        #if os(macOS)
        guard destinationFolder.isFileURL else { throw StudioFileError.invalidDestination }
        let directory = try destinationFolder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard directory.isDirectory == true, directory.isSymbolicLink != true else { throw StudioFileError.invalidDestination }
        let inputs = try files.map { url -> StudioFileInput in
            guard url.isFileURL else { throw StudioFileError.invalidInput }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize else { throw StudioFileError.invalidInput }
            return StudioFileInput(filename: url.lastPathComponent, byteCount: size)
        }
        try StudioFilePolicy.validate(inputs, for: task)
        try Task<Never, Never>.checkCancellation()
        return task.isPDF
            ? [try combinePDFs(files, destinationFolder: destinationFolder, progress: progress)]
            : try convertImages(files, task: task, destinationFolder: destinationFolder, progress: progress)
        #else
        throw StudioFileError.unsupportedPlatform
        #endif
    }

    #if os(macOS)
    private static func combinePDFs(_ files: [URL], destinationFolder folder: URL,
                                    progress: (@Sendable (Int, Int) -> Void)?) throws -> StudioFileOutput {
        let combined = PDFDocument()
        var total = 0
        for (index, url) in files.enumerated() {
            try Task<Never, Never>.checkCancellation()
            guard let document = PDFDocument(url: url) else { throw StudioFileError.invalidPDF }
            guard !document.isEncrypted, !document.isLocked else { throw StudioFileError.lockedPDF }
            guard document.pageCount > 0 else { throw StudioFileError.invalidPDF }
            guard total + document.pageCount <= StudioFilePolicy.maximumPDFPages else { throw StudioFileError.tooManyPages }
            for pageIndex in 0..<document.pageCount {
                try Task<Never, Never>.checkCancellation()
                guard let page = document.page(at: pageIndex) else { throw StudioFileError.invalidPDF }
                combined.insert(page, at: total)
                total += 1
            }
            progress?(index + 1, files.count)
        }
        let temp = folder.appendingPathComponent(".lr-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: temp) }
        guard combined.write(to: temp) else { throw StudioFileError.outputFailed }
        guard let verified = PDFDocument(url: temp), !verified.isLocked, verified.pageCount == total else {
            throw StudioFileError.verificationFailed
        }
        let output = try publishNewFile(temp, in: folder, named: "Combined-LibreReplace.pdf")
        return try verifyOutput(output, pages: total)
    }

    private static func convertImages(_ files: [URL], task: StudioFileTask, destinationFolder folder: URL,
                                      progress: (@Sendable (Int, Int) -> Void)?) throws -> [StudioFileOutput] {
        var results: [StudioFileOutput] = []
        for (index, url) in files.enumerated() {
            try Task<Never, Never>.checkCancellation()
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  CGImageSourceGetCount(source) == 1,
                  let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?,
                  let width = (info[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                  let height = (info[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
                  width > 0, height > 0, width <= StudioFilePolicy.maximumImagePixels / height
            else { throw StudioFileError.cannotDecodeImage }
            let temp = folder.appendingPathComponent(".lr-\(UUID().uuidString).\(task.outputExtension)")
            defer { try? FileManager.default.removeItem(at: temp) }
            let type = task == .convertToPNG ? UTType.png : UTType.jpeg
            guard let destination = CGImageDestinationCreateWithURL(temp as CFURL, type.identifier as CFString, 1, nil) else {
                throw StudioFileError.outputFailed
            }
            // Bake EXIF orientation into the pixels before export. Creating a
            // fresh image prevents private EXIF/GPS metadata from leaking into
            // converted files, unlike AddImageFromSource.
            guard let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw StudioFileError.cannotDecodeImage
            }
            let orientation = (info[kCGImagePropertyOrientation] as? NSNumber)?.int32Value ?? 1
            guard (1...8).contains(orientation) else { throw StudioFileError.cannotDecodeImage }
            let oriented = CIImage(cgImage: decoded).oriented(forExifOrientation: orientation)
            let extent = oriented.extent.integral
            guard extent.width > 0, extent.height > 0,
                  extent.width * extent.height <= CGFloat(StudioFilePolicy.maximumImagePixels),
                  let rendered = CIContext().createCGImage(oriented, from: extent) else {
                throw StudioFileError.cannotDecodeImage
            }
            let options: [CFString: Any] = task == .convertToJPEG
                ? [kCGImageDestinationLossyCompressionQuality: 0.88,
                   kCGImageDestinationBackgroundColor: CGColor(gray: 1, alpha: 1)] : [:]
            CGImageDestinationAddImage(destination, rendered, options as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw StudioFileError.outputFailed }
            guard let saved = CGImageSourceCreateWithURL(temp as CFURL, nil),
                  CGImageSourceGetCount(saved) == 1,
                  let outputType = CGImageSourceGetType(saved),
                  CFEqual(outputType, type.identifier as CFString),
                  let newImage = CGImageSourceCreateImageAtIndex(saved, 0, nil),
                  newImage.width == rendered.width, newImage.height == rendered.height else {
                throw StudioFileError.verificationFailed
            }
            let filename = StudioFilePolicy.resultFilename(for: url.lastPathComponent, task: task)
            let published = try publishNewFile(temp, in: folder, named: filename)
            results.append(try verifyOutput(published))
            progress?(index + 1, files.count)
        }
        return results
    }

    /// Use an atomic hard link in the same directory: creation fails rather than
    /// replacing an existing file, including an attacker-created symlink.
    private static func publishNewFile(_ temporary: URL, in folder: URL, named name: String) throws -> URL {
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for number in 0..<1000 {
            try Task<Never, Never>.checkCancellation()
            let filename = number == 0 ? name : "\(stem)-\(number + 1).\(ext)"
            let target = folder.appendingPathComponent(filename)
            do {
                try FileManager.default.linkItem(at: temporary, to: target)
                return target
            } catch {
                if FileManager.default.fileExists(atPath: target.path) ||
                   (try? FileManager.default.destinationOfSymbolicLink(atPath: target.path)) != nil {
                    continue
                }
                throw StudioFileError.outputFailed
            }
        }
        throw StudioFileError.outputFailed
    }

    private static func verifyOutput(_ output: URL, pages: Int? = nil) throws -> StudioFileOutput {
        let values = try output.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let bytes = values.fileSize, bytes > 0 else { throw StudioFileError.verificationFailed }
        return StudioFileOutput(filename: output.lastPathComponent, byteCount: bytes, pageCount: pages)
    }
    #endif
}
