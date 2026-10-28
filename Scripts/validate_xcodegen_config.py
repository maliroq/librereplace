#!/usr/bin/env python3
"""Validate packaging-critical XcodeGen settings without requiring XcodeGen/PyYAML."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "project.yml"
lines = PROJECT.read_text(encoding="utf-8").splitlines()


def target_block(name: str) -> list[str]:
    marker = f"  {name}:"
    try:
        start = lines.index(marker) + 1
    except ValueError:
        return []
    block = []
    for line in lines[start:]:
        if line.startswith("  ") and not line.startswith("    ") and line.rstrip().endswith(":"):
            break
        block.append(line)
    return block


def require_lines(target_name: str, required: set[str], problems: list[str]) -> list[str]:
    block = target_block(target_name)
    if not block:
        problems.append(f"{target_name} target is missing")
        return []
    normalized = {line.strip() for line in block if line.strip()}
    for setting in sorted(required):
        if setting not in normalized:
            problems.append(f"{target_name} missing required XcodeGen setting: {setting}")
    return block


problems: list[str] = []

require_lines(
    "LibreReplaceCore",
    {
        "type: framework",
        "PRODUCT_BUNDLE_IDENTIFIER: org.librereplace.core",
        "GENERATE_INFOPLIST_FILE: YES",
    },
    problems,
)

app = require_lines(
    "LibreReplace",
    {
        "type: application",
        "- path: App/LibreReplaceApp",
        "- path: Catalog/catalog.json",
        "buildPhase: resources",
        "- target: LibreReplaceCore",
        "GENERATE_INFOPLIST_FILE: YES",
        "ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon",
    },
    problems,
)
if any(line.strip() == "resources:" for line in app):
    problems.append(
        "LibreReplace must not use the top-level target resources: key for catalog.json; "
        "XcodeGen 2.46 can silently omit it. Use a sources entry with buildPhase: resources."
    )


icon_contents = ROOT / "App" / "LibreReplaceApp" / "Assets.xcassets" / "AppIcon.appiconset" / "Contents.json"
if not icon_contents.is_file():
    problems.append("LibreReplace AppIcon asset catalog is missing")
else:
    import json
    try:
        icon_data = json.loads(icon_contents.read_text(encoding="utf-8"))
        filenames = [item.get("filename") for item in icon_data.get("images", []) if item.get("filename")]
        if len(filenames) != 10:
            problems.append(f"LibreReplace AppIcon must define 10 macOS icon slots; found {len(filenames)}")
        for filename in filenames:
            if not (icon_contents.parent / filename).is_file():
                problems.append(f"LibreReplace AppIcon image is missing: {filename}")
    except (OSError, ValueError) as exc:
        problems.append(f"LibreReplace AppIcon Contents.json is unreadable: {exc}")

require_lines(
    "LibreReplaceCoreTests",
    {
        "type: bundle.unit-test",
        "- path: Tests/LibreReplaceCoreTests",
        "- path: Catalog/catalog.json",
        "buildPhase: resources",
        "- target: LibreReplaceCore",
        "PRODUCT_BUNDLE_IDENTIFIER: org.librereplace.coretests",
        "GENERATE_INFOPLIST_FILE: YES",
    },
    problems,
)

if problems:
    print("XcodeGen configuration validation failed:")
    for problem in problems:
        print(" -", problem)
    sys.exit(1)

print(
    "XcodeGen configuration OK: framework/test bundles generate Info.plists; "
    "catalog is explicitly copied into both app and native-test Resources build phases; AppIcon is configured"
)
