import Foundation

public enum MigrationError: Error, LocalizedError, Equatable {
    case unsafePath(String)
    case sourceMissing(String)
    case invalidSource(String)
    case invalidTarget(String)
    case stalePlan(String)
    case targetNotWritable(String)
    case backupFailed(String)
    case applyFailed(String)
    case verificationFailed(String)
    case rollbackFailed(String)
    case noBackup

    public var errorDescription: String? {
        switch self {
        case .unsafePath(let p): return "Unsafe migration path: \(p)"
        case .sourceMissing(let p): return "Migration source is missing: \(p)"
        case .invalidSource(let p): return "Migration source is not parseable: \(p)"
        case .invalidTarget(let p): return "Existing migration target is not parseable: \(p)"
        case .stalePlan(let p): return "Migration preview is stale or does not match the current target: \(p)"
        case .targetNotWritable(let p): return "Migration target is not writable: \(p)"
        case .backupFailed(let p): return "Could not create or verify backup for \(p)"
        case .applyFailed(let p): return "Could not apply migration to \(p)"
        case .verificationFailed(let p): return "Migration output could not be verified: \(p)"
        case .rollbackFailed(let p): return "Rollback could not restore the original target state: \(p)"
        case .noBackup: return "No rollback backup is available."
        }
    }
}

public struct MigrationChange: Codable, Hashable, Sendable {
    public let key: String
    public let fromValue: String?
    public let toValue: String

    public init(key: String, fromValue: String?, toValue: String) {
        self.key = key
        self.fromValue = fromValue
        self.toValue = toValue
    }
}

public struct MigrationPlan: Codable, Hashable, Sendable {
    public let adapterID: String
    public let sourcePath: URL
    public let targetPath: URL
    public let changes: [MigrationChange]
    public let warnings: [String]

    public init(adapterID: String, sourcePath: URL, targetPath: URL, changes: [MigrationChange], warnings: [String]) {
        self.adapterID = adapterID
        self.sourcePath = sourcePath
        self.targetPath = targetPath
        self.changes = changes
        self.warnings = warnings
    }
}

public struct MigrationReceipt: Codable, Hashable, Sendable {
    public let adapterID: String
    public let targetPath: URL
    public let backupPath: URL?
    public let targetExistedBeforeApply: Bool
    public let appliedAt: Date

    public init(
        adapterID: String,
        targetPath: URL,
        backupPath: URL?,
        targetExistedBeforeApply: Bool,
        appliedAt: Date = Date()
    ) {
        self.adapterID = adapterID
        self.targetPath = targetPath
        self.backupPath = backupPath
        self.targetExistedBeforeApply = targetExistedBeforeApply
        self.appliedAt = appliedAt
    }
}

public protocol MigrationAdapter: Sendable {
    var id: String { get }
    var displayName: String { get }
    func detect(home: URL, fileManager: FileManager) -> Bool
    func preview(home: URL, fileManager: FileManager) throws -> MigrationPlan
    func apply(plan: MigrationPlan, home: URL, backupRoot: URL, fileManager: FileManager) throws -> MigrationReceipt
    func rollback(receipt: MigrationReceipt, home: URL, fileManager: FileManager) throws
}

public enum MigrationBackup {
    public static func backup(target: URL, backupRoot: URL, fileManager: FileManager) throws -> URL? {
        guard fileManager.fileExists(atPath: target.path) else { return nil }
        do {
            try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let destination = backupRoot.appendingPathComponent("\(target.lastPathComponent).\(stamp).\(UUID().uuidString).bak")
            try fileManager.copyItem(at: target, to: destination)
            guard try Data(contentsOf: target) == Data(contentsOf: destination) else {
                try? fileManager.removeItem(at: destination)
                throw MigrationError.backupFailed(target.path)
            }
            return destination
        } catch let error as MigrationError {
            throw error
        } catch {
            throw MigrationError.backupFailed(target.path)
        }
    }

    public static func restore(receipt: MigrationReceipt, fileManager: FileManager) throws {
        if !receipt.targetExistedBeforeApply {
            do {
                if fileManager.fileExists(atPath: receipt.targetPath.path) {
                    try fileManager.removeItem(at: receipt.targetPath)
                }
                guard !fileManager.fileExists(atPath: receipt.targetPath.path) else {
                    throw MigrationError.rollbackFailed(receipt.targetPath.path)
                }
                return
            } catch let error as MigrationError {
                throw error
            } catch {
                throw MigrationError.rollbackFailed(receipt.targetPath.path)
            }
        }

        guard let backup = receipt.backupPath, fileManager.fileExists(atPath: backup.path) else {
            throw MigrationError.noBackup
        }
        do {
            let original = try Data(contentsOf: backup)
            try fileManager.createDirectory(at: receipt.targetPath.deletingLastPathComponent(), withIntermediateDirectories: true)
            try original.write(to: receipt.targetPath, options: .atomic)
            guard try Data(contentsOf: receipt.targetPath) == original else {
                throw MigrationError.rollbackFailed(receipt.targetPath.path)
            }
        } catch let error as MigrationError {
            throw error
        } catch {
            throw MigrationError.rollbackFailed(receipt.targetPath.path)
        }
    }
}
