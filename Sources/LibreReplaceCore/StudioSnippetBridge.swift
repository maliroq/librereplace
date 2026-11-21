import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Conservative, local conversion of Sublime user snippets into Zed's native
/// snippet files. This is deliberately not a general XML/extension executor.
/// Known scopes and placeholder syntax only; anything else is reported.
public enum StudioSnippetBridgeError: Error, LocalizedError {
    case unsafePath(String), changedSincePreview(String), malformedTarget(String)
    case recoveryConflict(String), failed(String)

    public var errorDescription: String? {
        switch self {
        case .unsafePath(let p): "Unsafe snippet path: \(p)"
        case .changedSincePreview(let p): "The destination changed since preview: \(p). Nothing was overwritten."
        case .malformedTarget(let p): "Zed snippet file cannot be safely merged: \(p)"
        case .recoveryConflict(let p): "Zed snippets changed since LibreReplace wrote them: \(p). Recovery was stopped to preserve your edits."
        case .failed(let message): message
        }
    }
}

public struct StudioSnippetIssue: Sendable, Equatable {
    public let filename: String
    public let explanation: String
    public init(_ filename: String, _ explanation: String) {
        self.filename = filename
        self.explanation = explanation
    }
}

public struct StudioSnippetFilePlan: Sendable {
    public let target: URL
    public let originalData: Data?
    public let resultData: Data
    public let expectedNames: [String]
}

public struct StudioSnippetPreview: Sendable {
    public let scanned: Int
    public let ready: Int
    public let issues: [StudioSnippetIssue]
    public let files: [StudioSnippetFilePlan]
    public var needsChanges: Bool { !files.isEmpty }
}

public struct StudioSnippetChangedFile: Codable, Sendable {
    public let target: URL
    public let backup: URL?
    public let existedBefore: Bool
    public let writtenFingerprint: String
}

public struct StudioSnippetReceipt: Codable, Sendable {
    public let id: UUID
    public let completedAt: Date
    public let changes: [StudioSnippetChangedFile]
}

public enum StudioDataFingerprint {
    public static func of(_ bytes: Data) -> String {
        #if canImport(CryptoKit)
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        #else
        // Portable Linux test implementation only. The shipped macOS app
        // uses CryptoKit SHA-256; do not use this branch for security decisions.
        var hash: UInt64 = 14695981039346656037
        for byte in bytes { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return String(hash, radix: 16)
        #endif
    }
}

private final class SublimeSnippetXMLDelegate: NSObject, XMLParserDelegate {
    var values: [String: String] = [:]
    var activeField: String?
    var hasRoot = false
    var hasInvalidRoot = false
    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if !hasRoot {
            hasRoot = true
            if elementName != "snippet" { hasInvalidRoot = true }
        }
        if ["content", "tabTrigger", "scope", "description"].contains(elementName) {
            activeField = elementName
            if values[elementName] == nil { values[elementName] = "" }
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if let field = activeField { values[field, default: ""] += string }
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let field = activeField, let string = String(data: CDATABlock, encoding: .utf8) {
            values[field, default: ""] += string
        }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if activeField == elementName { activeField = nil }
    }
}

public struct StudioSnippetBridge {
    public init() {}

