import Foundation

public enum InstallAction: Equatable, Sendable {
    case homebrew(executableCandidates: [String], arguments: [String], displayCommand: String)
    case openURL(URL)
}

public enum ExternalURLSafety {
    public static func httpsURL(_ value: String) -> URL? {
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              let url = components.url else { return nil }
        return url
    }

    public static func macAppStoreURL(_ value: String) -> URL? {
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "macappstore",
              components.user == nil, components.password == nil,
              let url = components.url else { return nil }
        return url
    }
}

public enum InstallActionBuilder {
    public static func action(for method: InstallMethod) -> InstallAction? {
        switch method.kind {
        case .homebrewCask:
            guard isSafePackageToken(method.value) else { return nil }
            return .homebrew(
                executableCandidates: ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"],
                arguments: ["install", "--cask", method.value],
                displayCommand: "brew install --cask \(method.value)"
            )
        case .homebrewFormula:
            guard isSafePackageToken(method.value) else { return nil }
            return .homebrew(
                executableCandidates: ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"],
                arguments: ["install", method.value],
                displayCommand: "brew install \(method.value)"
            )
        case .githubRelease, .officialDownload:
            guard let url = ExternalURLSafety.httpsURL(method.value) else { return nil }
            return .openURL(url)
        case .macAppStore:
            guard let url = ExternalURLSafety.macAppStoreURL(method.value) ?? ExternalURLSafety.httpsURL(method.value) else { return nil }
            return .openURL(url)
        }
    }

    public static func isSafePackageToken(_ token: String) -> Bool {
        !token.isEmpty && token.range(of: #"^[A-Za-z0-9@+._/-]+$"#, options: .regularExpression) != nil && !token.contains("..") && !token.hasPrefix("/")
    }
}
