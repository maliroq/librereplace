# LibreReplace v0.1.0-preview

**Replace paid Mac apps without losing what matters.**

This is a source prerelease for inspection and early testing, not a signed/notarized consumer binary release.

LibreReplace scans standard macOS application directories, recognizes 25 curated commercial apps, and compares them with evidence-backed open-source alternatives. Recommendations are conservative: feature losses are explicit and the correct outcome can be **KEEP THIS APP**.

## Included

- local metadata-only app scanning;
- 25-target evidence catalog and 41 known bundle identifiers;
- Strong / Partial / Keep recommendation levels;
- dated feature, license, maintenance, pricing, and installation evidence;
- confirmation-first install actions;
- privacy-safe Markdown reports;
- user-entered recurring-cost estimates only;
- one Sublime Text → Zed preference migration with preview, verified backup, output verification, and rollback;
- native SwiftUI app, portable Swift core/CLI, tests, CI, and local verification harness;
- custom macOS icon and publication assets;
- real Sublime Text → Zed hero capture from the validation Mac.

## Public-readiness hardening

The preview tightens migration path/backup/rollback invariants, scanner symlink boundaries, catalog URL/date validation, report privacy tests, savings semantics, and public-facing accessibility/presentation without expanding product scope. A sidebar navigation-state bug found during the real demo capture was fixed by resetting only the section-local SwiftUI navigation stack when the top-level sidebar selection changes. The 25-target catalog was re-audited and questionable claims were corrected or kept conservative.

## Validation

The engineering release candidate passed the complete real-Mac gate on Xcode 27.1, including native XCTest, app launch, real metadata scanning, Homebrew wiring, and temporary-fixture migration rollback. The branded candidate passed the same `python3 dev.py` gate before publication.

## Distribution status

Developer ID signing and Apple notarization are deferred. Source can be reviewed and built normally; an unsigned Debug `.app` should not be redistributed as a polished end-user download. No Gatekeeper bypass instructions are provided.

See [Known limitations](Docs/LIMITATIONS.md), the [Support matrix](Docs/SUPPORT_MATRIX.md), and [Building from source](Docs/BUILDING.md).
