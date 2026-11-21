# Changelog

LibreReplace is growing from a paid-app comparison utility into a **feature-aware Mac replacement platform**—built to help users reduce recurring software costs with capable free and open-source options.

## [Unreleased — LibreReplace Studio source] — 2026-11-21

### The biggest LibreReplace upgrade yet

The November 4 preview compared individual paid apps with free alternatives. Studio takes the next step: **build complete replacement setups, combine complementary free tools, use local document utilities and manage the switch in one native Mac app.**

### 1. FreeStack — a replacement engine, not just an app directory

- **Multi-app replacement combinations.** LibreReplace assembles candidate setups from free alternatives and its built-in tools. When a single app falls short, the suggested combination can cover more of the selected workflow.
- **Feature-aware planning.** People choose the exact capabilities they need, and recommendations respond to those requirements.
- **Coverage across the entire setup.** Supported, partial and missing capabilities are shown for the combined tools, with evidence and limitations available for deeper inspection.
- **45 commercial Mac targets, 70 free-alternative comparisons and 100 catalog products** form the curated comparison foundation.
- **Faster Discover experience.** Cleaner cards, more relevant search results, streamlined comparisons and useful empty states.

### 2. Built-in tools — useful capabilities without another subscription

- **On-device text extraction** from supported screenshots, images and PDFs.
- **PDF combination** and **searchable PDF creation** for supported files.
- **PDF Rescue** for supported recovery operations.
- **Batch-capable image format conversion.**
- **Connected tool workflows.** A replacement setup can launch the appropriate included tool and return to the original saved setup after use.

### 3. My Setups — save an entire free replacement plan

- Save the chosen combination of apps and built-in tools without installing anything.
- Preserve the original commercial app, selected requirements and exact components when reopening a plan.
- Revise must-have features, resume a setup and record tasks actually tested.
- Keep targeted TextExpander → Espanso and Sublime Text → Zed migration journeys accessible without cluttering the main experience.

### 4. Guided Switch — take control of the transition

- Rebuilt the setup flow around **feature fit, readiness on the Mac, a real task and saved results**.
- Made installing suggested third-party apps optional, with clear preflight information and explicit approval.
- Added installation-session checks, package identity validation and separate post-install verification.
- Improved supported settings and snippet migrations with previews, backups and recovery.
- Recorded user-tested outcomes separately from catalog recommendations.

### 5. Community — reusable replacement recipes

- Export and import complete combinations with their selected features and components.
- Open an imported recipe as an editable plan in Discover.
- Manage imported recipes locally and prepare review notes when submitting a tested setup.
- Added the foundation for a curated public recipe gallery.

### 6. My Mac and the new native interface

- Introduced **five connected destinations:** Discover, My Setups, Tools, Community and My Mac.
- Connected local installed-app detection with feature-based alternatives and user-entered potential savings.
- Refined icons, fallback artwork, action hierarchy, wording and navigation for everyday Mac use.
- Preserved local processing, optional installation and user control over the original paid app.

### Engineering and release preparation

- Expanded the portable Swift suite to **172 passing tests** at the November 21 release-candidate check, alongside native Xcode build/tests, catalog validation and migration probes.
- Confirmed the **unsigned Release configuration compiles** on macOS and added a release-readiness audit.
- Hardened recipe parsing, local file operations, Homebrew approvals, migration backups and workflow-trial records.
- Kept private artwork approvals out of the public source bundle.

### Availability

**Studio is available in source on `main`.** The downloadable [v0.2.0-preview.1](https://github.com/maliroq/librereplace/releases/tag/v0.2.0-preview.1) remains the earlier comparison-focused edition while the new downloadable Studio build is prepared.

---

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
