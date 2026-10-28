# Architecture

LibreReplace keeps the portable decision/safety logic separate from the macOS UI.

## `LibreReplaceCore`

- **AppScanner** — enumerates configured application roots and reads app `Info.plist` metadata.
- **AppMatcher** — bundle-ID-first matching with conservative normalized-name fallback.
- **CatalogLoader / CatalogValidator** — decodes structured catalog data and enforces cross-field invariants.
- **ReplacementRanker** — weighted capability coverage, critical-feature gates, and evidence freshness.
- **InstallActionBuilder / HomebrewExecutor** — typed installation actions and direct no-shell process execution.
- **SavingsCalculator / ReportGenerator** — counts only user-entered recurring costs and produces privacy-safe local reports.
- **Migration primitives / SublimeToZedMigration** — preview, path constraints, backup, apply verification, and rollback.

## macOS app

`App/LibreReplaceApp` contains SwiftUI presentation and AppKit-only actions such as opening URLs/export panels. `AppState` is `@MainActor`; the synchronous metadata scanner is constructed and consumed inside a detached task so filesystem enumeration does not run on the UI actor.

## Data flow

1. Load and validate bundled `Catalog/catalog.json`.
2. Scan standard application directories locally.
3. Match supported apps.
4. Rank alternatives using the catalog's capability matrix and evidence freshness.
5. Render strong/partial/keep results.
6. Execute only explicitly confirmed install/migration actions.

The catalog is data, not executable migration code. Migration adapter IDs can only select compiled adapters reviewed with the application.
