# Contributing

Thanks for helping make LibreReplace more trustworthy.

## Add or verify an app replacement

Catalog quality matters more than catalog size. The most valuable contribution is a correction or verification that makes an existing recommendation more defensible.

For `v0.1.0-preview`, the 25-target product scope is frozen. Please verify or correct existing entries now; new target proposals should begin as a discussion until maintainers explicitly reopen catalog scope.

A catalog contribution must:

1. identify the source app with reliable bundle identifiers or conservative name aliases;
2. describe user-visible workflow capabilities rather than marketing categories;
3. cite primary sources where practical: official docs, source repositories, license text, release notes, pricing pages, and package-manager records;
4. use `partial`, `none`, or `unknown` when parity is uncertain;
5. preserve meaningful workflow losses and critical capabilities;
6. set `lastVerified` to the date the source was actually checked;
7. never infer privacy or security superiority from an open-source license alone;
8. never assume an installed app proves a particular subscription or price;
9. verify the installation path rather than copying an old package name;
10. downgrade a recommendation when evidence no longer supports its current level.

Strong recommendations require fresh source-app, alternative, and underlying capability evidence. Future-dated or stale verification cannot produce a Strong result.

## Other useful contributions

Focused bug fixes, bundle-ID corrections, accessibility fixes, reproducible safety tests, evidence-link repairs, documentation corrections, and macOS compatibility fixes are welcome.

## Security-sensitive changes

Scanner paths, process execution, URL validation, report privacy, migration paths, backups, and rollback have a higher review bar. Migration changes must remain preview-first, path-constrained, backup-verified, stale-plan safe, output-verified, and rollback-capable. Passwords, Keychain, browser credentials, private documents, and unrelated user data are out of scope.

## Development

Run:

```bash
make check
```

On a Mac, run the complete gate before requesting release-level review:

```bash
python3 dev.py
```

The Swift core should remain portable and independent of AppKit; macOS UI/action code belongs under `App/`. Keep pull requests focused and explain the evidence or invariant that motivates the change.
