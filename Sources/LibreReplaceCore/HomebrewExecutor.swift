import Foundation

public struct ProcessExecutionResult: Equatable, Sendable {
    public let terminationStatus: Int32
    public let output: String

    public init(terminationStatus: Int32, output: String) {
        self.terminationStatus = terminationStatus
        self.output = output
    }
}

/// Executes Homebrew without a shell. The executable path and argument array are
/// passed directly to Foundation.Process so package tokens are never interpolated
/// into shell source.
public struct HomebrewExecutor: Sendable {
    public let executableCandidates: [String]

    public init(executableCandidates: [String] = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]) {
        self.executableCandidates = executableCandidates
    }

    public func resolvedExecutable(fileManager: FileManager = .default) -> String? {
        executableCandidates.first { fileManager.isExecutableFile(atPath: $0) }
    }

    public func run(arguments: [String], fileManager: FileManager = .default) -> ProcessExecutionResult? {
        guard let executable = resolvedExecutable(fileManager: fileManager) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            // Drain while the child runs so verbose commands cannot fill the pipe
            // and deadlock before waitUntilExit().
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            return ProcessExecutionResult(terminationStatus: process.terminationStatus, output: output)
        } catch {
            return ProcessExecutionResult(terminationStatus: -1, output: error.localizedDescription)
        }
    }
}
