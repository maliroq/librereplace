# Privacy

LibreReplace is local-first and contains no account system, telemetry, analytics SDK, advertising SDK, remote inventory upload, or background daemon.

## Normal application scan

The default scanner is limited to:

- `/Applications`
- `/System/Applications`
- `~/Applications`

It enumerates `.app` bundles and reads only `Contents/Info.plist` to obtain the displayed application name, bundle identifier, and version. Package descendants are skipped. The scanner does not intentionally open application support data, documents, project files, browser profiles, Keychain items, passwords, or arbitrary home-directory contents.

Scanning and recommendation do not require a network call.

## Catalog and recommendation

The catalog ships inside the app. Matching, feature scoring, stale-evidence checks, and report generation run locally. Evidence URLs are displayed as links but are not fetched during scanning or recommendation.

## Installation

Installation is always user-triggered and confirmation-first:

- Homebrew actions execute the Homebrew binary directly with an argument array; no shell is used.
- Official download/App Store actions open a validated URL after user confirmation.
- LibreReplace never automatically uninstalls the source application.

Those user-triggered external actions can of course use the network through Homebrew, the browser, or the Mac App Store.

## Savings

The app does not infer a subscription from installation. Any annual recurring amount is entered by the user, kept in process memory for the current app session, and not persisted or transmitted.

## Reports

The default Markdown report contains aggregate counts, coverage, and the user-entered savings total. It omits application names. The user may explicitly opt in to listing recognized catalog apps; unsupported/full inventory is never exported by the current report generator.

## Migration

The preview adapter reads only Sublime Text's user preference file and, if present, Zed's settings file. It maps four non-sensitive editor preferences. It does not inspect projects, source files, recent files, plugins, snippets, credentials, passwords, browser data, or Keychain contents.
