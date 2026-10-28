# Local macOS verification

From the repository root, run:

```bash
python3 dev.py
```

The harness:

- records macOS, Python, Xcode, Swift, XcodeGen, and Homebrew availability;
- compiles the Swift core before dependent probes;
- runs `make check`, both catalog validators, and Swift package tests;
- generates the Xcode project from `project.yml`;
- builds the Debug app and performs `build-for-testing`;
- verifies the native `.xctest` executable, Info.plist, bundled catalog, and `.xctestrun` paths before running XCTest;
- runs native Xcode tests against the generated test artifact;
- verifies the built app, framework metadata, and bundled catalog;
- performs a privacy-preserving real application metadata scan;
- tests installation command generation and only runs `brew --version` as the real Homebrew probe;
- exercises migration preview/backup/apply/verification/rollback entirely inside temporary fixture directories;
- launches the Debug app and asks three manual runtime questions.

Generated reports:

- `artifacts/local_verification_report.txt`
- `artifacts/local_verification_report.json`

The report sanitizes the repository/home path and does not include the full installed-app inventory, app names, bundle identifiers, versions, or private configuration data.

## Prerequisites

- macOS 14+
- Python 3.9+
- full Xcode (Command Line Tools alone are insufficient for the SwiftUI target)
- Swift supplied by Xcode
- XcodeGen

Install XcodeGen with Homebrew if needed:

```bash
brew install xcodegen
```

Homebrew is not required for scanning/comparison. If it is absent, the Homebrew wiring item remains `NOT VERIFIED` rather than being converted to a false pass.

Developer ID signing and notarization are outside this Debug verification gate.
