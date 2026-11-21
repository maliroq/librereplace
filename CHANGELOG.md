# Changelog

LibreReplace has evolved from a paid-app comparison tool into a **native Mac workspace for building free alternatives around the work that matters to you**.

## [Unreleased — LibreReplace Studio source] — 2026-11-21

### The headline: from alternative apps to complete free setups

This is the biggest leap in LibreReplace since its first preview. The November 4 edition helped people find and compare replacements. **Studio helps them put a replacement together, try useful parts of it, keep the exact plan and share the result.**

### Discover — build your own free stack

- **Introducing FreeStack combinations.** Candidate setups can assemble multiple free applications and included tools for one commercial workflow. A screenshot tool plus on-device OCR can now appear as one coherent answer to a screenshot-and-text-extraction requirement.
- **Requirements-first discovery.** Choose the capabilities you use, then let the setup engine compare combinations against those choices rather than relying on a generic app-to-app match.
- **Full-setup feature coverage.** See which requirements the entire combination covers, what remains partial and where the plan needs another tool.
- **A bigger picture with the same curated foundation.** 45 commercial Mac targets, 70 free-alternative comparisons and 100 distinct catalog products are organized around what people want to accomplish.
- **Better browsing and search.** Faster access to relevant names, better empty states, simplified comparison controls and clearer setup cards.
- **Explore before installing.** A person can review an entire proposed setup without owning the original app, downloading replacements or changing the Mac.

### Tools — useful work happens inside LibreReplace

- **Image and document text extraction.** Local OCR for selected screenshots, images and supported PDFs.
- **PDF combination.** Assemble selected documents into one PDF.
- **Searchable PDF creation.** Make supported scanned PDFs easier to search.
- **PDF Rescue.** Built-in recovery operations for supported PDF cases.
- **Image conversion.** Convert supported image files in batches.
- **Tools integrated with setups.** A relevant setup can open the correct local tool, preserve the chosen combination and provide a **Return to setup** action when the user finishes.
- **A focused no-install workflow.** Users can get value from included file tools before deciding whether they need another free application.

### My Setups — your exact plan, saved

- **Save for later.** Keep a promising setup without installing anything.
- **Restore the original combination.** Saved plans retain the source app, essential features, extra requirements and selected components—even when recommendation ordering changes later.
- **Resume in one click.** Explore a saved setup or change its requirements directly from My Setups.
- **Track real trials.** Record the tasks personally tested without conflating them with catalog feature coverage.
- **Keep focused migrations close by.** TextExpander → Espanso and Sublime Text → Zed flows are available alongside saved plans, without taking over the page.

### Guided Switch — simpler decisions, clearer control

- **A completely reworked setup journey:** Check the match → See what's ready → Try a real task → Save what worked.
- **Optional installation by design.** App detection and setup exploration come first. Missing-app installation details stay out of the way until requested.
- **Fresh, exact package approvals.** Installation consent is tied to the packages reviewed, with preflight validation and short-lived approval state.
- **Better post-install visibility.** Separate installation completion from package detection and make available installed apps easier to open.
- **Evidence-based trial tracking.** Save the specific tasks completed on the current setup and distinguish individual tool tests from the entire combination.
- **Safer switching for supported settings and snippets.** Preview, backup, verification and recovery remain part of supported migration flows.

### Community — share the whole setup

- **Portable replacement recipes.** Export and import combinations with their components and requirements.
- **Open imported recipes as real plans.** Review and adapt a shared setup in Discover without rebuilding it manually.
- **Local recipe management.** Find, inspect and remove imported recipes directly in the app.
- **Community submissions and review notes.** Package useful testing context alongside a recipe proposed for review.
- **A curated gallery foundation.** The public registry and browsing experience are in place for reviewed community contributions.

### My Mac — a clearer path from installed apps to free options

- **Local app discovery** identifies supported paid apps from installed bundle metadata.
- **Feature-aware replacement guidance** connects detected software to the same recommendation and setup experience found in Discover.
- **Potential recurring-cost savings** use amounts the user supplies rather than guessing at subscriptions.
- **Clearer statuses and next actions** make it easier to understand what a catalog match means and what to try next.

### Design, performance and quality

- **New native five-destination interface:** Discover, My Setups, Tools, Community and My Mac.
- **Sharper product presentation:** real app artwork when available, polished fallback icons, cleaner search, less redundant copy, more useful empty states and streamlined primary actions.
- **Private by design:** catalog matching and app scanning run locally; included document tools act on selected files; no account or telemetry is required.
- **Stronger safety foundations:** hardened file handling, recipe validation, migration backups, package identity checks and protected installation flow.
- **Expanded verification:** 172 portable Swift tests, native macOS Debug build and Xcode tests, scanner and migration probes, plus a successful unsigned Release configuration compile on November 21.

### Current availability

The **Studio source** is the new experience described above. The existing [v0.2.0-preview.1 downloadable app](https://github.com/maliroq/librereplace/releases/tag/v0.2.0-preview.1) is the earlier comparison-focused edition. A Studio downloadable build will follow the distribution checks.

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
