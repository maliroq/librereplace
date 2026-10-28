import Foundation
import LibreReplaceCore

func usage() {
    print("""
    Usage:
      libreplace validate <catalog.json>
      libreplace report <catalog.json> <fixture-apps.json>
      libreplace scan-smoke <catalog.json>
      libreplace install-smoke <catalog.json>
      libreplace migration-selftest
    """)
}

func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func emitJSON(_ object: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}

func runScanSmoke(catalogURL: URL) throws -> Bool {
    let catalog = try CatalogLoader.load(from: catalogURL)
    let policy = ScannerPolicy.macOSDefault
    let installed = AppScanner(policy: policy).scan()
    let matcher = AppMatcher()
    let matches = matcher.match(installed: installed, catalog: catalog)
    let unsupported = matcher.unsupported(installed: installed, catalog: catalog)
    let withBundleID = installed.filter { $0.bundleIdentifier != nil }.count
    let normalizedIDs = installed.compactMap { $0.bundleIdentifier?.lowercased() }
    let uniqueIDs = Set(normalizedIDs)
    let duplicateBundleIDsAfterScan = normalizedIDs.count - uniqueIDs.count
    let existingRoots = policy.roots.filter { FileManager.default.fileExists(atPath: $0.path) }

    // Do not print installed app names, bundle IDs, versions, or user-specific paths.
    // This smoke test reports aggregate metadata only.
    let pass = !existingRoots.isEmpty && !installed.isEmpty && withBundleID > 0 && duplicateBundleIDsAfterScan == 0
    try emitJSON([
        "pass": pass,
        "rootsConfigured": policy.roots.count,
        "rootsFound": existingRoots.count,
        "applicationsEnumerated": installed.count,
        "applicationsWithBundleIdentifier": withBundleID,
        "supportedCatalogMatches": matches.count,
        "unsupportedApplicationsHandled": unsupported.count,
        "duplicateBundleIdentifiersAfterDeduplication": duplicateBundleIDsAfterScan,
        "metadataRead": ["Contents/Info.plist"],
        "privateApplicationDataRead": false,
        "applicationContentsTraversed": false
    ])
    return pass
}

func runInstallSmoke(catalogURL: URL) throws -> Bool {
    let catalog = try CatalogLoader.load(from: catalogURL)
    var methodsChecked = 0
    var homebrewActions = 0
    var URLActions = 0
    var invalidActions = 0
    var brewCandidates: [String] = []

    for app in catalog.apps {
        for alternative in app.alternatives {
            methodsChecked += 1
            guard let action = InstallActionBuilder.action(for: alternative.install) else {
                invalidActions += 1
                continue
            }
            switch action {
            case .homebrew(let candidates, let arguments, _):
                homebrewActions += 1
                brewCandidates.append(contentsOf: candidates)
                // An install action is inspected, never executed by this smoke test.
                guard !arguments.isEmpty else { invalidActions += 1; continue }
            case .openURL:
                URLActions += 1
            }
        }
    }

    let uniqueCandidates = Array(Set(brewCandidates)).sorted()
    let executor = HomebrewExecutor(executableCandidates: uniqueCandidates.isEmpty ? ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] : uniqueCandidates)
    let brewPath = executor.resolvedExecutable()
    var probeStatus: String = "NOT VERIFIED"
    var probeExitCode: Int? = nil
    if brewPath != nil {
        let result = executor.run(arguments: ["--version"])
        probeExitCode = result.map { Int($0.terminationStatus) }
        probeStatus = result?.terminationStatus == 0 ? "PASS" : "FAIL"
    }

    let commandGenerationPass = methodsChecked > 0 && invalidActions == 0
    let overall = commandGenerationPass && (brewPath == nil || probeStatus == "PASS")
    try emitJSON([
        "pass": overall,
        "commandGenerationPass": commandGenerationPass,
        "installMethodsChecked": methodsChecked,
        "homebrewActionsChecked": homebrewActions,
        "urlActionsChecked": URLActions,
        "invalidActions": invalidActions,
        "homebrewAvailable": brewPath != nil,
        "homebrewProbe": probeStatus,
        "homebrewProbeExitCode": probeExitCode as Any,
        "executedInstallCommand": false,
        "probeCommand": brewPath == nil ? "not run" : "brew --version",
        "usesShell": false
    ])
    return overall
}

