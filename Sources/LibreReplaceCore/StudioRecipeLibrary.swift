import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Locally imported recipes are reviewed data, not executable plugins.
public struct StudioSavedRecipe: Sendable, Identifiable {
    public let recipe: StudioReplacementRecipe
    public let url: URL
    public var id: String { recipe.id }
}

public struct StudioRecipeLibrarySnapshot: Sendable {
    public let recipes: [StudioSavedRecipe]
    public let skipped: [String]
}

/// A dedicated, persistent library for validated community recipe data.
/// No imported action can be executed merely by adding a recipe to the library.
public enum StudioRecipeLibrary {
    public static let maximumRecipes = 300

    public static func directory(in applicationSupport: URL) -> URL {
        applicationSupport.appendingPathComponent("LibreReplace", isDirectory: true)
            .appendingPathComponent("Community Recipes", isDirectory: true)
    }

    @discardableResult
    public static func store(_ data: Data, catalog: [StudioComponent], in applicationSupport: URL) throws -> StudioSavedRecipe {
        let recipe = try StudioSafeRecipeLoader.decodeAndValidate(data, catalog: catalog)
        let folder = try prepare(in: applicationSupport)
        let existing = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        guard existing.count < maximumRecipes else {
            throw StudioRecipeValidationIssue("The recipe library has reached its current limit of 300 entries")
        }
        // The recipe ID is constrained to safe ASCII by the schema validator.
        let target = folder.appendingPathComponent(recipe.id + ".json", isDirectory: false)
        guard !FileManager.default.fileExists(atPath: target.path),
              (try? FileManager.default.destinationOfSymbolicLink(atPath: target.path)) == nil else {
            throw StudioRecipeValidationIssue("A recipe with this ID already exists. Your saved recipe was left unchanged.")
        }
        // Exclusive creation prevents replacement of an existing file.
        let flags = O_WRONLY | O_CREAT | O_EXCL
        let fd = target.path.withCString { open($0, flags, mode_t(0o600)) }
        guard fd >= 0 else { throw StudioRecipeValidationIssue("Could not create the recipe file safely") }
        let success = data.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            var offset = 0
            while offset < buffer.count {
                let written = write(fd, base.advanced(by: offset), buffer.count - offset)
                if written <= 0 { return false }
                offset += written
            }
            return true
        }
        let closed = close(fd)
        if !success || closed != 0 {
            try? FileManager.default.removeItem(at: target)
            throw StudioRecipeValidationIssue("Could not finish saving the recipe")
        }
        guard try Data(contentsOf: target) == data else {
            try? FileManager.default.removeItem(at: target)
            throw StudioRecipeValidationIssue("Saved recipe could not be verified")
        }
        return StudioSavedRecipe(recipe: recipe, url: target)
    }

    /// Removes one known local recipe file, never an app or a workflow result.
    public static func remove(id: String, in applicationSupport: URL) throws {
        guard id.range(of: "^[a-z][a-z0-9._-]{1,79}$", options: .regularExpression) != nil else {
            throw StudioRecipeValidationIssue("Invalid recipe identifier")
        }
        let folder = try prepare(in: applicationSupport)
        let target = folder.appendingPathComponent(id + ".json", isDirectory: false)
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: target.path),
              attrs[.type] as? FileAttributeType == .typeRegular else {
            throw StudioRecipeValidationIssue("The recipe file is missing or unsafe")
        }
        try fm.removeItem(at: target)
    }

    public static func load(catalog: [StudioComponent], in applicationSupport: URL) throws -> StudioRecipeLibrarySnapshot {
        let folder = try prepare(in: applicationSupport)
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey
        ], options: [.skipsHiddenFiles])
        var accepted: [StudioSavedRecipe] = []
        var skipped: [String] = []
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).prefix(maximumRecipes + 1) where url.pathExtension.lowercased() == "json" {
            do {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true,
                      let size = values.fileSize, size > 0 && size <= 256 * 1024 else {
                    throw StudioRecipeValidationIssue("Invalid file type or size")
                }
                let data = try Data(contentsOf: url)
                let recipe = try StudioSafeRecipeLoader.decodeAndValidate(data, catalog: catalog)
                guard url.lastPathComponent == recipe.id + ".json" else {
                    throw StudioRecipeValidationIssue("Recipe ID differs from filename")
                }
                accepted.append(StudioSavedRecipe(recipe: recipe, url: url))
            } catch {
                skipped.append(url.lastPathComponent)
            }
        }
        return StudioRecipeLibrarySnapshot(recipes: accepted, skipped: skipped)
    }

    private static func prepare(in applicationSupport: URL) throws -> URL {
        let first = applicationSupport.appendingPathComponent("LibreReplace", isDirectory: true)
        let folder = directory(in: applicationSupport)
        let fm = FileManager.default
        for url in [first, folder] {
            if let attrs = try? fm.attributesOfItem(atPath: url.path) {
                guard attrs[.type] as? FileAttributeType == .typeDirectory else {
                    throw StudioRecipeValidationIssue("Recipe storage path must be a regular directory")
                }
            }
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        return folder
    }
}
