# Releasing

LibreReplace keeps source, no-cost preview binaries, and future Apple-trusted binaries distinct.

## Recommended local build

```bash
git clone https://github.com/maliroq/LibreReplace.git
cd LibreReplace
./Scripts/install_local.sh
```

`install_local.sh` requires macOS 14+, full Xcode, and XcodeGen. It builds locally, applies an ad-hoc signature, verifies the bundle, installs to `~/Applications/LibreReplace.app` by default, and launches it. It does not request Apple credentials, use `sudo`, clear quarantine, or disable Gatekeeper.

## No-cost downloadable preview

A downloadable preview may ship without Developer ID only after the exact source commit passes `make check` and `python3 dev.py`, the Release app is ad-hoc signed and verified, the exact DMG is mounted/copied/version-checked/launched, and the release prominently states that it is not Developer ID signed or Apple-notarized. Publish the exact source commit and DMG SHA-256.

Never document or automate quarantine removal, Gatekeeper disablement, or system-wide security weakening. For a downloaded non-notarized app, the only documented exception path is Apple's normal per-app UI after first launch attempt: **System Settings → Privacy & Security → Open Anyway**. The local build remains the recommended route for users who do not want to approve a downloaded non-notarized app.

## Homebrew Cask

A third-party Cask may reference the same exact DMG only if current Homebrew can install, uninstall, and reinstall it while preserving quarantine and without an automatic Gatekeeper bypass. Pin exact version, URL, and SHA-256; use `app "LibreReplace.app"` and `zap :not_required`. If that security-preserving test fails, do not publish or retain the Cask.

Before any tap push, fetch/rebase the latest `maliroq/homebrew-tap` state and preserve every existing project. Never force-push.

## Future Developer ID / notarized distribution

`Scripts/check_distribution_prereqs.sh` remains the future preflight. When Developer ID Application and notarization authentication are intentionally configured: validate the exact source, build Release, Developer ID-sign nested code and the app, verify, notarize and require Accepted, staple, verify Gatekeeper, mount-test the final DMG, publish its checksum, then update the Cask to that same artifact.

Do not commit certificates, private keys, API keys, app-specific passwords, or notarization credentials.

## Frozen product boundary

Distribution work must not change scanner semantics, metadata-only privacy, detection, recommendation ranking, Strong / Partial / Keep policy, savings semantics, migration preview/backup/rollback, catalog rules, or security invariants.
