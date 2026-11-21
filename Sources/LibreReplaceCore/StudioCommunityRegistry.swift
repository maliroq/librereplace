import Foundation

/// Curated registry metadata. The registry is data, never executable instructions.
public struct StudioCommunityBuild: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    public let paidApp: String
    public let freeApps: [String]
    public let category: String
    public let contributor: String
    public let recipePath: String
    public let recipeSHA256: String
    public let lastReviewed: String

    public init(id: String, title: String, summary: String, paidApp: String,
                freeApps: [String], category: String, contributor: String,
                recipePath: String, recipeSHA256: String, lastReviewed: String) {
        self.id = id
        self.title = title
        self.summary = summary
        self.paidApp = paidApp
        self.freeApps = freeApps
        self.category = category
        self.contributor = contributor
        self.recipePath = recipePath
        self.recipeSHA256 = recipeSHA256
        self.lastReviewed = lastReviewed
    }
}

public struct StudioCommunityIndex: Codable, Sendable {
    public let schemaVersion: Int
    public let builds: [StudioCommunityBuild]
    public init(schemaVersion: Int, builds: [StudioCommunityBuild]) {
        self.schemaVersion = schemaVersion
        self.builds = builds
    }
}

/// A curated index is only a discovery mechanism. The downloaded recipe still
/// must match its checksum and pass StudioSafeRecipeLoader before local import.
public enum StudioCommunityRegistry {
    public static let repository = "maliroq/librereplace"
    public static let maxIndexBytes = 128 * 1024
    public static let maxBuilds = 250
    public static let indexURL = URL(string: "https://raw.githubusercontent.com/maliroq/librereplace/main/Community/index.v1.json")!

    private static func validID(_ value: String) -> Bool {
        value.range(of: "^[a-z][a-z0-9-]{2,79}$", options: .regularExpression) != nil
    }

    public static func read(_ data: Data) throws -> [StudioCommunityBuild] {
        guard !data.isEmpty, data.count <= maxIndexBytes else {
            throw StudioRecipeValidationIssue("Community index is too large or empty")
        }
        let index: StudioCommunityIndex
        do { index = try JSONDecoder().decode(StudioCommunityIndex.self, from: data) }
        catch { throw StudioRecipeValidationIssue("Community index has an unsupported format") }
        guard index.schemaVersion == 1, index.builds.count <= maxBuilds else {
            throw StudioRecipeValidationIssue("Community index version or item count is unsupported")
        }
        var ids = Set<String>()
        for build in index.builds {
            guard validID(build.id), ids.insert(build.id).inserted else {
                throw StudioRecipeValidationIssue("Community build has an invalid or duplicate identifier")
            }
            guard (3...90).contains(build.title.count), (12...320).contains(build.summary.count),
                  (2...80).contains(build.paidApp.count), (2...64).contains(build.contributor.count),
                  (3...40).contains(build.category.count),
                  (1...8).contains(build.freeApps.count),
                  build.freeApps.allSatisfy({ (2...80).contains($0.count) }),
                  build.lastReviewed.range(of: "^20[0-9]{2}-[01][0-9]-[0-3][0-9]$", options: .regularExpression) != nil else {
                throw StudioRecipeValidationIssue("Community build metadata is incomplete")
            }
            guard build.recipePath == "Community/recipes/\(build.id).json",
                  build.recipeSHA256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
                throw StudioRecipeValidationIssue("Community recipe path or checksum is invalid")
            }
        }
        return index.builds
    }

    public static func recipeURL(for build: StudioCommunityBuild) -> URL {
        URL(string: "https://raw.githubusercontent.com/\(repository)/main/\(build.recipePath)")!
    }
}
