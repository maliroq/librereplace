#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo "xcodegen is required: brew install xcodegen" >&2; exit 1; }
xcodegen generate
xcodebuild -project LibreReplace.xcodeproj -scheme LibreReplace -configuration Debug -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
printf '\nBuilt app:\n%s\n' "$(pwd)/DerivedData/Build/Products/Debug/LibreReplace.app"