    /// No artificial snippet-count or snippet-size cutoff. Enumerates
    /// user-created snippets (including subfolders); skips symlinks.
    public func preview(home: URL, fileManager fm: FileManager = .default) throws -> StudioSnippetPreview {
        let sourceRoots = try findSourceRoots(home: home, fm: fm)
        guard !sourceRoots.isEmpty else { return .init(scanned: 0, ready: 0, issues: [], files: []) }
        let targetRoot = home.appendingPathComponent(".config/zed/snippets", isDirectory: true)
        try PathSafety.requireWithin(targetRoot, allowedRoots: [home])
        try PathSafety.requireNoSymlinkTraversal(targetRoot, allowedRoot: home, fileManager: fm)

        var scanned = 0
        var issues: [StudioSnippetIssue] = []
        var grouped: [String: [(String, [String: Any])]] = [:]
        for sourceRoot in sourceRoots {
        guard let enumerator = fm.enumerator(at: sourceRoot, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else {
            throw StudioSnippetBridgeError.failed("Cannot read Sublime's user snippets folder.")
        }
        // Stable ordering across APFS, HFS and Linux. This also makes a
        // second preview byte-for-byte comparable with the first.
        let urls = enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "sublime-snippet" }
            .sorted { $0.path < $1.path }
        for url in urls {
            scanned += 1
            // Use URL path components rather than character-count subtraction.
            // Foundation on macOS and swift-corelibs-foundation do not always
            // format directory URL paths identically (notably trailing `/`).
            // File identity must not silently lose a character or a folder.
            let rootParts = sourceRoot.standardizedFileURL.pathComponents
            let fileParts = url.standardizedFileURL.pathComponents
            guard fileParts.count > rootParts.count,
                  fileParts.starts(with: rootParts) else {
                issues.append(.init(url.lastPathComponent, "Snippet is outside its source folder."))
                continue
            }
            let relative = fileParts.dropFirst(rootParts.count).joined(separator: "/")
            let edition = sourceRoot.path.contains("Sublime Text 3/") ? "Sublime Text 3" : "Sublime Text"
            let shortName = sourceRoots.count > 1 ? edition + "/" + relative : relative
            guard PathSafety.isWithin(url: url, allowedRoot: sourceRoot),
                  (try? PathSafety.requireNoSymlinkTraversal(url, allowedRoot: home, fileManager: fm)) != nil,
                  (try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey]))?.isSymbolicLink != true,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else {
                issues.append(.init(shortName, "Symbolic links and unsafe paths are not imported.")); continue
            }
            guard let source = fm.contents(atPath: url.path),
                  let xmlString = String(data: source, encoding: .utf8),
                  !xmlString.localizedCaseInsensitiveContains("<!DOCTYPE"),
                  !xmlString.localizedCaseInsensitiveContains("<!ENTITY") else {
                issues.append(.init(shortName, "Unreadable or unsafe XML.")); continue
            }
            let delegate = SublimeSnippetXMLDelegate()
            let parser = XMLParser(data: source)
            parser.delegate = delegate
            parser.shouldResolveExternalEntities = false
            guard parser.parse(), delegate.hasRoot, !delegate.hasInvalidRoot,
                  let body = delegate.values["content"], !body.isEmpty,
                  let prefix = delegate.values["tabTrigger"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !prefix.isEmpty else {
                issues.append(.init(shortName, "Invalid XML, missing content, or missing tab trigger.")); continue
            }
            let rawScope = (delegate.values["scope"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let filename = Self.zedFilename(for: rawScope) else {
                issues.append(.init(shortName, "This Sublime scope has no verified Zed equivalent: \(rawScope).")); continue
            }
            guard Self.hasCompatiblePlaceholders(body) else {
                issues.append(.init(shortName, "Unsupported snippet variable or placeholder transformation.")); continue
            }
            let title = (delegate.values["description"] ?? url.deletingPathExtension().lastPathComponent)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let uniqueName = "LibreReplace: \(shortName)"
            let item: [String: Any] = [
                "prefix": prefix,
                "body": body.replacingOccurrences(of: "\\$", with: "\\\\$", options: .literal).components(separatedBy: "\n"),
                "description": title.isEmpty ? shortName : title
            ]
            grouped[filename, default: []].append((uniqueName, item))
        }
        }
        var ready = 0
        var files: [StudioSnippetFilePlan] = []
        for filename in grouped.keys.sorted() {
            let target = targetRoot.appendingPathComponent(filename)
            try PathSafety.requireNoSymlinkTraversal(target, allowedRoot: home, fileManager: fm)
            let original: Data? = fm.fileExists(atPath: target.path) ? fm.contents(atPath: target.path) : nil
            if fm.fileExists(atPath: target.path), original == nil {
                issues.append(.init(filename, "Cannot read the current Zed snippet file.")); continue
            }
            var existing: [String: Any] = [:]
            if let original {
                guard let parsed = try? JSONSerialization.jsonObject(with: JSONC.stripComments(original)) as? [String: Any] else {
                    issues.append(.init(filename, "Existing Zed JSON cannot be safely merged.")); continue
                }
                existing = parsed
            }
            var additions: [String: Any] = [:]
            var newNames: [String] = []
            let currentPrefixes = Set(existing.values.compactMap { ($0 as? [String: Any])?["prefix"] as? String })
            var addedPrefixes = Set<String>()
            for (name, item) in grouped[filename] ?? [] {
                let prefix = item["prefix"] as? String ?? ""
                if existing[name] != nil {
                    issues.append(.init(name, "A snippet with this name already exists; not overwritten.")); continue
                }
                if currentPrefixes.contains(prefix) || !addedPrefixes.insert(prefix).inserted {
                    issues.append(.init(name, "Trigger conflicts with an existing or imported Zed snippet.")); continue
                }
                additions[name] = item
                newNames.append(name)
            }
            guard !additions.isEmpty else { continue }
            guard let merged = try? Self.appendEntries(additions, original: original) else {
                issues.append(.init(filename, "Could not create a safe, comment-preserving merge.")); continue
            }
            files.append(.init(target: target, originalData: original, resultData: merged, expectedNames: newNames.sorted()))
            ready += additions.count
        }
        return .init(scanned: scanned, ready: ready, issues: issues, files: files)
    }

    /// All backups are created and verified before writing any target.
    /// Rollback refuses to overwrite changes made later in Zed.
    public func apply(_ plan: StudioSnippetPreview, home: URL, backupRoot: URL, fileManager fm: FileManager = .default) throws -> StudioSnippetReceipt {
        guard !plan.files.isEmpty else { throw StudioSnippetBridgeError.failed("No new compatible snippets to install.") }
        try PathSafety.requireWithin(backupRoot, allowedRoots: [home])
        try PathSafety.requireNoSymlinkTraversal(backupRoot, allowedRoot: home, fileManager: fm)
        let current = try preview(home: home, fileManager: fm)
        let expected = Dictionary(uniqueKeysWithValues: plan.files.map { ($0.target.path, $0.resultData) })
        let actual = Dictionary(uniqueKeysWithValues: current.files.map { ($0.target.path, $0.resultData) })
        guard expected == actual else { throw StudioSnippetBridgeError.changedSincePreview("Sublime snippets or Zed snippets") }
        try fm.createDirectory(at: backupRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var changes: [StudioSnippetChangedFile] = []
        for file in plan.files {
            try PathSafety.requireWithin(file.target, allowedRoots: [home])
            try PathSafety.requireNoSymlinkTraversal(file.target, allowedRoot: home, fileManager: fm)
            let existing = fm.contents(atPath: file.target.path)
            guard existing == file.originalData else { throw StudioSnippetBridgeError.changedSincePreview(file.target.path) }
            let backup = try MigrationBackup.backup(target: file.target, backupRoot: backupRoot, fileManager: fm)
            changes.append(.init(target: file.target, backup: backup, existedBefore: file.originalData != nil,
                                 writtenFingerprint: StudioDataFingerprint.of(file.resultData)))
        }
        let receipt = StudioSnippetReceipt(id: UUID(), completedAt: Date(), changes: changes)
        let journalURL = backupRoot.appendingPathComponent("Zed-" + receipt.id.uuidString + ".receipt.json")
        let journalData = try JSONEncoder().encode(receipt)
        try journalData.write(to: journalURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journalURL.path)
        guard fm.contents(atPath: journalURL.path) == journalData else {
            throw StudioSnippetBridgeError.failed("Could not preserve recovery information. No Zed snippet files changed.")
        }
        var written: [StudioSnippetChangedFile] = []
        do {
            for (index, file) in plan.files.enumerated() {
                try fm.createDirectory(at: file.target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try PathSafety.requireNoSymlinkTraversal(file.target, allowedRoot: home, fileManager: fm)
                guard fm.contents(atPath: file.target.path) == file.originalData else {
                    throw StudioSnippetBridgeError.changedSincePreview(file.target.path)
                }
                try file.resultData.write(to: file.target, options: .atomic)
                written.append(changes[index])
                guard let check = fm.contents(atPath: file.target.path),
                      StudioDataFingerprint.of(check) == changes[index].writtenFingerprint,
                      let parsed = try? JSONSerialization.jsonObject(with: JSONC.stripComments(check)) as? [String: Any],
                      file.expectedNames.allSatisfy({ parsed[$0] != nil }) else {
                    throw StudioSnippetBridgeError.failed("Could not verify the Zed snippets written to \(file.target.lastPathComponent).")
                }
            }
            return receipt
        } catch {
            // On a failed write, restore only files we actually changed. A
            // failure to restore is always surfaced, not swallowed.
            for item in written.reversed() {
                guard let currentData = fm.contents(atPath: item.target.path),
                      StudioDataFingerprint.of(currentData) == item.writtenFingerprint else {
                    throw StudioSnippetBridgeError.recoveryConflict(item.target.path)
                }
                try restore(item, fm: fm)
            }
            // A preserved receipt remains on disk if recovery was interrupted.
            throw error
        }
    }

    public func verify(_ receipt: StudioSnippetReceipt, home: URL, fileManager fm: FileManager = .default) -> Bool {
        receipt.changes.allSatisfy { item in
            (try? PathSafety.requireNoSymlinkTraversal(item.target, allowedRoot: home, fileManager: fm)) != nil &&
            (fm.contents(atPath: item.target.path)).map { StudioDataFingerprint.of($0) == item.writtenFingerprint } == true
        }
    }

    public func canSafelyRollback(_ receipt: StudioSnippetReceipt, home: URL,
                                  fileManager fm: FileManager = .default) -> Bool {
        (try? checkRecoveryStates(receipt, home: home, fm: fm)) != nil
    }

    public func rollback(_ receipt: StudioSnippetReceipt, home: URL, fileManager fm: FileManager = .default) throws {
        // Every target must be either our exact output or the exact original.
        // This makes interrupted/partial recovery safe to retry, but never
        // overwrites changes created by the user afterward.
        let pending = try checkRecoveryStates(receipt, home: home, fm: fm)
        for item in pending.reversed() {
            guard let data = fm.contents(atPath: item.target.path),
                  StudioDataFingerprint.of(data) == item.writtenFingerprint else {
                throw StudioSnippetBridgeError.recoveryConflict(item.target.path)
            }
            try restore(item, fm: fm)
        }
    }

    private func checkRecoveryStates(_ receipt: StudioSnippetReceipt, home: URL,
                                     fm: FileManager) throws -> [StudioSnippetChangedFile] {
        var pending: [StudioSnippetChangedFile] = []
        for item in receipt.changes {
            try PathSafety.requireWithin(item.target, allowedRoots: [home])
            try PathSafety.requireNoSymlinkTraversal(item.target, allowedRoot: home, fileManager: fm)
            if let backup = item.backup {
                try PathSafety.requireWithin(backup, allowedRoots: [home])
                try PathSafety.requireNoSymlinkTraversal(backup, allowedRoot: home, fileManager: fm)
            }
            let current = fm.contents(atPath: item.target.path)
            if current.map({ StudioDataFingerprint.of($0) == item.writtenFingerprint }) == true {
                // Backup must still be usable before any recovery begins.
                if item.existedBefore && (item.backup == nil || !fm.fileExists(atPath: item.backup!.path)) {
                    throw StudioSnippetBridgeError.failed("Required recovery backup is missing: \(item.target.path)")
                }
                pending.append(item)
            } else if item.existedBefore, let backup = item.backup,
                      let original = fm.contents(atPath: backup.path), original == current {
                continue // This file was already safely restored.
            } else if !item.existedBefore && current == nil && !fm.fileExists(atPath: item.target.path) {
                continue // Previously created file was already removed.
            } else {
                throw StudioSnippetBridgeError.recoveryConflict(item.target.path)
            }
        }
        return pending
    }

    private func restore(_ item: StudioSnippetChangedFile, fm: FileManager) throws {
        if item.existedBefore, let backup = item.backup {
            try Data(contentsOf: backup).write(to: item.target, options: .atomic)
        } else if fm.fileExists(atPath: item.target.path) {
            try fm.removeItem(at: item.target)
        }
    }

    private func findSourceRoots(home: URL, fm: FileManager) throws -> [URL] {
        var result: [URL] = []
        for directory in ["Sublime Text", "Sublime Text 3"] {
            let candidate = home.appendingPathComponent("Library/Application Support/\(directory)/Packages/User", isDirectory: true)
            try PathSafety.requireNoSymlinkTraversal(candidate, allowedRoot: home, fileManager: fm)
            if fm.fileExists(atPath: candidate.path) { result.append(candidate) }
        }
        return result
    }

    private static func zedFilename(for scope: String) -> String? {
        if scope.isEmpty { return "snippets.json" }
        let mapping = [
            "source.python": "python", "source.js": "javascript", "source.jsx": "javascript",
            "source.ts": "typescript", "source.tsx": "tsx", "source.swift": "swift",
            "source.rust": "rust", "source.go": "go", "source.java": "java",
            "source.c": "c", "source.css": "css",
            "text.html.basic": "html", "text.html.markdown": "markdown",
            "source.json": "json", "source.yaml": "yaml", "source.php": "php",
            "source.shell": "shell script", "text.plain": "plaintext"
        ]
        return mapping[scope].map { $0 + ".json" }
    }

    private static func hasCompatiblePlaceholders(_ body: String) -> Bool {
        // Numeric tab stops and placeholders use the common TextMate grammar.
        // Transformations, named variables and custom Sublime fields are not
        // assumed equivalent in Zed's implementation.
        let token = #"(?<!\\)\$([A-Za-z_][A-Za-z_0-9]*|\{[^}]+\})"#
        guard let re = try? NSRegularExpression(pattern: token) else { return false }
        let ns = body as NSString
        for match in re.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
            let value = ns.substring(with: match.range)
            if value.hasPrefix("${") {
                let inner = String(value.dropFirst(2).dropLast())
                if inner.range(of: #"^[0-9]+(:[^{}]*)?$"#, options: .regularExpression) == nil { return false }
            } else { return false }
        }
        return true
    }

    private static func appendEntries(_ entries: [String: Any], original: Data?) throws -> Data {
        // Preserve every existing byte (including JSONC comments) by
        // inserting new entries just before the final top-level `}`.
        let payload = try JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted, .sortedKeys])
        guard let payloadString = String(data: payload, encoding: .utf8) else { throw StudioSnippetBridgeError.failed("Cannot encode snippets.") }
        let inside = String(payloadString.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inside.isEmpty else { throw StudioSnippetBridgeError.failed("No snippets to append.") }
        guard let original else { return Data(("{\n" + inside + "\n}\n").utf8) }
        guard let text = String(data: original, encoding: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: JSONC.stripComments(original)) as? [String: Any],
              let closing = text.lastIndex(of: "}") else { throw StudioSnippetBridgeError.malformedTarget("Zed JSON") }
        // The final brace must be the root close, followed only by whitespace.
        guard text[text.index(after: closing)...].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StudioSnippetBridgeError.malformedTarget("Zed JSON trailing content")
        }
        let prefix = text[..<closing]
        // For a valid JSON object ending with `}`, the top-level parsed
        // dictionary is the authoritative indication of whether a comma is needed.
        let cleanPrefix = String(decoding: JSONC.stripComments(Data(prefix.utf8)), as: UTF8.self)
        let alreadyHasComma = cleanPrefix.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(",")
        let separator = (parsed.isEmpty || alreadyHasComma) ? "\n" : ",\n"
        let result = String(prefix) + separator + inside + "\n" + String(text[closing...])
        guard (try? JSONSerialization.jsonObject(with: JSONC.stripComments(Data(result.utf8))) as? [String: Any]) != nil else {
            throw StudioSnippetBridgeError.malformedTarget("Zed JSON cannot be safely extended")
        }
        return Data(result.utf8)
    }
}
