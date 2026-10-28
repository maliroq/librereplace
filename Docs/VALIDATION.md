# Validation

LibreReplace uses one repeatable local gate: `python3 dev.py`.

## Last independently demonstrated real-Mac baseline

On **2026-10-27**, the pre-release baseline was run on a real Mac with **Xcode 27.1 (27A9275)**. The following all passed:

- environment probes;
- portable tests;
- Python and Swift catalog validation;
- XcodeGen generation;
- native Xcode build;
- native Xcode `build-for-testing` and XCTest execution;
- built app/resource validation;
- app launch;
- real application metadata scan;
- safe Homebrew wiring probe;
- migration preview, verified backup, apply verification, and rollback using temporary fixtures.

Manual checks also confirmed that the main window opened without crashing, scanning completed and populated the normal UI, and LibreReplace did not request unrelated Documents/Desktop/Keychain access.

## Release-candidate rule

The source changes made during the public-readiness audit are not represented as having passed Xcode/macOS runtime validation until the same `python3 dev.py` gate is run again on the release-candidate archive. Portable checks can be run in non-macOS CI, but they do not replace that final Mac gate.

## Signing

Developer ID signing, notarization, stapling, and clean-machine Gatekeeper validation are tracked separately from source correctness. They are required before presenting a downloadable app binary as a normal polished distribution, but not for publishing source code.