func runMigrationSelftest() throws -> Bool {
    let fm = FileManager.default
    let fixtureRoot = fm.temporaryDirectory.appendingPathComponent("LibreReplaceMigrationSelftest-\(UUID().uuidString)", isDirectory: true)
    defer { try? fm.removeItem(at: fixtureRoot) }
    try fm.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)

    let source = fixtureRoot.appendingPathComponent("Library/Application Support/Sublime Text/Packages/User/Preferences.sublime-settings")
    let target = fixtureRoot.appendingPathComponent(".config/zed/settings.json")
    let backupRoot = fixtureRoot.appendingPathComponent(".libreplace-backups")
    try fm.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

    let sourceFixture = #"{"font_size": 15, "font_face": "SF Mono", "tab_size": 2, "translate_tabs_to_spaces": true}"#
    let targetFixture = #"{"buffer_font_size": 13, "unrelated": "preserve-me"}"#
    try sourceFixture.write(to: source, atomically: true, encoding: .utf8)
    try targetFixture.write(to: target, atomically: true, encoding: .utf8)
    let originalTarget = try Data(contentsOf: target)

    let adapter = SublimeToZedMigration()
    let detected = adapter.detect(home: fixtureRoot, fileManager: fm)
    let plan = try adapter.preview(home: fixtureRoot, fileManager: fm)
    let previewPass = detected && plan.changes.count == 4 && plan.targetPath.standardizedFileURL == target.standardizedFileURL

    let receipt = try adapter.apply(plan: plan, home: fixtureRoot, backupRoot: backupRoot, fileManager: fm)
    let backupPass = receipt.backupPath.map { fm.fileExists(atPath: $0.path) } ?? false
    let appliedData = try Data(contentsOf: target)
    let appliedObject = try JSONSerialization.jsonObject(with: appliedData) as? [String: Any]
    let applyPass = appliedData != originalTarget
    let verificationPass =
        (appliedObject?["buffer_font_size"] as? NSNumber)?.intValue == 15 &&
        appliedObject?["buffer_font_family"] as? String == "SF Mono" &&
        (appliedObject?["tab_size"] as? NSNumber)?.intValue == 2 &&
        (appliedObject?["hard_tabs"] as? Bool) == false &&
        appliedObject?["unrelated"] as? String == "preserve-me"

    try adapter.rollback(receipt: receipt, home: fixtureRoot, fileManager: fm)
    let rollbackPass = try Data(contentsOf: target) == originalTarget
    let overall = previewPass && backupPass && applyPass && verificationPass && rollbackPass

    try emitJSON([
        "pass": overall,
        "usedTemporaryFixtureOnly": true,
        "touchedRealSublimeConfiguration": false,
        "touchedRealZedConfiguration": false,
        "preview": previewPass,
        "backup": backupPass,
        "apply": applyPass,
        "verification": verificationPass,
        "rollback": rollbackPass,
        "rollbackRestoredOriginalBytes": rollbackPass
    ])
    return overall
}

let args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty else { usage(); exit(2) }

switch args[0] {
case "validate":
    guard args.count == 2 else { usage(); exit(2) }
    let url = URL(fileURLWithPath: args[1])
    do {
        let catalog = try CatalogLoader.load(from: url)
        print("catalog OK: \(catalog.apps.count) commercial applications")
    } catch {
        printError("error: \(error.localizedDescription)")
        exit(1)
    }
case "report":
    guard args.count == 3 else { usage(); exit(2) }
    do {
        let catalog = try CatalogLoader.load(from: URL(fileURLWithPath: args[1]))
        let data = try Data(contentsOf: URL(fileURLWithPath: args[2]))
        let installed = try JSONDecoder().decode([InstalledApplication].self, from: data)
        let matches = AppMatcher().match(installed: installed, catalog: catalog)
        let recs = matches.map { ReplacementRanker().recommendation(for: $0) }
        let summary = ReportSummary(applicationsDetected: installed.count, recommendations: recs)
        print(ReportGenerator.markdown(summary: summary, recommendations: recs))
    } catch {
        printError("error: \(error.localizedDescription)")
        exit(1)
    }
case "scan-smoke":
    guard args.count == 2 else { usage(); exit(2) }
    do {
        let pass = try runScanSmoke(catalogURL: URL(fileURLWithPath: args[1]))
        exit(pass ? 0 : 1)
    } catch {
        printError("error: \(error.localizedDescription)")
        exit(1)
    }
case "install-smoke":
    guard args.count == 2 else { usage(); exit(2) }
    do {
        let pass = try runInstallSmoke(catalogURL: URL(fileURLWithPath: args[1]))
        exit(pass ? 0 : 1)
    } catch {
        printError("error: \(error.localizedDescription)")
        exit(1)
    }
case "migration-selftest":
    guard args.count == 1 else { usage(); exit(2) }
    do {
        let pass = try runMigrationSelftest()
        exit(pass ? 0 : 1)
    } catch {
        printError("error: \(error.localizedDescription)")
        exit(1)
    }
default:
    usage(); exit(2)
}
