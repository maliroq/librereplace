# Releasing

LibreReplace treats the source release and a distributable macOS binary as separate deliverables.

## Source prerelease

1. Update `VERSION`, `CHANGELOG.md`, `RELEASE_NOTES.md`, the support matrix, and catalog verification dates.
2. Run `make check` from a clean checkout.
3. On a real Mac, run `python3 dev.py` and require every applicable matrix item to pass.
4. Review the generated verification report for unexpected paths, permissions, or warnings.
5. Tag `vX.Y.Z` and push. The release workflow prepares a **draft prerelease** containing source/catalog artifacts and checksums.
6. Review the draft and publish it only after the real-Mac gate for that exact release candidate has passed.

A source prerelease does not imply that LibreReplace provides a signed/notarized end-user application binary.

## Current consumer-distribution status

`v0.1.0-preview` is intentionally source-only. Do not publish a DMG, standalone `.app`, or Homebrew Cask until all of these are true for the exact distributed artifact:

- a usable **Developer ID Application** identity is installed;
- notarization authentication is configured for `notarytool`;
- the release app is signed with hardened runtime as appropriate;
- Apple notarization succeeds;
- the notarization ticket is stapled where appropriate;
- `codesign` and Gatekeeper verification succeed;
- the final DMG is mounted and smoke-tested after packaging;
- the same DMG is the artifact referenced by any Homebrew Cask.

There are no supported Gatekeeper-bypass instructions.

## Credential preflight

The repository includes a read-only check:

```bash
Scripts/check_distribution_prereqs.sh
```

For notarization authentication, create a keychain profile with Apple's `notarytool store-credentials`, then pass only its profile name to the script:

```bash
LIBREREPLACE_NOTARY_PROFILE="LibreReplaceNotary" \
  Scripts/check_distribution_prereqs.sh
```

The script does not print or store the underlying password, private key, or API-key contents.

## Signed binary workflow — only after preflight passes

Use the already-validated source state. Do not rebuild distribution artifacts from an unrelated checkout.

1. Record the exact source commit, `VERSION`, bundle identifier, deployment target, build configuration, and architectures.
2. Run `make check` and the real-Mac `python3 dev.py` gate for that source state.
3. Generate the Xcode project from `project.yml` and build the **Release** application.
4. Sign nested executable code and frameworks with the installed **Developer ID Application** identity, then sign the outer `.app`. Preserve the hardened-runtime requirements used for direct distribution.
5. Verify the app with `codesign --verify --deep --strict --verbose=2` and inspect the designated authority/identity before packaging.
6. Create the distribution archive/DMG without changing the signed app contents.
7. Submit the signed distribution artifact using current `xcrun notarytool` tooling and require an Apple **Accepted** result. Inspect the notarization log on any failure or ambiguity.
8. Staple the ticket where supported and verify with `stapler validate`.
9. Verify Gatekeeper acceptance with the current supported `spctl` assessment for the exact distributed app/artifact.
10. Mount the exact final DMG, copy `LibreReplace.app` out to a clean temporary/Application-style destination, launch it, confirm scanner startup and primary navigation, and confirm no migration/install action occurs automatically.
11. Calculate SHA-256 for the exact verified DMG and attach that DMG to the appropriate GitHub release.
12. Only then create/update the Homebrew Cask so its `url`, `version`, and `sha256` point to that same signed/notarized GitHub release artifact.
13. Test the public cask path: syntax/style/audit, install to `/Applications`, Gatekeeper acceptance, launch, version, uninstall, reinstall, and confirmation that uninstall does not delete unrelated user data.

Do not commit certificates, API keys, app-specific passwords, notarization credentials, or exported private keys. Ordinary CI must not require Developer ID credentials.

## Homebrew Cask readiness

LibreReplace intentionally does **not** ship a live cask while the consumer artifact is unsigned/unnotarized. When a verified DMG exists, the cask should use current Homebrew Cask conventions and point to that exact versioned/checksummed DMG with:

```ruby
app "LibreReplace.app"
```

Add `zap` entries only for paths that LibreReplace itself genuinely creates and owns. If there is nothing appropriate to remove, do not invent cleanup paths merely to populate `zap`.

Before changing `maliroq/homebrew-tap`, fetch/rebase the latest tap state and preserve WireDiet plus any ComposeDrill work that has landed. Never force-push over concurrent tap changes.

## Source/binary boundary

Never attach an unsigned Debug build as a polished user download, never label ad-hoc signing as Developer ID distribution, and never weaken Gatekeeper, installer, scanner, recommendation, privacy, or migration protections merely to make release packaging easier.
