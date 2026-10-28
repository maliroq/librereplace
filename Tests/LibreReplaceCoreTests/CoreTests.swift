import XCTest
@testable import LibreReplaceCore

final class CoreTests: XCTestCase {
    func testBundleIDMatchingBeatsName() {
        let target = sampleApp(id: "clean", name: "CleanShot X", bundle: "example.clean")
        let catalog = Catalog(schemaVersion: "1.0", generatedAt: "2026-10-26", apps: [target])
        let installed = InstalledApplication(name: "Totally Different", bundleIdentifier: "example.clean", version: "1", path: URL(fileURLWithPath: "/Applications/X.app"))
        let match = AppMatcher().match(installed: [installed], catalog: catalog).first
        XCTAssertEqual(match?.catalogApp.id, "clean")
        XCTAssertEqual(match?.confidence, .bundleIdentifier)
    }

    func testNameAliasFallback() {
        let target = sampleApp(id: "clean", name: "CleanShot X", bundle: "example.clean", aliases: ["CleanShot"])
        let catalog = Catalog(schemaVersion: "1.0", generatedAt: "2026-10-26", apps: [target])
        let installed = InstalledApplication(name: "Clean Shot", bundleIdentifier: nil, version: nil, path: URL(fileURLWithPath: "/Applications/Clean Shot.app"))
        let match = AppMatcher().match(installed: [installed], catalog: catalog).first
        XCTAssertEqual(match?.catalogApp.id, "clean")
        XCTAssertEqual(match?.confidence, .nameAlias)
    }

    func testUnsupportedAppsRemainUnsupported() {
        let catalog = Catalog(schemaVersion: "1.0", generatedAt: "2026-10-26", apps: [sampleApp(id: "a", name: "A", bundle: "a.bundle")])
        let installed = [InstalledApplication(name: "Unknown", bundleIdentifier: "unknown.bundle", version: nil, path: URL(fileURLWithPath: "/Applications/Unknown.app"))]
        XCTAssertEqual(AppMatcher().unsupported(installed: installed, catalog: catalog).count, 1)
    }

    func testRankingRespectsCriticalFeature() {
        var app = sampleApp(id: "a", name: "A", bundle: "a.bundle")
        app = PaidApplication(
            id: app.id, name: app.name, vendor: app.vendor, bundleIdentifiers: app.bundleIdentifiers, nameAliases: app.nameAliases,
            pricing: app.pricing,
            capabilities: [Capability(id: "core", label: "Core", weight: 3, critical: true), Capability(id: "nice", label: "Nice", weight: 1)],
            alternatives: [Alternative(id: "alt", name: "Alt", license: "MIT", licenseKind: .openSource, repositoryURL: "https://example.com/repo", homepageURL: "https://example.com", install: InstallMethod(kind: .officialDownload, value: "https://example.com"), support: ["core": .none, "nice": .full], limitations: [], evidence: [], lastVerified: "2026-10-26")],
            policy: RecommendationPolicy(strongThreshold: 0.20, partialThreshold: 0.10, requireCriticalCapabilities: true), evidence: [], lastVerified: "2026-10-26"
        )
        let match = AppMatch(installed: InstalledApplication(name: "A", bundleIdentifier: "a.bundle", version: nil, path: URL(fileURLWithPath: "/Applications/A.app")), catalogApp: app, confidence: .bundleIdentifier)
        let recommendation = ReplacementRanker().recommendation(for: match, now: CatalogDate.parse("2026-10-26")!)
        XCTAssertNotEqual(recommendation.level, .strong)
        XCTAssertEqual(recommendation.bestAlternative?.missingCritical.map(\.id), ["core"])
    }

    func testStaleEvidence() {
        let now = CatalogDate.parse("2026-10-26")!
        XCTAssertTrue(EvidenceFreshness.isStale("2026-01-01", now: now))
        XCTAssertFalse(EvidenceFreshness.isStale("2026-10-01", now: now))
    }

