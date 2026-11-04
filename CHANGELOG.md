# Changelog

All notable public changes are recorded here.

## [0.2.0-preview.1] - 2026-11-04

### Added
- **Explore Alternatives:** browse curated replacement options without installing the paid app.
- Expanded catalog from 25 to **45 commercial targets**, with **70 open-source comparisons** and **55 researched macOS bundle-ID mappings**.
- Mark essential workflow features and review each alternative's Strong / Partial / Keep decision and documented losses.
- Shared required-feature selections between Explore and installed-app comparisons.
- Choice of alternatives for the apps you use; source links, documented limitations and verification dates.

### Improved
- Conservative recommendation ranking and protection against unrelated apps matching by name.
- Simpler potential-savings estimate: for curated free desktop editions such as GIMP, the recurring replacement software cost defaults to **$0**. Hosted or paid-plan variants are excluded from estimates until their costs can be established.
- Savings require a real user-entered recurring expense, a selected Strong replacement, and confirmation that the original subscription could be cancelled after switching. No savings are called realized savings.
- Stronger install-token and catalog-schema validation; migration safety checks remain intact.
- Updated local validation and 0.2.0 development-build versioning.

### Limitations
- Not all 55 identifiers have been confirmed against installed applications; support comparisons are evidence-based, not a guarantee of complete workflow or file-format compatibility.
- Some options require hosting or optional paid features. No Spotify-licensed streaming catalog replacement is claimed.
- Downloadable binaries remain ad-hoc signed, **not Apple Developer ID signed or Apple-notarized**. macOS 14+ required.
- Existing paid apps are never uninstalled and subscriptions are never cancelled automatically.

## [0.1.0-preview.1] - 2026-10-27

Initial source preview of LibreReplace.

### Included
- Native SwiftUI macOS application with local application-metadata scanning.
- Curated 25-target catalog with bundle-ID matching, dated evidence, weighted feature coverage, and strong/partial/keep outcomes.
- Confirmation-first Homebrew/official-download installation actions with no shell interpolation.
- Privacy-safe Markdown reporting and user-entered recurring-cost estimates.
- One narrow Sublime Text → Zed settings migration with preview, verified backup, output verification, and rollback.
- Portable Swift tests, catalog validation, XcodeGen project generation, CI, and the `python3 dev.py` real-Mac verification harness.

### Public-readiness hardening
- Removed an avoidable duplicate-bundle crash path from matching and added stronger malformed-catalog validation.
- Made strong recommendations depend on fresh underlying evidence, not only top-level verification dates, and reject future-dated provenance.
- Removed catalog-price fallback from savings; only user-entered recurring costs count.
- Prevented scanner symlinks from redirecting metadata reads outside configured application roots and strengthened privacy-report leakage tests.
- Tightened external URL validation and Homebrew argument safety.
- Hardened migration against malformed targets, stale/tampered previews, symlink redirection, unverified backups, failed output verification, and rollback of newly created targets.
- Corrected current catalog metadata/evidence, including TablePlus licensing, OpenDisk macOS support, Freeplane license evidence, and Skim source provenance.
- Removed obsolete internal launch/research/handoff material and rewrote public documentation around reproducible behavior and limitations.
