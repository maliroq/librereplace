#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
umask 022

die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }
[[ "$(uname -s)" == "Darwin" ]] || die "macOS is required."
for c in xcodebuild xcodegen codesign ditto open sw_vers uname; do need "$c"; done
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
INSTALL_DIR="${LIBREREPLACE_INSTALL_DIR:-$HOME/Applications}"
TARGET="$INSTALL_DIR/LibreReplace.app"
DERIVED="$(mktemp -d "${TMPDIR:-/tmp}/LibreReplaceLocalBuild.XXXXXX")"
BUILT="$DERIVED/Build/Products/Release/LibreReplace.app"
STAGED="$INSTALL_DIR/.LibreReplace.app.installing.$$"
BACKUP=""
NEW_INSTALLED=0
cleanup(){ set +e; rm -rf "$STAGED" "$DERIVED"; }
rollback(){
  set +e
  [[ "$NEW_INSTALLED" == "1" && -d "$TARGET" ]] && rm -rf "$TARGET"
  if [[ -n "$BACKUP" && -d "$BACKUP" ]]; then
    mv "$BACKUP" "$TARGET"
    printf 'Previous LibreReplace installation restored after failure.\n' >&2
  fi
}
trap cleanup EXIT
trap rollback ERR
MAC_MAJOR="$(sw_vers -productVersion | awk -F. '{print $1}')"
[[ "$MAC_MAJOR" =~ ^[0-9]+$ ]] && (( MAC_MAJOR >= 14 )) || die "LibreReplace requires macOS 14 or later."
ARCH="$(uname -m)"
case "$ARCH" in arm64|x86_64) ;; *) die "Unsupported architecture: $ARCH";; esac
SELECTED="$(xcode-select -p 2>/dev/null || true)"
[[ "$SELECTED" == *".app/Contents/Developer"* ]] || die "Full Xcode must be selected with xcode-select."
printf 'LibreReplace %s local Release build\n' "$VERSION"
printf 'Destination: %s\n' "$TARGET"
printf 'Signing: local ad-hoc only; no Apple credentials are requested.\n'
cd "$ROOT"
xcodegen generate >/dev/null
xcodebuild -quiet -project LibreReplace.xcodeproj -scheme LibreReplace -configuration Release \
  -destination "platform=macOS,arch=$ARCH" -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  "INFOPLIST_KEY_CFBundleShortVersionString=0.1.0" \
  "INFOPLIST_KEY_CFBundleVersion=1" build
[[ -d "$BUILT" ]] || die "Release app was not produced."
INFO="$BUILT/Contents/Info.plist"
[[ -f "$INFO" ]] || die "Built app Info.plist is missing."
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.1.0" "$INFO" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 0.1.0" "$INFO"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 1" "$INFO" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" "$INFO"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")" == "0.1.0" ]] || die "Local app version stamp failed."
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO")" == "1" ]] || die "Local app build stamp failed."
FRAMEWORK="$BUILT/Contents/Frameworks/LibreReplaceCore.framework"
[[ -d "$FRAMEWORK" ]] && codesign --force --sign - --timestamp=none "$FRAMEWORK"
codesign --force --sign - --timestamp=none "$BUILT"
codesign --verify --deep --strict --verbose=2 "$BUILT"
SIGINFO="$(codesign -dv --verbose=4 "$BUILT" 2>&1 || true)"
if ! printf '%s\n' "$SIGINFO" | grep -Eqi 'Signature=adhoc|CodeDirectory .*flags=.*\([^)]*adhoc[^)]*\)'; then
  printf '%s\n' "$SIGINFO" >&2
  die "Expected an ad-hoc signature."
fi
mkdir -p "$INSTALL_DIR"
rm -rf "$STAGED"
ditto "$BUILT" "$STAGED"
codesign --verify --deep --strict --verbose=2 "$STAGED"
if [[ -e "$TARGET" ]]; then
  BACKUP="$INSTALL_DIR/LibreReplace.app.backup-$(date -u +%Y%m%dT%H%M%SZ)"
  mv "$TARGET" "$BACKUP"
  printf 'Existing app preserved at: %s\n' "$BACKUP"
fi
mv "$STAGED" "$TARGET"
NEW_INSTALLED=1
codesign --verify --deep --strict --verbose=2 "$TARGET"
open -n "$TARGET"
printf '\nLibreReplace local installation complete.\n'
printf 'Installed: %s\n' "$TARGET"
printf 'This copy is ad-hoc signed and not Apple-notarized.\n'
printf 'No Gatekeeper setting or quarantine attribute was changed.\n'
printf 'Uninstall app bundle: rm -rf %q\n' "$TARGET"
if [[ -n "$BACKUP" ]]; then
  printf 'Previous app backup: %s\n' "$BACKUP"
fi
exit 0
