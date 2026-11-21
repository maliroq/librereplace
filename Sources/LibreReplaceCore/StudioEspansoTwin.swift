import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

public enum StudioEspansoTwinError: LocalizedError, Sendable {
    case notApproved, noCompatibleMatches, existingSetup, invalidFolder, unsafePath, modifiedFile, missingGeneratedFile, corruptReceipt, operationFailed(String)
    public var errorDescription: String? {
        switch self {
        case .notApproved: "The setup was not approved."
        case .noCompatibleMatches: "No safe static text expansions were found in this export."
        case .existingSetup: "An Espanso setup is already saved. Restore or remove it before making another."
        case .invalidFolder: "Choose a valid Espanso configuration folder."
        case .unsafePath: "The selected configuration or setup folder contains a symbolic link."
        case .modifiedFile: "The generated expansion file has changed since LibreReplace created it. Nothing was removed."
        case .missingGeneratedFile: "The previously generated file could not be found. No other files were modified."
        case .corruptReceipt: "The saved configuration receipt could not be verified. No changes were made."
        case .operationFailed(let note): note
        }
    }
}

/// No snippet content is persisted in the receipt; all generated text remains
/// inside the user's chosen local Espanso configuration directory.
public struct StudioEspansoReceipt: Codable, Sendable, Equatable {
    public let id: UUID
    public let date: Date
    public let configRootPath: String
    public let generatedFilename: String
    public let fingerprint: String
    public let installedCount: Int
    public let excludedCount: Int
    public var generatedFile: URL {
        URL(fileURLWithPath: configRootPath, isDirectory: true)
            .appendingPathComponent("match", isDirectory: true)
            .appendingPathComponent(generatedFilename)
    }
}

public struct StudioEspansoPreview: Sendable {
    public let trial: StudioSnippetTrial
    public let configRoot: URL
    public var ready: Int { trial.readyCount }
    public var needsReview: Int { trial.needsReviewCount }
    public var blocked: Int { trial.blockedCount }
    public var total: Int { trial.findings.count }
}

public enum StudioEspansoTwin {
    /// The official default is Application Support; existing legacy/XDG
    /// directories are supported without silently choosing between two setups.
    public static func defaultConfigRoots(home: URL) -> [URL] {
        [home.appendingPathComponent("Library/Application Support/espanso", isDirectory: true),
         home.appendingPathComponent(".config/espanso", isDirectory: true)]
    }

    public static func preferredConfigRoot(home: URL, fileManager fm: FileManager = .default) throws -> URL {
        let candidates = defaultConfigRoots(home: home)
        let found = try candidates.filter { url in
            if fm.fileExists(atPath: url.path) {
                let attr = try fm.attributesOfItem(atPath: url.path)
                if attr[.type] as? FileAttributeType == .typeSymbolicLink { throw StudioEspansoTwinError.unsafePath }
                guard attr[.type] as? FileAttributeType == .typeDirectory else { throw StudioEspansoTwinError.invalidFolder }
                return true
            }
            return false
        }
        if found.count > 1 { throw StudioEspansoTwinError.operationFailed("Two Espanso configuration folders exist. Choose the one Espanso uses in the app.") }
        return found.first ?? candidates[0]
    }

    public static func preview(csv: URL, configRoot: URL) throws -> StudioEspansoPreview {
        try preview(csvs: [csv], configRoot: configRoot)
    }
    public static func preview(csvs: [URL], configRoot: URL) throws -> StudioEspansoPreview {
        let trial = try StudioSnippetSwitch.audit(files: csvs)
        return StudioEspansoPreview(trial: trial, configRoot: configRoot)
    }

