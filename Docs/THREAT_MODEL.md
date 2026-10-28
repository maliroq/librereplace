# Threat model

## Assets to protect

- user documents and unrelated filesystem contents;
- credentials and Keychain/browser data;
- integrity of installed applications and settings;
- privacy of the installed-app inventory;
- integrity of migration backups and rollback;
- trustworthiness of catalog/install evidence.

## Threats and mitigations

### Over-broad scanning

Scanner roots are fixed to standard application directories. The scanner skips package descendants and reads only each discovered app's `Contents/Info.plist`. Real-Mac smoke output reports aggregate counts only.

### Ambiguous application matching

Exact bundle identifiers take precedence. Catalog validation rejects duplicate bundle identifiers and ambiguous normalized name matchers. The matcher itself remains non-trapping if an unvalidated catalog is passed to the public core API.

### Command injection

Homebrew actions are an executable path plus argument array, never shell source. Package tokens are validated. External install/evidence URLs must use allowed schemes, have a host where required, and cannot contain embedded credentials.

### Malicious catalog migration instructions

Catalog data cannot supply executable migration code or arbitrary paths. It can reference only compiled adapter IDs reviewed with the application.

### Migration path redirection or stale previews

The Sublime → Zed adapter requires the exact documented source/target paths, rejects symlink traversal below the allowed home root, rejects unknown/duplicate target keys, and verifies that current target values still match the preview before applying.

### Destructive migration or weak rollback

Existing target bytes are captured before backup. Backups use unique names and are byte-verified. Output is read back and verified after the atomic write. On failure, the pre-apply state is restored; if the target did not exist before apply, rollback removes the file LibreReplace created and verifies removal. Source files are never deleted.

### Privacy leakage in reports

Aggregate reports omit application names by default. Names require an explicit opt-in and include only recognized catalog apps. Full unsupported inventory is not exported.

### Stale or misleading claims

Material claims carry dated evidence. Strong recommendations require fresh app, alternative, and supporting evidence dates. The Python catalog gate also rejects evidence older than 180 days and rejects future-dated provenance. `unknown` support never increases coverage.

### Supply-chain risk

LibreReplace prefers Homebrew and official project/download pages and does not mirror third-party binaries. Upstream compromise, a compromised Homebrew installation, or a compromised host cannot be fully mitigated by LibreReplace.

## Out of scope

- protecting a Mac already controlled by another process running as the same user;
- proving an upstream project's security or privacy properties beyond cited evidence;
- migrating secrets or credentials;
- replacing macOS code signing, Gatekeeper, or notarization.