    func testStaleAlternativeCannotRemainStrong() {
        let base = sampleApp(id: "stale", name: "Stale", bundle: "stale.bundle")
        let staleAlt = Alternative(id: "alt", name: "Alt", license: "MIT", licenseKind: .openSource, repositoryURL: "https://example.com/repo", homepageURL: "https://example.com", install: InstallMethod(kind: .officialDownload, value: "https://example.com"), support: ["core": .full], limitations: [], evidence: [], lastVerified: "2026-01-01")
        let target = PaidApplication(id: base.id, name: base.name, vendor: base.vendor, bundleIdentifiers: base.bundleIdentifiers, nameAliases: [], pricing: base.pricing, capabilities: base.capabilities, alternatives: [staleAlt], policy: base.policy, evidence: [], lastVerified: "2026-10-26")
        let installed = InstalledApplication(name: "Stale", bundleIdentifier: "stale.bundle", version: nil, path: URL(fileURLWithPath: "/Applications/Stale.app"))
        let match = AppMatch(installed: installed, catalogApp: target, confidence: .bundleIdentifier)
        XCTAssertEqual(ReplacementRanker().recommendation(for: match, now: CatalogDate.parse("2026-10-26")!).level, .partial)
    }

    func testUserConfirmedAnnualCostOverridesCatalogPricing() {
        let target = sampleApp(id: "paid", name: "Paid", bundle: "paid.bundle")
        let catalog = Catalog(schemaVersion: "1.0", generatedAt: "2026-10-26", apps: [target])
        let installed = InstalledApplication(name: "Paid", bundleIdentifier: "paid.bundle", version: nil, path: URL(fileURLWithPath: "/Applications/Paid.app"))
        let match = AppMatcher().match(installed: [installed], catalog: catalog)[0]
        let rec = ReplacementRanker().recommendation(for: match, now: CatalogDate.parse("2026-10-26")!)
        XCTAssertEqual(SavingsCalculator.annualSavings(for: [rec], annualCostOverrides: ["paid": 42]), Decimal(42))
    }


    func testStaleUnderlyingEvidenceCannotRemainStrong() {
        let base = sampleApp(id: "stale-evidence", name: "Stale Evidence", bundle: "stale.evidence")
        let staleEvidence = Evidence(kind: .feature, title: "Old feature evidence", url: "https://example.com/evidence", lastVerified: "2026-01-01")
        let target = PaidApplication(
            id: base.id, name: base.name, vendor: base.vendor, bundleIdentifiers: base.bundleIdentifiers, nameAliases: [],
            pricing: base.pricing, capabilities: base.capabilities, alternatives: base.alternatives,
            policy: base.policy, evidence: [staleEvidence], lastVerified: "2026-10-26"
        )
        let installed = InstalledApplication(name: target.name, bundleIdentifier: "stale.evidence", version: nil, path: URL(fileURLWithPath: "/Applications/Stale Evidence.app"))
        let match = AppMatch(installed: installed, catalogApp: target, confidence: .bundleIdentifier)
        XCTAssertEqual(ReplacementRanker().recommendation(for: match, now: CatalogDate.parse("2026-10-26")!).level, .partial)
    }

    func testCatalogPriceIsNeverAssumedAsUserSavings() {
        let target = sampleApp(id: "paid", name: "Paid", bundle: "paid.bundle")
        let catalog = Catalog(schemaVersion: "1.0", generatedAt: "2026-10-26", apps: [target])
        let installed = InstalledApplication(name: "Paid", bundleIdentifier: "paid.bundle", version: nil, path: URL(fileURLWithPath: "/Applications/Paid.app"))
        let match = AppMatcher().match(installed: [installed], catalog: catalog)[0]
        let rec = ReplacementRanker().recommendation(for: match, now: CatalogDate.parse("2026-10-26")!)
        XCTAssertEqual(SavingsCalculator.annualSavings(for: [rec]), 0)
    }

    func testExternalURLValidationRejectsLookalikeSchemesAndCredentials() {
        XCTAssertNil(ExternalURLSafety.httpsURL("httpx://example.com"))
        XCTAssertNil(ExternalURLSafety.httpsURL("https://user:secret@example.com/path"))
        XCTAssertNil(ExternalURLSafety.httpsURL("https:///missing-host"))
        XCTAssertNotNil(ExternalURLSafety.httpsURL("https://example.com/path"))
        XCTAssertNil(InstallActionBuilder.action(for: InstallMethod(kind: .officialDownload, value: "httpx://example.com")))
    }

    func testInstallTokenRejectsInjection() {
        XCTAssertTrue(InstallActionBuilder.isSafePackageToken("jordanbaird-ice"))
        XCTAssertFalse(InstallActionBuilder.isSafePackageToken("good; rm -rf /"))
        XCTAssertFalse(InstallActionBuilder.isSafePackageToken("../evil"))
    }

