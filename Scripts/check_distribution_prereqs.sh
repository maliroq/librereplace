#!/usr/bin/env bash
set -euo pipefail

# Read-only preflight for future signed/notarized macOS distribution.
# It never prints private keys, passwords, app-specific passwords, or API-key contents.

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: macOS is required for Developer ID distribution checks." >&2
  exit 2
fi

NOTARY_PROFILE="${LIBREREPLACE_NOTARY_PROFILE:-${1:-}}"

printf '%s\n' "=== LibreReplace distribution preflight ==="
printf 'Xcode: '
/usr/bin/xcodebuild -version | head -n 1

IDENTITY_LINE="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null | grep 'Developer ID Application' | head -n 1 || true)"
if [[ -z "$IDENTITY_LINE" ]]; then
  echo "Developer ID Application: NOT FOUND"
  echo "RESULT: BLOCKED — install a Developer ID Application certificate before binary distribution."
  exit 3
fi

echo "Developer ID Application: FOUND"
printf '%s\n' "$IDENTITY_LINE" | sed -E 's/^[[:space:]]*[0-9]+\)[[:space:]]+[A-F0-9]+[[:space:]]+//'

if ! /usr/bin/xcrun --find notarytool >/dev/null 2>&1; then
  echo "notarytool: NOT FOUND"
  echo "RESULT: BLOCKED — install/use a current full Xcode that includes notarytool."
  exit 4
fi

echo "notarytool: FOUND"

if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "Notary keychain profile: NOT SPECIFIED"
  echo "Set LIBREREPLACE_NOTARY_PROFILE to the keychain profile name created with 'xcrun notarytool store-credentials'."
  echo "RESULT: BLOCKED — notarization authentication is not configured for this release invocation."
  exit 5
fi

if /usr/bin/xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "Notary authentication: PASS ($NOTARY_PROFILE)"
else
  echo "Notary authentication: FAIL ($NOTARY_PROFILE)"
  echo "RESULT: BLOCKED — the named keychain profile could not authenticate to Apple's notary service."
  exit 6
fi

echo "RESULT: READY FOR SIGNED DISTRIBUTION WORKFLOW"
