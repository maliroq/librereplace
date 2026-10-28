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

## Binary distribution

Do this only when Developer ID distribution is intentionally configured:

1. Build an Archive with a Developer ID Application certificate.
2. Export/package the application.
3. Submit it to Apple notarization and staple the ticket.
4. Verify Gatekeeper on a clean Mac or clean user account.
5. Smoke-test the exact packaged artifact.
6. Publish the binary and its SHA-256 checksum separately from the source archive.

Never attach an unsigned Debug build as a polished user download, and never weaken signing, Gatekeeper, installer, or migration protections merely to make a release easier.
