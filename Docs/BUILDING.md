# Building and testing

## Requirements

- macOS 14+
- full Xcode with Swift 6 support
- Python 3
- XcodeGen
- Homebrew only if you want the Homebrew wiring check/install actions

Install XcodeGen:

```bash
brew install xcodegen
```

## Recommended full local gate

```bash
python3 dev.py
```

This is the release-candidate verification path. See [LOCAL_VERIFICATION.md](LOCAL_VERIFICATION.md).

## Portable checks

```bash
make check
```

This runs Swift package tests, Python and Swift catalog validation, repository safety checks, XcodeGen source-of-truth checks, and harness regression tests.

## Generate the Xcode project

```bash
xcodegen generate
open LibreReplace.xcodeproj
```

`project.yml` is the source of truth. Do not hand-edit the generated `.xcodeproj`.

## Build the unsigned Debug app

```bash
./Scripts/build_app.sh
```

An unsigned Debug build is for development/verification. Do not present it as equivalent to a Developer ID-signed and notarized release binary.