    func testHomebrewExecutorPassesArgumentsDirectlyWithoutShellExpansion() throws {
        let printf = ["/usr/bin/printf", "/bin/printf"].first { FileManager.default.isExecutableFile(atPath: $0) }
        let executable = try XCTUnwrap(printf)
        let result = try XCTUnwrap(HomebrewExecutor(executableCandidates: [executable]).run(arguments: ["%s", "literal;$(not-a-shell)"]))
        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(result.output, "literal;$(not-a-shell)")
    }

    func testPathSafetyRejectsTraversal() {
        XCTAssertTrue(PathSafety.isSafeRelativePath("Library/Application Support/App/settings.json"))
        XCTAssertFalse(PathSafety.isSafeRelativePath("../../etc/passwd"))
        XCTAssertFalse(PathSafety.isSafeRelativePath("/etc/passwd"))
    }

    func testScannerReadsOnlyAppMetadataAndDeduplicatesBundleID() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try makeFakeApp(root: root, name: "One", bundleID: "test.bundle")
        try makeFakeApp(root: root, name: "Duplicate", bundleID: "test.bundle")
        try "private document".write(to: root.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        let scanned = AppScanner(policy: ScannerPolicy(roots: [root])).scan()
        XCTAssertEqual(scanned.count, 1)
        XCTAssertEqual(scanned.first?.bundleIdentifier, "test.bundle")
    }

    func testScannerCanBeConstructedAndUsedInsideDetachedTask() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try makeFakeApp(root: root, name: "Detached", bundleID: "detached.bundle")

        let policy = ScannerPolicy(roots: [root])
        let scanned = await Task.detached {
            AppScanner(policy: policy).scan()
        }.value

