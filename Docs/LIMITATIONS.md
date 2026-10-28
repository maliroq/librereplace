# Known limitations

LibreReplace is intentionally narrow. These are product boundaries, not hidden backlog items.

- **Catalog coverage is finite.** The preview recognizes 25 commercial applications. Unsupported apps remain unsupported; LibreReplace does not upload or auto-classify them.
- **Bundle metadata is imperfect.** Bundle identifiers are preferred. A conservative name fallback exists for apps whose identifier is unavailable, but renamed/repackaged apps can still be missed.
- **Feature coverage is a maintained judgment.** Percentages summarize the capabilities explicitly modeled in the catalog. They do not prove equal polish, performance, accessibility, security, privacy, support, file-format fidelity, or subjective workflow fit.
- **Evidence ages.** Strong recommendations require fresh dated evidence, and CI rejects stale catalog evidence after 180 days. A project can still change between verification and use; the evidence links remain visible for inspection.
- **Pricing is informational.** Installation metadata cannot reveal whether someone has a lifetime license, bundle, education/team plan, Setapp access, or a particular subscription. Savings count only an annual recurring amount the user enters for the current session.
- **Installation is not package management.** Homebrew must already be installed for Homebrew actions. LibreReplace does not silently install Homebrew, bypass Gatekeeper, or uninstall the source app.
- **One migration adapter exists.** Sublime Text → Zed migrates four editor preferences only. It deliberately excludes plugins, projects, snippets, keybindings, themes, recent files, credentials, and document contents.
- **Rollback is scoped to LibreReplace's own migration.** The adapter verifies its backup/output and can restore the pre-apply target state, but it is not a general settings-history system.
- **Accessibility review is incomplete.** The UI uses standard SwiftUI controls, semantic labels, native focus behavior, and system light/dark appearance. A dedicated independent VoiceOver and full keyboard-navigation audit has not yet been completed for this release candidate.
- **Binary distribution is not hardened yet.** Developer ID signing, notarization, stapling, and clean-machine Gatekeeper verification are deferred. A source release is not a claim that the unsigned Debug build is ready for normal end-user distribution.
