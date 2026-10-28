# Changelog

All notable public changes are recorded here.

## [0.1.0-preview] - 2026-10-27

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