        XCTAssertEqual(scanned.count, 1)
        XCTAssertEqual(scanned.first?.bundleIdentifier, "detached.bundle")
    }

    func testMigrationDryRunApplyAndRollback() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let source = home.appendingPathComponent("Library/Application Support/Sublime Text/Packages/User/Preferences.sublime-settings")
        try fm.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"font_size": 15, "font_face": "SF Mono", "tab_size": 2, "translate_tabs_to_spaces": true}"#.write(to: source, atomically: true, encoding: .utf8)
        let target = home.appendingPathComponent(".config/zed/settings.json")
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"buffer_font_size": 13, "unrelated": "keep"}"#.write(to: target, atomically: true, encoding: .utf8)

        let adapter = SublimeToZedMigration()
        let plan = try adapter.preview(home: home, fileManager: fm)
        XCTAssertEqual(plan.changes.count, 4)
        let original = try Data(contentsOf: target)
        let receipt = try adapter.apply(plan: plan, home: home, backupRoot: home.appendingPathComponent(".libreplace-backups"), fileManager: fm)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(receipt.backupPath)), original)
        let changed = try String(contentsOf: target, encoding: .utf8)
        XCTAssertTrue(changed.contains("buffer_font_size"))
        XCTAssertTrue(changed.contains("unrelated"))
        try adapter.rollback(receipt: receipt, home: home, fileManager: fm)
        XCTAssertEqual(try Data(contentsOf: target), original)
    }


    func testMigrationRejectsMalformedExistingTarget() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let source = home.appendingPathComponent("Library/Application Support/Sublime Text/Packages/User/Preferences.sublime-settings")
        let target = home.appendingPathComponent(".config/zed/settings.json")
        try fm.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"font_size": 15}"#.write(to: source, atomically: true, encoding: .utf8)
        try "{ definitely not json".write(to: target, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try SublimeToZedMigration().preview(home: home, fileManager: fm)) { error in
            guard case MigrationError.invalidTarget = error else { return XCTFail("Expected invalidTarget, got \(error)") }
        }
    }

    func testMigrationRejectsStaleOrTamperedPreview() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let source = home.appendingPathComponent("Library/Application Support/Sublime Text/Packages/User/Preferences.sublime-settings")
        let target = home.appendingPathComponent(".config/zed/settings.json")
        try fm.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"font_size": 15}"#.write(to: source, atomically: true, encoding: .utf8)
        try #"{"buffer_font_size": 13}"#.write(to: target, atomically: true, encoding: .utf8)

        let adapter = SublimeToZedMigration()
        let plan = try adapter.preview(home: home, fileManager: fm)
        let modified = #"{"buffer_font_size": 14}"#
        try modified.write(to: target, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try adapter.apply(plan: plan, home: home, backupRoot: home.appendingPathComponent("Backups"), fileManager: fm)) { error in
            guard case MigrationError.stalePlan = error else { return XCTFail("Expected stalePlan, got \(error)") }
        }
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), modified)

        let tampered = MigrationPlan(
            adapterID: adapter.id,
            sourcePath: plan.sourcePath,
            targetPath: home.appendingPathComponent("unrelated.json"),
            changes: plan.changes,
            warnings: plan.warnings
        )
        XCTAssertThrowsError(try adapter.apply(plan: tampered, home: home, backupRoot: home.appendingPathComponent("Backups"), fileManager: fm))
    }

    func testMigrationRejectsSymlinkedTarget() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let source = home.appendingPathComponent("Library/Application Support/Sublime Text/Packages/User/Preferences.sublime-settings")
        let target = home.appendingPathComponent(".config/zed/settings.json")
        let unrelated = home.appendingPathComponent("unrelated.json")
        try fm.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"font_size": 15}"#.write(to: source, atomically: true, encoding: .utf8)
        try #"{"safe": true}"#.write(to: unrelated, atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(at: target, withDestinationURL: unrelated)

        XCTAssertThrowsError(try SublimeToZedMigration().preview(home: home, fileManager: fm)) { error in
            guard case MigrationError.unsafePath = error else { return XCTFail("Expected unsafePath, got \(error)") }
        }
        XCTAssertEqual(try String(contentsOf: unrelated, encoding: .utf8), #"{"safe": true}"#)
    }

    func testRollbackRemovesTargetCreatedByMigration() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let source = home.appendingPathComponent("Library/Application Support/Sublime Text/Packages/User/Preferences.sublime-settings")
        let target = home.appendingPathComponent(".config/zed/settings.json")
        try fm.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"font_size": 15}"#.write(to: source, atomically: true, encoding: .utf8)

        let adapter = SublimeToZedMigration()
        let plan = try adapter.preview(home: home, fileManager: fm)
        let receipt = try adapter.apply(plan: plan, home: home, backupRoot: home.appendingPathComponent("Backups"), fileManager: fm)
        XCTAssertFalse(receipt.targetExistedBeforeApply)
        XCTAssertNil(receipt.backupPath)
        XCTAssertTrue(fm.fileExists(atPath: target.path))
        try adapter.rollback(receipt: receipt, home: home, fileManager: fm)
        XCTAssertFalse(fm.fileExists(atPath: target.path))
    }

    func testScannerDoesNotFollowSymlinkedAppOutsideConfiguredRoot() throws {
        let fm = FileManager.default
        let fixture = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: fixture) }
        let root = fixture.appendingPathComponent("Applications")
        let outside = fixture.appendingPathComponent("Private/Outside.app/Contents")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleName": "Outside",
            "CFBundleIdentifier": "example.outside"
        ], format: .xml, options: 0)
        try plist.write(to: outside.appendingPathComponent("Info.plist"))
        try fm.createSymbolicLink(at: root.appendingPathComponent("Outside.app"), withDestinationURL: outside.deletingLastPathComponent())

        let scanned = AppScanner(policy: ScannerPolicy(roots: [root]), fileManager: fm).scan()
        XCTAssertTrue(scanned.isEmpty)
    }

    func testScannerIgnoresMalformedBundleMetadataAndToleratesMissingBundleID() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let malformed = root.appendingPathComponent("Malformed.app/Contents")
        try fm.createDirectory(at: malformed, withIntermediateDirectories: true)
        try "not a plist".write(to: malformed.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

        let noID = root.appendingPathComponent("NoID.app/Contents")
        try fm.createDirectory(at: noID, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleName": "No ID"], format: .xml, options: 0)
        try plist.write(to: noID.appendingPathComponent("Info.plist"))

        let scanned = AppScanner(policy: ScannerPolicy(roots: [root]), fileManager: fm).scan()
        XCTAssertEqual(scanned.count, 1)
        XCTAssertEqual(scanned.first?.name, "No ID")
        XCTAssertNil(scanned.first?.bundleIdentifier)
    }

    func testBundledCatalogLoadsAndProducesARecommendationForEveryTarget() throws {
        let catalog = try CatalogLoader.load(from: launchCatalogURL())
        XCTAssertEqual(catalog.apps.count, 25)
        for app in catalog.apps {
            let installed = InstalledApplication(name: app.name, bundleIdentifier: app.bundleIdentifiers.first, version: "fixture", path: URL(fileURLWithPath: "/Applications/\(app.name).app"))
            let match = try XCTUnwrap(AppMatcher().match(installed: [installed], catalog: catalog).first, "No match for \(app.name)")
            let rec = ReplacementRanker().recommendation(for: match, now: CatalogDate.parse("2026-10-26")!)
            XCTAssertNotNil(rec.bestAlternative, "No recommendation candidate for \(app.name)")
        }
    }

    func testCatalogMigrationAdapterIDsAreKnown() throws {
        let catalog = try CatalogLoader.load(from: launchCatalogURL())
        let ids = Set(catalog.apps.flatMap(\.alternatives).compactMap(\.migrationAdapter))
        XCTAssertEqual(ids, [SublimeToZedMigration().id])
    }

    func testDefaultReportDoesNotRevealRecognizedAppNames() {
        let target = sampleApp(id: "private", name: "Sensitive App Name", bundle: "private.bundle")
        let installed = InstalledApplication(name: target.name, bundleIdentifier: "private.bundle", version: nil, path: URL(fileURLWithPath: "/Applications/Private.app"))
        let catalog = Catalog(schemaVersion: "1.0", generatedAt: "2026-10-26", apps: [target])
        let match = AppMatcher().match(installed: [installed], catalog: catalog)[0]
        let rec = ReplacementRanker().recommendation(for: match, now: CatalogDate.parse("2026-10-26")!)
        let report = ReportGenerator.markdown(summary: ReportSummary(applicationsDetected: 1, recommendations: [rec]), recommendations: [rec])
        XCTAssertFalse(report.contains("Sensitive App Name"))
        XCTAssertFalse(report.contains("private.bundle"))
        XCTAssertFalse(report.contains("/Applications/Private.app"))
        XCTAssertFalse(report.contains("Alternative"))
    }

    func testCatalogValidatorCatchesDuplicateBundleAndMalformedSupport() {
        var apps = (0..<20).map { sampleApp(id: "app\($0)", name: "App \($0)", bundle: "bundle.\($0)") }
        let bad = PaidApplication(
            id: "app19", name: "Bad", vendor: "V", bundleIdentifiers: ["bundle.0"], nameAliases: [],
            pricing: Pricing(model: .unknown), capabilities: [Capability(id: "x", label: "X")],
            alternatives: [Alternative(id: "alt", name: "Alt", license: "MIT", licenseKind: .openSource, repositoryURL: nil, homepageURL: "not a url", install: InstallMethod(kind: .officialDownload, value: "https://example.com"), support: ["unknown": .full], limitations: [], evidence: [], lastVerified: "bad")],
            policy: RecommendationPolicy(), evidence: [], lastVerified: "bad"
        )
        apps[19] = bad
        let errors = CatalogValidator.validate(Catalog(schemaVersion: "1.0", generatedAt: "2026-10-26", apps: apps))
        XCTAssertTrue(errors.contains(where: { $0.contains("duplicate bundle identifier") }))
        XCTAssertTrue(errors.contains(where: { $0.contains("unknown capabilities") }))
        XCTAssertTrue(errors.contains(where: { $0.contains("invalid lastVerified") }))
    }

    func testMatcherDoesNotTrapOnDuplicateBundleIDsInUnvalidatedCatalog() {
        let first = sampleApp(id: "first", name: "First", bundle: "duplicate.bundle")
        let second = sampleApp(id: "second", name: "Second", bundle: "duplicate.bundle")
        let catalog = Catalog(schemaVersion: "1.0", generatedAt: "2026-10-27", apps: [first, second])
        let installed = InstalledApplication(name: "Installed", bundleIdentifier: "duplicate.bundle", version: nil, path: URL(fileURLWithPath: "/Applications/Installed.app"))

        let match = AppMatcher().match(installed: [installed], catalog: catalog).first
        XCTAssertEqual(match?.catalogApp.id, "first")
    }

    func testFutureVerificationDatesAreRejectedAndNeverFresh() {
        let now = CatalogDate.parse("2026-10-27")!
        XCTAssertTrue(EvidenceFreshness.isStale("2026-10-28", now: now))

        var apps = (0..<20).map { sampleApp(id: "future-app\($0)", name: "Future App \($0)", bundle: "future.bundle.\($0)") }
        let base = apps[19]
        let evidence = Evidence(kind: .feature, title: "Evidence", url: "https://example.com/evidence", lastVerified: "2026-10-28")
        let alternative = Alternative(
            id: "alt", name: "Alt", license: "MIT", licenseKind: .openSource,
            repositoryURL: "https://example.com/repo", homepageURL: "https://example.com",
            install: InstallMethod(kind: .officialDownload, value: "https://example.com/download"),
            support: ["core": .full], limitations: [], evidence: [evidence], lastVerified: "2026-10-28"
        )
        apps[19] = PaidApplication(
            id: base.id, name: base.name, vendor: base.vendor, bundleIdentifiers: base.bundleIdentifiers, nameAliases: [],
            pricing: base.pricing, capabilities: base.capabilities, alternatives: [alternative], policy: base.policy,
            evidence: [evidence], lastVerified: "2026-10-28"
        )

        let errors = CatalogValidator.validate(
            Catalog(schemaVersion: "1.0", generatedAt: "2026-10-28", apps: apps),
            now: now
        )
        XCTAssertTrue(errors.contains("generatedAt cannot be in the future"))
        XCTAssertTrue(errors.contains(where: { $0.contains("lastVerified cannot be in the future") }))
        XCTAssertTrue(errors.contains(where: { $0.contains("evidence date cannot be in the future") }))
    }

    func testCatalogValidatorRejectsDuplicateCapabilitiesAndAmbiguousNameMatchers() {
        var apps = (0..<20).map { sampleApp(id: "app\($0)", name: "App \($0)", bundle: "bundle.\($0)") }
        let base = apps[19]
        apps[19] = PaidApplication(
            id: base.id,
            name: "App-0",
            vendor: base.vendor,
            bundleIdentifiers: base.bundleIdentifiers,
            nameAliases: [],
            pricing: base.pricing,
            capabilities: [
                Capability(id: "core", label: "Core", weight: 1, critical: true),
                Capability(id: "core", label: "Duplicate", weight: 1)
            ],
            alternatives: [Alternative(
                id: "alt", name: "Alt", license: "MIT", licenseKind: .openSource,
                repositoryURL: "https://example.com/repo", homepageURL: "https://example.com",
                install: InstallMethod(kind: .officialDownload, value: "https://example.com/download"),
                support: ["core": .full], limitations: [],
                evidence: [Evidence(kind: .feature, title: "Evidence", url: "https://example.com/evidence", lastVerified: "2026-10-27")],
                lastVerified: "2026-10-27"
            )],
            policy: RecommendationPolicy(),
            evidence: [Evidence(kind: .feature, title: "Evidence", url: "https://example.com/source", lastVerified: "2026-10-27")],
            lastVerified: "2026-10-27"
        )

        let errors = CatalogValidator.validate(Catalog(schemaVersion: "1.0", generatedAt: "2026-10-27", apps: apps))
        XCTAssertTrue(errors.contains(where: { $0.contains("duplicate or empty capability id") }))
        XCTAssertTrue(errors.contains(where: { $0.contains("ambiguous name matcher") }))
    }

    private func launchCatalogURL() throws -> URL {
#if SWIFT_PACKAGE
        // Swift Package Manager executes these tests from the source checkout.
        // Keep the portable path explicit; native Xcode tests use their bundled
        // resource so Xcode's managed test service never needs source-tree access.
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repo.appendingPathComponent("Catalog/catalog.json")
#else
        return try XCTUnwrap(
            Bundle(for: CoreTests.self).url(forResource: "catalog", withExtension: "json"),
            "Xcode test bundle is missing catalog.json"
        )
#endif
    }

    private func sampleApp(id: String, name: String, bundle: String, aliases: [String] = []) -> PaidApplication {
        PaidApplication(
            id: id, name: name, vendor: "Vendor", bundleIdentifiers: [bundle], nameAliases: aliases,
            pricing: Pricing(model: .subscription, recurringAnnualUSD: 30),
            capabilities: [Capability(id: "core", label: "Core", critical: true)],
            alternatives: [Alternative(id: "alt", name: "Alternative", license: "MIT", licenseKind: .openSource, repositoryURL: "https://example.com/repo", homepageURL: "https://example.com", install: InstallMethod(kind: .officialDownload, value: "https://example.com"), support: ["core": .full], limitations: [], evidence: [], lastVerified: "2026-10-26")],
            policy: RecommendationPolicy(), evidence: [], lastVerified: "2026-10-26"
        )
    }

    private func makeFakeApp(root: URL, name: String, bundleID: String) throws {
        let app = root.appendingPathComponent("\(name).app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleName": name, "CFBundleIdentifier": bundleID, "CFBundleShortVersionString": "1.0"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }
}
