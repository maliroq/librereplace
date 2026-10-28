#!/usr/bin/env python3
"""Regression checks for the local verification harness without requiring macOS/Xcode."""
from pathlib import Path
import plistlib
import tempfile
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import dev  # noqa: E402


def main() -> int:
    # Native Xcode products must not default inside the repository/user home.
    # XCTest runs in Xcode test services whose TCC access may differ from the
    # Terminal process that invoked this harness.
    assert not str(dev.DERIVED_DATA).startswith(str(dev.ROOT)), dev.DERIVED_DATA
    assert not str(dev.DERIVED_DATA).startswith(str(Path.home())), dev.DERIVED_DATA

    original_derived = dev.DERIVED_DATA
    original_bundle = dev.TEST_BUNDLE
    try:
        with tempfile.TemporaryDirectory(prefix="librereplace-dev-harness-") as tmp:
            tmp = Path(tmp)
            derived = tmp / "DerivedData"
            products = derived / "Build" / "Products"
            bundle = products / "Debug" / "LibreReplaceCoreTests.xctest"
            executable = bundle / "Contents" / "MacOS" / "LibreReplaceCoreTests"
            executable.parent.mkdir(parents=True)
            executable.write_bytes(b"fixture")
            executable.chmod(0o755)
            resources = bundle / "Contents" / "Resources"
            resources.mkdir(parents=True)
            (resources / "catalog.json").write_bytes((ROOT / "Catalog" / "catalog.json").read_bytes())

            info = bundle / "Contents" / "Info.plist"
            with info.open("wb") as f:
                plistlib.dump(
                    {
                        "CFBundleIdentifier": "org.librereplace.coretests",
                        "CFBundleExecutable": "LibreReplaceCoreTests",
                    },
                    f,
                )

            xctestrun = products / "LibreReplace_macosx27.0-arm64.xctestrun"
            with xctestrun.open("wb") as f:
                plistlib.dump(
                    {
                        "TestConfigurations": [
                            {
                                "TestTargets": [
                                    {
                                        "BlueprintName": "LibreReplaceCoreTests",
                                        "TestBundlePath": "__TESTROOT__/Debug/LibreReplaceCoreTests.xctest",
                                    }
                                ]
                            }
                        ]
                    },
                    f,
                )

            dev.DERIVED_DATA = derived
            dev.TEST_BUNDLE = bundle

            bundle_probe = dev.test_bundle_checks(bundle)
            run_probe = dev.xctestrun_checks(xctestrun)
            assert bundle_probe["pass"] is True, bundle_probe
            assert bundle_probe["actualExecutableNames"] == ["LibreReplaceCoreTests"], bundle_probe
            assert bundle_probe["testCatalogExists"] is True, bundle_probe
            assert bundle_probe["testCatalogJSONReadable"] is True, bundle_probe
            assert bundle_probe["testCatalogMatchesSource"] is True, bundle_probe
            assert run_probe["pass"] is True, run_probe
            assert run_probe["referencesExpectedTestBundle"] is True, run_probe
            assert run_probe["testArchitecture"] == "arm64", run_probe
            assert run_probe["testArchitectureSource"] == "xctestrun filename", run_probe
            assert run_probe["testDestination"] == "platform=macOS,arch=arm64", run_probe
    finally:
        dev.DERIVED_DATA = original_derived
        dev.TEST_BUNDLE = original_bundle

    print("Local verification harness regression checks OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
