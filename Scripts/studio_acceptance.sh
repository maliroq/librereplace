#!/bin/bash
# Create real disposable PDF and image fixtures through XCTest; no user files.
# Show the full build/test matrix and keep a plain-text log in Downloads.
set -euo pipefail
cd "$(dirname "$0")/.."
LOG="$HOME/Downloads/LibreReplace-Studio-Acceptance.log"
if [ -e "$LOG" ]; then
  LOG="$HOME/Downloads/LibreReplace-Studio-Acceptance-$(date +%Y%m%d-%H%M%S).log"
fi
{
  echo '=== STUDIO UI SOURCE REGRESSION CHECKS ==='
  python3 Scripts/studio_ui_contract_check.py
  echo
  echo '=== GENERATED PDF, IMAGE AND OCR FIXTURE TESTS ==='
  echo 'These tests use disposable generated files. Nothing is uploaded.'
  /usr/bin/swift test --filter StudioGeneratedFixtureTests
  echo
  echo '=== SEARCHABLE PDF END-TO-END TESTS ==='
  /usr/bin/swift test --filter StudioSearchablePDFTests
  echo
  echo '=== MIXED DIGITAL + SCANNED PDF RESCUE PIPELINE ==='
  /usr/bin/swift test --filter StudioPDFRescueTests
  echo
  echo '=== COMPLETE SOURCE AND XCODE CHECKS ==='
  python3 dev.py
  echo
  echo '=== GENERATED-FIXTURE TESTS AND APP VERIFICATION FINISHED ==='
} 2>&1 | tee "$LOG"
printf '\nTest log saved to: %s\n' "$LOG"
