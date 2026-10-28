import Foundation

public struct ScannerPolicy: Sendable {
    public let roots: [URL]

    public init(roots: [URL]) {
        self.roots = roots.map { $0.standardizedFileURL }
    }

    public static var macOSDefault: ScannerPolicy {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ScannerPolicy(roots: [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true)
        ])
    }
}

/// Synchronous scanner that owns a Foundation `FileManager`.
///
/// `AppScanner` is intentionally not `Sendable`: on Apple platforms `FileManager`
/// is not declared `Sendable`. Callers that want off-main scanning should create
/// and consume the scanner within the same task, as the SwiftUI app does, rather
/// than transferring a scanner instance across concurrency domains.
public struct AppScanner {
    private let fileManager: FileManager
    public let policy: ScannerPolicy

    public init(policy: ScannerPolicy = .macOSDefault, fileManager: FileManager = .default) {
        self.policy = policy
        self.fileManager = fileManager
    }

    public func scan() -> [InstalledApplication] {
        var found: [InstalledApplication] = []
        for root in policy.roots where fileManager.fileExists(atPath: root.path) {
            found.append(contentsOf: scan(root: root))
        }
        return deduplicate(found)
    }

    private func scan(root: URL) -> [InstalledApplication] {
        // Do not let a user-controlled symlink turn a configured application root
        // into a scan of an unrelated directory.
        guard (try? fileManager.destinationOfSymbolicLink(atPath: root.path)) == nil else { return [] }
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var apps: [InstalledApplication] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "app" else { continue }
            guard PathSafety.isWithin(url: url, allowedRoot: root) else { continue }
            if let app = readBundle(at: url) { apps.append(app) }
        }
        return apps
    }

    private func readBundle(at appURL: URL) -> InstalledApplication? {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard PathSafety.isWithin(url: plistURL, allowedRoot: appURL),
              let data = try? Data(contentsOf: plistURL),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let plist = object as? [String: Any] else {
            return nil
        }

        let name = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? appURL.deletingPathExtension().lastPathComponent
        let bundleID = plist["CFBundleIdentifier"] as? String
        let version = (plist["CFBundleShortVersionString"] as? String) ?? (plist["CFBundleVersion"] as? String)
        return InstalledApplication(name: name, bundleIdentifier: bundleID, version: version, path: appURL)
    }

    private func deduplicate(_ apps: [InstalledApplication]) -> [InstalledApplication] {
        var seen = Set<String>()
        var result: [InstalledApplication] = []
        for app in apps.sorted(by: { $0.path.path < $1.path.path }) {
            let key = (app.bundleIdentifier?.lowercased()).map { "bundle:\($0)" } ?? "path:\(app.path.standardizedFileURL.path.lowercased())"
            if seen.insert(key).inserted { result.append(app) }
        }
        return result
    }
}
