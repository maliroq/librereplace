import Foundation

public enum PathSafety {
    public static func isWithin(url: URL, allowedRoot: URL) -> Bool {
        let candidate = url.standardizedFileURL.resolvingSymlinksInPath().path
        let root = allowedRoot.standardizedFileURL.resolvingSymlinksInPath().path
        if candidate == root { return true }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return candidate.hasPrefix(prefix)
    }

    public static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0") else { return false }
        let pieces = path.split(separator: "/", omittingEmptySubsequences: false)
        return !pieces.contains("..")
    }

    public static func requireWithin(_ url: URL, allowedRoots: [URL]) throws {
        guard allowedRoots.contains(where: { isWithin(url: url, allowedRoot: $0) }) else {
            throw MigrationError.unsafePath(url.path)
        }
    }

    /// Rejects symbolic-link components below an allowed root. Migration paths are
    /// intentionally stricter than scanner paths so a settings write cannot be
    /// redirected to a different file through a symlink.
    public static func requireNoSymlinkTraversal(_ url: URL, allowedRoot: URL, fileManager: FileManager = .default) throws {
        let root = allowedRoot.standardizedFileURL
        let candidate = url.standardizedFileURL
        let rootPath = root.path
        let candidatePath = candidate.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"

        guard candidatePath == rootPath || candidatePath.hasPrefix(prefix) else {
            throw MigrationError.unsafePath(candidatePath)
        }
        guard candidatePath != rootPath else { return }

        let relative = String(candidatePath.dropFirst(prefix.count))
        var current = root
        for component in relative.split(separator: "/") {
            current.appendPathComponent(String(component))
            if (try? fileManager.destinationOfSymbolicLink(atPath: current.path)) != nil {
                throw MigrationError.unsafePath(current.path)
            }
            if !fileManager.fileExists(atPath: current.path) {
                // Descendants cannot exist when their parent is absent.
                break
            }
        }
    }
}