    /// The caller must obtain explicit approval. Never overwrites any existing
    /// Espanso match file. A fresh, UUID-named file is created exclusively.
    public static func prepare(_ preview: StudioEspansoPreview, approved: Bool,
                               applicationSupport: URL, fileManager fm: FileManager = .default) throws -> StudioEspansoReceipt {
        guard approved else { throw StudioEspansoTwinError.notApproved }
        guard preview.ready > 0 else { throw StudioEspansoTwinError.noCompatibleMatches }
        guard try load(in: applicationSupport, fileManager: fm) == nil else { throw StudioEspansoTwinError.existingSetup }
        let root = preview.configRoot.standardizedFileURL
        guard root.isFileURL else { throw StudioEspansoTwinError.invalidFolder }
        // Ensure the entire path is made of real directories. The destination
        // is explicitly selected by the app/user; this refuses symlink redirects.
        try ensureSafeDirectory(root, create: true, fileManager: fm)
        let match = root.appendingPathComponent("match", isDirectory: true)
        try ensureSafeDirectory(match, create: true, fileManager: fm)
        let bytes = try StudioSnippetSwitch.export(preview.trial, as: .espanso)
        let name = "librereplace-\(UUID().uuidString.lowercased()).yml"
        let dest = match.appendingPathComponent(name)
        let temp = match.appendingPathComponent(".librereplace-\(UUID().uuidString).tmp")
        defer { try? fm.removeItem(at: temp) }
        try bytes.write(to: temp, options: .withoutOverwriting)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temp.path)
        do { try fm.linkItem(at: temp, to: dest) }
        catch { throw StudioEspansoTwinError.operationFailed("The new configuration could not be created without replacing existing files.") }
        do {
            guard try Data(contentsOf: dest) == bytes else { throw StudioEspansoTwinError.operationFailed("Generated text did not pass the read-back check.") }
            let receipt = StudioEspansoReceipt(id: UUID(), date: Date(), configRootPath: root.path,
                generatedFilename: name, fingerprint: fingerprint(bytes),
                installedCount: preview.ready, excludedCount: preview.total - preview.ready)
            try persist(receipt, in: applicationSupport, fileManager: fm)
            return receipt
        } catch {
            // The file was just created and we still own the exact bytes.
            if (try? Data(contentsOf: dest)) == bytes { try? fm.removeItem(at: dest) }
            throw error
        }
    }

    public static func verify(_ receipt: StudioEspansoReceipt, fileManager fm: FileManager = .default) throws -> Bool {
        let target = receipt.generatedFile
        guard target.lastPathComponent == receipt.generatedFilename,
              receipt.generatedFilename.hasPrefix("librereplace-"), receipt.generatedFilename.hasSuffix(".yml") else {
            throw StudioEspansoTwinError.corruptReceipt
        }
        try checkExistingDirectory(target.deletingLastPathComponent(), fileManager: fm)
        let attributes = try? fm.attributesOfItem(atPath: target.path)
        guard attributes?[.type] as? FileAttributeType == .typeRegular else { return false }
        let bytes = try Data(contentsOf: target)
        return fingerprint(bytes) == receipt.fingerprint
    }

    /// Undo removes ONLY the file created by LibreReplace. If the user or
    /// Espanso changed it after setup, recovery refuses to remove it.
    public static func undo(_ receipt: StudioEspansoReceipt, applicationSupport: URL,
                            fileManager fm: FileManager = .default) throws {
        // A caller must never be able to swap the receipt's destination path
        // while keeping an otherwise valid local setup identifier.
        guard let saved = try load(in: applicationSupport, fileManager: fm), saved == receipt else {
            throw StudioEspansoTwinError.corruptReceipt
        }
        guard try verify(receipt, fileManager: fm) else {
            if fm.fileExists(atPath: receipt.generatedFile.path) { throw StudioEspansoTwinError.modifiedFile }
            // If the user already removed our file in Finder, clear only the
            // stale receipt. Don't hold their free setup library hostage.
            try fm.removeItem(at: receiptURL(applicationSupport))
            return
        }
        try fm.removeItem(at: receipt.generatedFile)
        try fm.removeItem(at: receiptURL(applicationSupport))
    }

    public static func load(in applicationSupport: URL, fileManager fm: FileManager = .default) throws -> StudioEspansoReceipt? {
        let path = receiptURL(applicationSupport)
        try rejectSymlinks(path.deletingLastPathComponent(), fileManager: fm)
        guard fm.fileExists(atPath: path.path) else { return nil }
        guard (try? fm.attributesOfItem(atPath: path.path)[.type] as? FileAttributeType) == .typeRegular,
              let bytes = fm.contents(atPath: path.path), bytes.count <= 8192,
              let receipt = try? JSONDecoder().decode(StudioEspansoReceipt.self, from: bytes) else {
            throw StudioEspansoTwinError.corruptReceipt
        }
        return receipt
    }

    private static func persist(_ receipt: StudioEspansoReceipt, in applicationSupport: URL,
                                fileManager fm: FileManager) throws {
        let url = receiptURL(applicationSupport)
        try ensureSafeDirectory(url.deletingLastPathComponent(), create: true, fileManager: fm)
        guard !fm.fileExists(atPath: url.path) else { throw StudioEspansoTwinError.existingSetup }
        let encoded = try JSONEncoder().encode(receipt)
        try encoded.write(to: url, options: .withoutOverwriting)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        guard (try? fm.contents(atPath: url.path)) == encoded else {
            throw StudioEspansoTwinError.corruptReceipt
        }
    }

    private static func receiptURL(_ root: URL) -> URL {
        root.appendingPathComponent("LibreReplace/Free Twins/Espanso/state-v1.json")
    }

    private static func checkExistingDirectory(_ url: URL, fileManager fm: FileManager) throws {
        try rejectSymlinks(url, fileManager: fm)
        guard let type = (try? fm.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType,
              type == .typeDirectory else { throw StudioEspansoTwinError.invalidFolder }
    }

    private static func rejectSymlinks(_ url: URL, fileManager fm: FileManager) throws {
        var path = url.standardizedFileURL
        while path.path != "/" {
            if path.path != "/var" && path.path != "/tmp" && path.path != "/etc",
               let attributes = try? fm.attributesOfItem(atPath: path.path),
               attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                throw StudioEspansoTwinError.unsafePath
            }
            let parent = path.deletingLastPathComponent()
            if parent.path == path.path { break }
            path = parent
        }
    }

    private static func ensureSafeDirectory(_ url: URL, create: Bool, fileManager fm: FileManager) throws {
        try rejectSymlinks(url, fileManager: fm)
        if create { try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        try checkExistingDirectory(url, fileManager: fm)
    }

    private static func fingerprint(_ bytes: Data) -> String {
        #if canImport(CryptoKit)
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        #else
        // Portable test-only checksum. The distributed macOS build uses SHA-256.
        var hash: UInt64 = 14695981039346656037
        for byte in bytes { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return String(hash, radix: 16)
        #endif
    }
}
