#!/usr/bin/env python3
"""Deterministic local macOS verification harness for LibreReplace.

Run from the repository root with:
    python3 dev.py

The harness never installs third-party applications, never reads private user
files, and never touches real Sublime Text or Zed settings. It writes sanitized
reports to artifacts/local_verification_report.{txt,json}.
"""

import argparse
import hashlib
import json
import os
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ARTIFACTS = ROOT / "artifacts"
TXT_REPORT = ARTIFACTS / "local_verification_report.txt"
JSON_REPORT = ARTIFACTS / "local_verification_report.json"
CATALOG = ROOT / "Catalog" / "catalog.json"
# Keep Xcode build/test products outside macOS privacy-protected user folders
# (Downloads/Desktop/Documents). The source tree may live there because the user
# explicitly invoked Terminal from it, but XCTest is launched by Xcode test
# services that can have different TCC access. A neutral temp location avoids
# false "bundle executable couldn't be located" failures without asking for
# Full Disk Access. The path is deterministic per local user and is cleared at
# the start of each native validation run.
DERIVED_DATA = Path(tempfile.gettempdir()) / f"LibreReplaceDerivedData-{os.getuid() if hasattr(os, 'getuid') else 'local'}"
APP_BUNDLE = DERIVED_DATA / "Build" / "Products" / "Debug" / "LibreReplace.app"
TEST_BUNDLE = DERIVED_DATA / "Build" / "Products" / "Debug" / "LibreReplaceCoreTests.xctest"

PASS = "PASS"
FAIL = "FAIL"
NOT_VERIFIED = "NOT VERIFIED"
NEEDS_MANUAL = "NEEDS MANUAL CONFIRMATION"
DEFERRED = "DEFERRED"

COMMANDS = []
NOTES = []
MANUAL = {}
RESOURCE_CHECKS = {}
PROBES = {}


def sanitize(text):
    if text is None:
        return ""
    value = str(text)
    # Reports are intended to be safe to paste back into ChatGPT. Remove the
    # repository's absolute path and the user's home-directory prefix.
    replacements = [
        (str(ROOT), "<REPO>"),
        (str(DERIVED_DATA), "<DERIVED_DATA>"),
        (str(Path.home()), "~"),
        (platform.node(), "<HOST>"),
    ]
    for old, new in replacements:
        if old:
            value = value.replace(old, new)
    return value


def trim_output(text, limit=16000):
    text = sanitize(text)
    if len(text) <= limit:
        return text
    head = text[:2500]
    tail = text[-(limit - 2600):]
    return head + "\n... <output truncated; failure tail preserved> ...\n" + tail


def display_command(cmd):
    return " ".join(str(x) if re.fullmatch(r"[A-Za-z0-9_./:=+,-]+", str(x)) else repr(str(x)) for x in cmd)


def run_command(label, cmd, env=None, timeout=900, cwd=ROOT, quiet=False):
    print("\n== {} ==".format(label))
    print("$ {}".format(sanitize(display_command(cmd))))
    started = time.monotonic()
    try:
        cp = subprocess.run(
            [str(x) for x in cmd],
            cwd=str(cwd),
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            check=False,
        )
        code = cp.returncode
        stdout = cp.stdout or ""
        stderr = cp.stderr or ""
    except FileNotFoundError as exc:
        code = 127
        stdout = ""
        stderr = str(exc)
    except subprocess.TimeoutExpired as exc:
        code = 124
        stdout = exc.stdout.decode(errors="replace") if isinstance(exc.stdout, bytes) else (exc.stdout or "")
        stderr = exc.stderr.decode(errors="replace") if isinstance(exc.stderr, bytes) else (exc.stderr or "")
        stderr += "\nCommand timed out."
    duration = round(time.monotonic() - started, 3)
    record = {
        "label": label,
        "command": sanitize(display_command(cmd)),
        "exitCode": code,
        "durationSeconds": duration,
        "stdout": trim_output(stdout),
        "stderr": trim_output(stderr),
    }
    COMMANDS.append(record)
    status = PASS if code == 0 else FAIL
    print("{} (exit {})".format(status, code))
    if not quiet and code != 0:
        combined = (record["stdout"] + "\n" + record["stderr"]).strip()
        if combined:
            print(combined[-5000:])
    return code, stdout, stderr


def parse_json_stdout(stdout):
    try:
        return json.loads(stdout)
    except Exception:
        return None


def sha256(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def version_tuple(text):
    parts = []
    for piece in (text or "").split("."):
        match = re.match(r"(\d+)", piece)
        if not match:
            break
        parts.append(int(match.group(1)))
    return tuple(parts)


def xcode_developer_candidates(selected_path):
    candidates = []
    explicit = os.environ.get("DEVELOPER_DIR")
    if explicit and ".app/Contents/Developer" in explicit:
        candidates.append(Path(explicit))
    if selected_path and ".app/Contents/Developer" in selected_path and Path(selected_path) not in candidates:
        candidates.append(Path(selected_path))
    apps = Path("/Applications")
    if apps.exists():
        for app in sorted(apps.glob("Xcode*.app")):
            developer = app / "Contents" / "Developer"
            if developer.exists() and developer not in candidates:
                candidates.append(developer)
    return candidates


def ask(question_key, text):
    print("\n{}:".format(question_key))
    print(text)
    while True:
        try:
            answer = input("[y/n/s to skip] ").strip().lower()
        except EOFError:
            answer = "s"
        if answer in ("y", "yes"):
            MANUAL[question_key] = {"answer": "yes", "prompt": text}
            return "yes"
        if answer in ("n", "no"):
            MANUAL[question_key] = {"answer": "no", "prompt": text}
            return "no"
        if answer in ("s", "skip", ""):
            MANUAL[question_key] = {"answer": "skipped", "prompt": text}
            return "skipped"
        print("Enter y, n, or s.")


def resource_checks(app_bundle):
    result = {
        "appBundleExists": app_bundle.is_dir(),
        "executableExists": False,
        "infoPlistReadable": False,
        "bundleIdentifierCorrect": False,
        "coreFrameworkExists": False,
        "coreFrameworkInfoPlistReadable": False,
        "coreFrameworkBundleIdentifierCorrect": False,
        "bundledCatalogExists": False,
        "bundledCatalogMatchesSource": False,
        "bundledCatalogJSONReadable": False,
        "bundledCatalogAppCount": None,
    }
    if not app_bundle.is_dir():
        return result

    executable = app_bundle / "Contents" / "MacOS" / "LibreReplace"
    info = app_bundle / "Contents" / "Info.plist"
    bundled_catalog = app_bundle / "Contents" / "Resources" / "catalog.json"
    result["executableExists"] = executable.is_file() and os.access(str(executable), os.X_OK)

    try:
        with info.open("rb") as f:
            plist = plistlib.load(f)
        result["infoPlistReadable"] = True
        result["bundleIdentifierCorrect"] = plist.get("CFBundleIdentifier") == "org.librereplace.LibreReplace"
    except Exception as exc:
        result["infoPlistError"] = sanitize(exc)

    framework = app_bundle / "Contents" / "Frameworks" / "LibreReplaceCore.framework"
    result["coreFrameworkExists"] = framework.is_dir()
    if framework.is_dir():
        framework_info_candidates = [
            framework / "Resources" / "Info.plist",
            framework / "Versions" / "Current" / "Resources" / "Info.plist",
            framework / "Versions" / "A" / "Resources" / "Info.plist",
            framework / "Info.plist",
        ]
        framework_info = next((candidate for candidate in framework_info_candidates if candidate.is_file()), None)
        if framework_info is not None:
            try:
                with framework_info.open("rb") as f:
                    framework_plist = plistlib.load(f)
                result["coreFrameworkInfoPlistReadable"] = True
                result["coreFrameworkBundleIdentifierCorrect"] = (
                    framework_plist.get("CFBundleIdentifier") == "org.librereplace.core"
                )
            except Exception as exc:
                result["coreFrameworkInfoPlistError"] = sanitize(exc)
        else:
            result["coreFrameworkInfoPlistError"] = "LibreReplaceCore.framework contains no Info.plist"

    result["bundledCatalogExists"] = bundled_catalog.is_file()
    if bundled_catalog.is_file():
        try:
            bundled = json.loads(bundled_catalog.read_text(encoding="utf-8"))
            result["bundledCatalogJSONReadable"] = True
            result["bundledCatalogAppCount"] = len(bundled.get("apps", []))
            result["bundledCatalogMatchesSource"] = sha256(bundled_catalog) == sha256(CATALOG)
        except Exception as exc:
            result["bundledCatalogError"] = sanitize(exc)
    return result


def _safe_dir_names(path):
    try:
        return sorted(entry.name for entry in path.iterdir())
    except Exception:
        return []


def test_bundle_checks(test_bundle):
    result = {
        "testBundleExists": test_bundle.is_dir(),
        "testBundleContents": [],
        "testMacOSDirectoryExists": False,
        "testMacOSContents": [],
        "actualExecutableNames": [],
        "testExecutableExists": False,
        "testExecutableIsExecutable": False,
        "testExecutableSizeBytes": None,
        "testInfoPlistReadable": False,
        "testBundleIdentifierCorrect": False,
        "testInfoPlistExecutable": None,
        "testInfoPlistExecutableCorrect": False,
        "testCatalogExists": False,
        "testCatalogJSONReadable": False,
        "testCatalogAppCount": None,
        "testCatalogMatchesSource": False,
    }
    if not test_bundle.is_dir():
        return result

    result["testBundleContents"] = _safe_dir_names(test_bundle)
    macos_dir = test_bundle / "Contents" / "MacOS"
    result["testMacOSDirectoryExists"] = macos_dir.is_dir()
    result["testMacOSContents"] = _safe_dir_names(macos_dir) if macos_dir.is_dir() else []
    if macos_dir.is_dir():
        result["actualExecutableNames"] = sorted(
            entry.name for entry in macos_dir.iterdir()
            if entry.is_file() and os.access(str(entry), os.X_OK)
        )

    executable = macos_dir / "LibreReplaceCoreTests"
    info = test_bundle / "Contents" / "Info.plist"
    test_catalog = test_bundle / "Contents" / "Resources" / "catalog.json"
    result["testExecutableExists"] = executable.is_file()
    result["testExecutableIsExecutable"] = executable.is_file() and os.access(str(executable), os.X_OK)
    if executable.is_file():
        try:
            result["testExecutableSizeBytes"] = executable.stat().st_size
        except OSError:
            pass
    try:
        with info.open("rb") as f:
            plist = plistlib.load(f)
        result["testInfoPlistReadable"] = True
        result["testBundleIdentifierCorrect"] = plist.get("CFBundleIdentifier") == "org.librereplace.coretests"
        result["testInfoPlistExecutable"] = plist.get("CFBundleExecutable")
        result["testInfoPlistExecutableCorrect"] = plist.get("CFBundleExecutable") == "LibreReplaceCoreTests"
    except Exception as exc:
        result["testInfoPlistError"] = sanitize(exc)

    result["testCatalogExists"] = test_catalog.is_file()
    if test_catalog.is_file():
        try:
            bundled_catalog = json.loads(test_catalog.read_text(encoding="utf-8"))
            source_catalog = json.loads((ROOT / "Catalog" / "catalog.json").read_text(encoding="utf-8"))
            result["testCatalogJSONReadable"] = True
            result["testCatalogAppCount"] = len(bundled_catalog.get("apps", [])) if isinstance(bundled_catalog, dict) else None
            result["testCatalogMatchesSource"] = bundled_catalog == source_catalog
        except Exception as exc:
            result["testCatalogError"] = sanitize(exc)

    result["pass"] = all([
        result["testBundleExists"],
        result["testMacOSDirectoryExists"],
        result["testExecutableExists"],
        result["testExecutableIsExecutable"],
        result["testInfoPlistReadable"],
        result["testBundleIdentifierCorrect"],
        result["testInfoPlistExecutableCorrect"],
        result["testCatalogExists"],
        result["testCatalogJSONReadable"],
        result["testCatalogMatchesSource"],
    ])
    return result


def _walk_dicts(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from _walk_dicts(child)
    elif isinstance(value, list):
        for child in value:
            yield from _walk_dicts(child)


def find_xctestrun():
    products = DERIVED_DATA / "Build" / "Products"
    if not products.is_dir():
        return None
    candidates = sorted(products.rglob("*.xctestrun"), key=lambda path: path.stat().st_mtime, reverse=True)
    return candidates[0] if candidates else None


def xctestrun_destination(xctestrun_path):
    """Return a destination constrained to the architecture built into an .xctestrun.

    Xcode 27 can expose several macOS destination variants when test execution is
    driven only by an .xctestrun file. A generic ``platform=macOS`` destination
    may select arm64e even when build-for-testing produced an arm64 test bundle.
    Keep execution on the architecture encoded by Xcode in the manifest name.
    """
    architecture = None
    source = None
    if xctestrun_path:
        match = re.search(r"-(arm64e|arm64|x86_64)\.xctestrun$", xctestrun_path.name)
        if match:
            architecture = match.group(1)
            source = "xctestrun filename"

    if architecture is None:
        host = platform.machine().lower()
        if host == "aarch64":
            host = "arm64"
        if host in {"arm64", "x86_64"}:
            architecture = host
            source = "host architecture fallback"

    destination = "platform=macOS"
    if architecture:
        destination += ",arch={}".format(architecture)
    return destination, architecture, source


def xctestrun_checks(xctestrun_path):
    destination, architecture, architecture_source = xctestrun_destination(xctestrun_path)
    result = {
        "xctestrunExists": bool(xctestrun_path and xctestrun_path.is_file()),
        "xctestrunPath": sanitize(xctestrun_path) if xctestrun_path else None,
        "testBundlePaths": [],
        "resolvedTestBundlePaths": [],
        "referencesExpectedTestBundle": False,
        "testArchitecture": architecture,
        "testArchitectureSource": architecture_source,
        "testDestination": destination,
        "pass": False,
    }
    if not xctestrun_path or not xctestrun_path.is_file():
        return result
    try:
        with xctestrun_path.open("rb") as f:
            data = plistlib.load(f)
        raw_paths = []
        for item in _walk_dicts(data):
            value = item.get("TestBundlePath")
            if isinstance(value, str) and value not in raw_paths:
                raw_paths.append(value)
        result["testBundlePaths"] = raw_paths
        resolved = []
        for raw in raw_paths:
            value = raw.replace("__TESTROOT__", str(xctestrun_path.parent))
            value = value.replace("__TESTHOST__", str(xctestrun_path.parent))
            resolved.append(sanitize(value))
            try:
                if Path(value).resolve() == TEST_BUNDLE.resolve():
                    result["referencesExpectedTestBundle"] = True
            except Exception:
                pass
        result["resolvedTestBundlePaths"] = resolved
        result["pass"] = result["referencesExpectedTestBundle"]
    except Exception as exc:
        result["error"] = sanitize(exc)
    return result


def parse_build_settings(output, names):
    parsed = {}
    for name in names:
        match = re.search(r"^\s*{}\s*=\s*(.*?)\s*$".format(re.escape(name)), output, re.MULTILINE)
        if match:
            parsed[name] = match.group(1)
    return parsed


def status_from_bool(value):
    return PASS if value else FAIL


def build_text_report(environment, matrix, prerequisites):
    lines = []
    lines.append("LibreReplace local verification report")
    lines.append("Generated: {}".format(environment["generatedAtUTC"]))
    lines.append("Repository: <REPO>")
    lines.append("")
    lines.append("SAFETY BOUNDARIES")
    lines.append("- No third-party application was installed by this harness.")
    lines.append("- Real application scanning is limited to LibreReplace's standard application roots and bundle Info.plist metadata.")
    lines.append("- Installed application names, bundle identifiers, versions, and paths are not written to this report.")
    lines.append("- Migration validation uses a temporary fixture home only; real Sublime Text and Zed settings are never touched.")
    lines.append("- SIGNING: DEFERRED")
    lines.append("- NOTARIZATION: DEFERRED")
    lines.append("")
    lines.append("ENVIRONMENT")
    for key in (
        "macOS", "python", "architecture", "xcodeSelectPath", "commandLineTools", "fullXcode",
        "developerDirUsed", "swift", "xcodegen", "homebrew", "make"
    ):
        lines.append("{}: {}".format(key, environment.get(key, "unknown")))
    lines.append("")

    if prerequisites:
        lines.append("PREREQUISITES / ACTIONS")
        for item in prerequisites:
            lines.append("- " + item)
        lines.append("")

    lines.append("SAFE RUNTIME PROBES")
    for name, value in PROBES.items():
        lines.append("{}: {}".format(name, json.dumps(value, sort_keys=True)))
    if not PROBES:
        lines.append("None completed.")
    lines.append("")

    lines.append("BUILT APP RESOURCE CHECKS")
    if RESOURCE_CHECKS:
        for key, value in RESOURCE_CHECKS.items():
            lines.append("{}: {}".format(key, value))
    else:
        lines.append("Not run.")
    lines.append("")

    lines.append("MANUAL CHECKS")
    if MANUAL:
        for key, value in MANUAL.items():
            lines.append("{}: {}".format(key, value["answer"]))
            lines.append("  {}".format(value["prompt"]))
    else:
        lines.append("No manual answers recorded.")
    lines.append("")

    lines.append("COMMAND RESULTS")
    for command in COMMANDS:
        lines.append("")
        lines.append("[{}] exit={} duration={}s".format(command["label"], command["exitCode"], command["durationSeconds"]))
        lines.append("$ " + command["command"])
        if command["stdout"].strip():
            lines.append("stdout:")
            lines.append(command["stdout"].rstrip())
        if command["stderr"].strip():
            lines.append("stderr:")
            lines.append(command["stderr"].rstrip())
    lines.append("")

    if NOTES:
        lines.append("NOTES")
        for note in NOTES:
            lines.append("- " + note)
        lines.append("")

    # Keep the final matrix at the absolute end so it is easy to find when the
    # user pastes this report back for patching.
    lines.append("FINAL VERIFICATION MATRIX")
    order = [
        "ENVIRONMENT",
        "PORTABLE TESTS",
        "CATALOG VALIDATION",
        "XCODEGEN",
        "XCODE BUILD",
        "XCODE TESTS",
        "APP BUNDLE CREATED",
        "APP LAUNCH",
        "REAL APP SCAN",
        "HOMEBREW WIRING",
        "MIGRATION PREVIEW",
        "MIGRATION BACKUP",
        "MIGRATION ROLLBACK",
    ]
    for key in order:
        lines.append("{} {}".format(key, matrix.get(key, NOT_VERIFIED)))
    return "\n".join(lines) + "\n"


def write_reports(environment, matrix, prerequisites):
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    payload = {
        "schemaVersion": 1,
        "project": "LibreReplace",
        "generatedAtUTC": environment["generatedAtUTC"],
        "environment": environment,
        "matrix": matrix,
        "prerequisites": prerequisites,
        "probes": PROBES,
        "resourceChecks": RESOURCE_CHECKS,
        "manualChecks": MANUAL,
        "commands": COMMANDS,
        "notes": NOTES,
        "signing": DEFERRED,
        "notarization": DEFERRED,
        "privacy": {
            "installedApplicationNamesRecorded": False,
            "installedBundleIdentifiersRecorded": False,
            "privateApplicationDataReadByHarness": False,
            "realEditorSettingsTouchedByMigrationTest": False,
            "thirdPartyApplicationsInstalled": False,
        },
    }
    TXT_REPORT.write_text(build_text_report(environment, matrix, prerequisites), encoding="utf-8")
    JSON_REPORT.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description="Verify LibreReplace locally on macOS.")
    parser.add_argument("--non-interactive", action="store_true", help="Do not ask GUI confirmation questions.")
    parser.add_argument("--no-launch", action="store_true", help="Build and verify the app bundle but do not open it.")
    args = parser.parse_args()

    if Path.cwd().resolve() != ROOT:
        print("Running from repository root: {}".format(ROOT))
        os.chdir(str(ROOT))

    environment = {
        "generatedAtUTC": datetime.now(timezone.utc).isoformat(),
        "macOS": platform.mac_ver()[0] if platform.system() == "Darwin" else "not macOS ({})".format(platform.system()),
        "python": platform.python_version(),
        "architecture": platform.machine(),
        "xcodeSelectPath": "not detected",
        "commandLineTools": "not detected",
        "fullXcode": "not detected",
        "developerDirUsed": "not detected",
        "swift": "not detected",
        "xcodegen": "not detected",
        "homebrew": "not detected",
        "make": shutil.which("make") or "not found",
    }
    matrix = {
        "ENVIRONMENT": NOT_VERIFIED,
        "PORTABLE TESTS": NOT_VERIFIED,
        "CATALOG VALIDATION": NOT_VERIFIED,
        "XCODEGEN": NOT_VERIFIED,
        "XCODE BUILD": NOT_VERIFIED,
        "XCODE TESTS": NOT_VERIFIED,
        "APP BUNDLE CREATED": NOT_VERIFIED,
        "APP LAUNCH": NOT_VERIFIED,
        "REAL APP SCAN": NOT_VERIFIED,
        "HOMEBREW WIRING": NOT_VERIFIED,
        "MIGRATION PREVIEW": NOT_VERIFIED,
        "MIGRATION BACKUP": NOT_VERIFIED,
        "MIGRATION ROLLBACK": NOT_VERIFIED,
    }
    prerequisites = []
    base_env = os.environ.copy()
    developer_env = base_env.copy()

    try:
        is_mac = platform.system() == "Darwin"
        mac_version_ok = is_mac and version_tuple(platform.mac_ver()[0]) >= (14, 0)
        python_ok = sys.version_info >= (3, 9)
        make_ok = shutil.which("make") is not None

        selected_path = None
        if is_mac:
            code, stdout, _ = run_command("xcode-select path", ["/usr/bin/xcode-select", "-p"], timeout=30, quiet=True)
            if code == 0:
                selected_path = stdout.strip()
                environment["xcodeSelectPath"] = sanitize(selected_path)

        full_xcode_dir = None
        full_xcode_version = None
        if is_mac:
            for index, candidate in enumerate(xcode_developer_candidates(selected_path), start=1):
                candidate_env = base_env.copy()
                candidate_env["DEVELOPER_DIR"] = str(candidate)
                code, stdout, _ = run_command("Xcode version candidate {}".format(index), ["/usr/bin/xcodebuild", "-version"], env=candidate_env, timeout=30, quiet=True)
                if code == 0 and "Xcode" in stdout:
                    full_xcode_dir = candidate
                    full_xcode_version = stdout.strip()
                    developer_env = candidate_env
                    break
        if full_xcode_dir:
            environment["developerDirUsed"] = sanitize(str(full_xcode_dir))
            environment["fullXcode"] = full_xcode_version.replace("\n", "; ")
        elif is_mac:
            environment["fullXcode"] = "not found"
            prerequisites.append("Install full Xcode (Command Line Tools alone are insufficient for the SwiftUI app build), then rerun: python3 dev.py")

        if is_mac:
            code, stdout, _ = run_command("Command Line Tools probe", ["/usr/bin/xcrun", "--find", "clang"], env=developer_env, timeout=30, quiet=True)
            environment["commandLineTools"] = sanitize(stdout.strip()) if code == 0 else "not available"

        swift_path = shutil.which("swift")
        swift_ok = False
        if swift_path:
            code, stdout, stderr = run_command("Swift version", [swift_path, "--version"], env=developer_env, timeout=30, quiet=True)
            if code == 0:
                swift_ok = True
                environment["swift"] = (stdout or stderr).strip().splitlines()[0]
        else:
            environment["swift"] = "not found"
            prerequisites.append("Swift was not found. Install/repair Xcode Command Line Tools or full Xcode, then rerun: python3 dev.py")

        xcodegen_path = shutil.which("xcodegen")
        if not xcodegen_path:
            for candidate in ("/opt/homebrew/bin/xcodegen", "/usr/local/bin/xcodegen"):
                if Path(candidate).is_file() and os.access(candidate, os.X_OK):
                    xcodegen_path = candidate
                    break
        if xcodegen_path:
            code, stdout, stderr = run_command("XcodeGen version", [xcodegen_path, "--version"], env=developer_env, timeout=30, quiet=True)
            environment["xcodegen"] = (stdout or stderr).strip().splitlines()[0] if code == 0 else "present but failed"
        else:
            environment["xcodegen"] = "not found"

        brew_path = shutil.which("brew")
        if not brew_path:
            for candidate in ("/opt/homebrew/bin/brew", "/usr/local/bin/brew"):
                if Path(candidate).is_file() and os.access(candidate, os.X_OK):
                    brew_path = candidate
                    break
        if brew_path:
            code, stdout, stderr = run_command("Homebrew version", [brew_path, "--version"], env=developer_env, timeout=60, quiet=True)
            environment["homebrew"] = (stdout or stderr).strip().splitlines()[0] if code == 0 else "present but failed"
        else:
            environment["homebrew"] = "not found (optional for core validation)"

        if not xcodegen_path:
            if brew_path:
                prerequisites.append("XcodeGen is required for the macOS project: brew install xcodegen ; then rerun: python3 dev.py")
            else:
                prerequisites.append("XcodeGen is required. Install XcodeGen (Homebrew: brew install xcodegen) and rerun: python3 dev.py")

        environment_ok = is_mac and mac_version_ok and python_ok and make_ok and swift_ok and full_xcode_dir is not None
        matrix["ENVIRONMENT"] = status_from_bool(environment_ok)
        if is_mac and not mac_version_ok:
            prerequisites.append("LibreReplace targets macOS 14 or newer; this Mac reports {}.".format(platform.mac_ver()[0]))
        if not python_ok:
            prerequisites.append("Python 3.9 or newer is required; this interpreter is {}.".format(platform.python_version()))
        if not make_ok:
            prerequisites.append("The 'make' command is required and was not found.")

        # Portable validation. First compile the Swift core as a dependency gate.
        # If that gate fails, Swift-backed validators/probes are NOT VERIFIED
        # rather than being reported as separate product failures caused by the
        # same compiler error. The Python catalog validator remains independent.
        if make_ok and swift_ok:
            core_code, _, _ = run_command("Swift core compile gate", [swift_path, "build", "--target", "LibreReplaceCore"], env=developer_env, timeout=1200)
            core_compiles = core_code == 0

            py_code, _, _ = run_command("Python catalog validator", [sys.executable, "Scripts/validate_catalog.py"], env=developer_env, timeout=180)

            if core_compiles:
                code, _, _ = run_command("Portable repository checks", ["make", "check"], env=developer_env, timeout=1200)
                matrix["PORTABLE TESTS"] = PASS if code == 0 else FAIL

                swift_val_code, _, _ = run_command("Swift catalog validator", [swift_path, "run", "libreplace", "validate", "Catalog/catalog.json"], env=developer_env, timeout=600)
                matrix["CATALOG VALIDATION"] = PASS if py_code == 0 and swift_val_code == 0 else FAIL

                # Explicit standalone Swift test invocation keeps an unambiguous test
                # exit code in the report even though make check already includes it.
                test_code, _, _ = run_command("Swift package tests", [swift_path, "test"], env=developer_env, timeout=1200)
                if test_code != 0:
                    matrix["PORTABLE TESTS"] = FAIL

                mig_code, mig_stdout, _ = run_command("Temporary migration self-test", [swift_path, "run", "libreplace", "migration-selftest"], env=developer_env, timeout=600)
                mig = parse_json_stdout(mig_stdout)
                if isinstance(mig, dict):
                    PROBES["migrationFixture"] = mig
                    matrix["MIGRATION PREVIEW"] = PASS if mig_code == 0 and mig.get("preview") is True else FAIL
                    matrix["MIGRATION BACKUP"] = PASS if mig_code == 0 and mig.get("backup") is True else FAIL
                    matrix["MIGRATION ROLLBACK"] = PASS if mig_code == 0 and mig.get("rollback") is True and mig.get("rollbackRestoredOriginalBytes") is True else FAIL
                else:
                    matrix["MIGRATION PREVIEW"] = FAIL
                    matrix["MIGRATION BACKUP"] = FAIL
                    matrix["MIGRATION ROLLBACK"] = FAIL

                install_code, install_stdout, _ = run_command("Safe installation wiring self-test", [swift_path, "run", "libreplace", "install-smoke", "Catalog/catalog.json"], env=developer_env, timeout=600)
                install_probe = parse_json_stdout(install_stdout)
                if isinstance(install_probe, dict):
                    PROBES["installationWiring"] = install_probe
                    if install_code != 0 or install_probe.get("commandGenerationPass") is not True or install_probe.get("homebrewProbe") == FAIL:
                        matrix["HOMEBREW WIRING"] = FAIL
                    elif install_probe.get("homebrewAvailable") is True and install_probe.get("homebrewProbe") == PASS:
                        # Final PASS is assigned after the GUI target also compiles.
                        matrix["HOMEBREW WIRING"] = NOT_VERIFIED
                    else:
                        matrix["HOMEBREW WIRING"] = NOT_VERIFIED
                else:
                    matrix["HOMEBREW WIRING"] = FAIL

                if is_mac:
                    scan_code, scan_stdout, _ = run_command("Real Mac metadata scanner smoke test", [swift_path, "run", "libreplace", "scan-smoke", "Catalog/catalog.json"], env=developer_env, timeout=600)
                    scan_probe = parse_json_stdout(scan_stdout)
                    if isinstance(scan_probe, dict):
                        PROBES["realMacScanner"] = scan_probe
                    matrix["REAL APP SCAN"] = PASS if scan_code == 0 and isinstance(scan_probe, dict) and scan_probe.get("pass") is True else FAIL
            else:
                matrix["PORTABLE TESTS"] = FAIL
                matrix["CATALOG VALIDATION"] = FAIL if py_code != 0 else NOT_VERIFIED
                NOTES.append("Swift core compilation failed. Swift-backed catalog validation, migration, installation, and real-Mac scanner probes were skipped to avoid reporting cascade failures as independent bugs.")
        else:
            NOTES.append("Portable checks could not run because make or Swift is unavailable.")

        # Xcode generation/build/test phase.
        PROBES["nativeBuildLocation"] = {
            "derivedDataPath": sanitize(DERIVED_DATA),
            "outsideRepository": not str(DERIVED_DATA).startswith(str(ROOT)),
            "outsideUserHome": not str(DERIVED_DATA).startswith(str(Path.home())),
            "purpose": "Keep XCTest products outside macOS TCC-protected Downloads/Desktop/Documents paths.",
        }
        generated = False
        if xcodegen_path:
            code, _, _ = run_command("Generate Xcode project", [xcodegen_path, "generate"], env=developer_env, timeout=180)
            generated = code == 0 and (ROOT / "LibreReplace.xcodeproj").is_dir()
            matrix["XCODEGEN"] = PASS if generated else FAIL

            # Xcode 27 requires embedded framework bundles to contain a valid
            # Info.plist. Verify the generated target still carries the
            # source-of-truth setting rather than relying only on project.yml.
            if generated and is_mac and full_xcode_dir:
                settings_code, settings_stdout, _ = run_command(
                    "Inspect generated LibreReplaceCore build settings",
                    [
                        "/usr/bin/xcodebuild",
                        "-project", "LibreReplace.xcodeproj",
                        "-target", "LibreReplaceCore",
                        "-configuration", "Debug",
                        "-showBuildSettings",
                    ],
                    env=developer_env,
                    timeout=180,
                    quiet=True,
                )
                setting_names = (
                    "GENERATE_INFOPLIST_FILE",
                    "PRODUCT_BUNDLE_IDENTIFIER",
                    "WRAPPER_EXTENSION",
                    "MACH_O_TYPE",
                )
                generated_settings = parse_build_settings(settings_stdout, setting_names) if settings_code == 0 else {}
                generated_settings["pass"] = (
                    settings_code == 0
                    and generated_settings.get("GENERATE_INFOPLIST_FILE") == "YES"
                    and generated_settings.get("PRODUCT_BUNDLE_IDENTIFIER") == "org.librereplace.core"
                )
                PROBES["generatedCoreFrameworkSettings"] = generated_settings
                if generated_settings["pass"] is not True:
                    matrix["XCODEGEN"] = FAIL
                    NOTES.append("Generated LibreReplaceCore settings did not preserve GENERATE_INFOPLIST_FILE=YES and the expected bundle identifier.")

                test_settings_code, test_settings_stdout, _ = run_command(
                    "Inspect generated LibreReplaceCoreTests build settings",
                    [
                        "/usr/bin/xcodebuild",
                        "-project", "LibreReplace.xcodeproj",
                        "-target", "LibreReplaceCoreTests",
                        "-configuration", "Debug",
                        "-showBuildSettings",
                    ],
                    env=developer_env,
                    timeout=180,
                    quiet=True,
                )
                test_setting_names = (
                    "GENERATE_INFOPLIST_FILE",
                    "PRODUCT_BUNDLE_IDENTIFIER",
                    "PRODUCT_TYPE",
                    "PRODUCT_NAME",
                    "EXECUTABLE_NAME",
                    "EXECUTABLE_PATH",
                    "FULL_PRODUCT_NAME",
                    "WRAPPER_EXTENSION",
                    "MACH_O_TYPE",
                    "SKIP_INSTALL",
                    "BUNDLE_LOADER",
                    "TEST_HOST",
                )
                test_settings = parse_build_settings(test_settings_stdout, test_setting_names) if test_settings_code == 0 else {}
                test_settings["pass"] = (
                    test_settings_code == 0
                    and test_settings.get("GENERATE_INFOPLIST_FILE") == "YES"
                    and test_settings.get("PRODUCT_BUNDLE_IDENTIFIER") == "org.librereplace.coretests"
                    and test_settings.get("PRODUCT_TYPE") == "com.apple.product-type.bundle.unit-test"
                    and test_settings.get("PRODUCT_NAME") == "LibreReplaceCoreTests"
                    and test_settings.get("EXECUTABLE_NAME") == "LibreReplaceCoreTests"
                    and test_settings.get("WRAPPER_EXTENSION") == "xctest"
                    and test_settings.get("MACH_O_TYPE") == "mh_bundle"
                )
                PROBES["generatedCoreTestsSettings"] = test_settings
                scheme_path = ROOT / "LibreReplace.xcodeproj" / "xcshareddata" / "xcschemes" / "LibreReplace.xcscheme"
                scheme_text = scheme_path.read_text(encoding="utf-8", errors="replace") if scheme_path.is_file() else ""
                PROBES["xcodeTestScheme"] = {
                    "schemeExists": scheme_path.is_file(),
                    "referencesLibreReplaceCoreTests": "LibreReplaceCoreTests" in scheme_text,
                    "pass": scheme_path.is_file() and "LibreReplaceCoreTests" in scheme_text,
                }
                if test_settings["pass"] is not True:
                    matrix["XCODEGEN"] = FAIL
                    NOTES.append("Generated LibreReplaceCoreTests settings do not resolve to an executable macOS XCTest bundle with generated Info.plist metadata.")
                if PROBES["xcodeTestScheme"]["pass"] is not True:
                    matrix["XCODEGEN"] = FAIL
                    NOTES.append("Generated LibreReplace scheme does not reference LibreReplaceCoreTests in its test action.")
        else:
            matrix["XCODEGEN"] = FAIL

        build_attempted = False
        build_passed = False
        test_attempted = False
        if is_mac and full_xcode_dir and generated:
            # Start native validation from a clean derived-data tree so stale
            # products cannot make bundle/resource checks pass accidentally.
            if DERIVED_DATA.exists():
                shutil.rmtree(DERIVED_DATA)

            build_attempted = True
            build_cmd = [
                "/usr/bin/xcodebuild", "-quiet",
                "-project", "LibreReplace.xcodeproj",
                "-scheme", "LibreReplace",
                "-configuration", "Debug",
                "-destination", "platform=macOS",
                "-derivedDataPath", str(DERIVED_DATA),
                "CODE_SIGNING_ALLOWED=NO",
                "CODE_SIGNING_REQUIRED=NO",
                "build",
            ]
            code, _, _ = run_command("Xcode Debug build/type-check", build_cmd, env=developer_env, timeout=1800)
            build_passed = code == 0
            matrix["XCODE BUILD"] = PASS if build_passed else FAIL

            test_attempted = True
            test_build_cmd = [
                "/usr/bin/xcodebuild",
                "-project", "LibreReplace.xcodeproj",
                "-scheme", "LibreReplace",
                "-configuration", "Debug",
                "-destination", "platform=macOS",
                "-derivedDataPath", str(DERIVED_DATA),
                "CODE_SIGNING_ALLOWED=NO",
                "CODE_SIGNING_REQUIRED=NO",
                "build-for-testing",
            ]
            test_build_code, test_build_stdout, test_build_stderr = run_command(
                "Xcode build-for-testing", test_build_cmd, env=developer_env, timeout=1800
            )
            test_bundle_probe = test_bundle_checks(TEST_BUNDLE)
            PROBES["xcodeTestBundle"] = test_bundle_probe

            # build-for-testing is the source of truth for test execution. Xcode
            # emits an .xctestrun manifest that records the exact products it
            # intends XCTest to load. Validate and execute that manifest rather
            # than asking a second project/scheme planning pass to rediscover a
            # prebuilt test bundle. This remains native XCTest execution.
            xctestrun_path = find_xctestrun() if test_build_code == 0 else None
            xctestrun_probe = xctestrun_checks(xctestrun_path)
            PROBES["xcodeTestRun"] = xctestrun_probe

            # Record whether the fresh build-for-testing actually compiled and
            # linked the test target. The on-disk executable is the decisive
            # check; these log hints make failures easier to diagnose.
            build_log = test_build_stdout + "\n" + test_build_stderr
            PROBES["xcodeTestBuildPhases"] = {
                "testSourcePresentInGeneratedProject": (ROOT / "LibreReplace.xcodeproj" / "project.pbxproj").is_file()
                    and "CoreTests.swift" in (ROOT / "LibreReplace.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8", errors="replace"),
                "compilePhaseObserved": bool(re.search(r"(SwiftCompile|CompileSwift).*LibreReplaceCoreTests|CoreTests\.swift", build_log)),
                "linkPhaseObserved": bool(re.search(r"(^|\n).*Ld .*LibreReplaceCoreTests", build_log)),
                "testExecutableProduced": test_bundle_probe.get("testExecutableExists") is True,
            }

            if (
                test_build_code == 0
                and test_bundle_probe.get("pass") is True
                and xctestrun_probe.get("pass") is True
                and xctestrun_path is not None
            ):
                # Bind XCTest execution to the architecture that Xcode encoded
                # in the generated .xctestrun artifact. With Xcode 27.1, a bare
                # ``platform=macOS`` xctestrun invocation may otherwise select
                # arm64e first even though build-for-testing produced arm64.
                test_destination = xctestrun_probe.get("testDestination") or "platform=macOS"
                test_cmd = [
                    "/usr/bin/xcodebuild", "-quiet",
                    "test-without-building",
                    "-xctestrun", str(xctestrun_path),
                    "-destination", test_destination,
                ]
                test_code, _, _ = run_command("Xcode tests", test_cmd, env=developer_env, timeout=1800)
                matrix["XCODE TESTS"] = PASS if test_code == 0 else FAIL

                # Failure-only diagnostic: execute the already-built generated
                # Xcode unit-test bundle with Apple's xctest host directly. This
                # never upgrades XCODE TESTS to PASS; it only distinguishes a
                # malformed test product from an xcodebuild/testmanager issue.
                if test_code != 0 and test_bundle_probe.get("pass") is True:
                    xctest_candidates = [
                        Path(full_xcode_dir) / "Platforms" / "MacOSX.platform" / "Developer" / "Library" / "Xcode" / "Agents" / "xctest",
                        Path("/usr/bin/xctest"),
                    ]
                    xctest_host = next((candidate for candidate in xctest_candidates if candidate.is_file()), None)
                    if xctest_host:
                        direct_env = dict(developer_env)
                        products_debug = DERIVED_DATA / "Build" / "Products" / "Debug"
                        existing_framework_path = direct_env.get("DYLD_FRAMEWORK_PATH", "")
                        direct_env["DYLD_FRAMEWORK_PATH"] = str(products_debug) + ((":" + existing_framework_path) if existing_framework_path else "")
                        direct_code, direct_stdout, direct_stderr = run_command(
                            "Direct XCTest diagnostic (matrix unaffected)",
                            [str(xctest_host), str(TEST_BUNDLE)],
                            env=direct_env,
                            timeout=600,
                        )
                        PROBES["directXCTestDiagnostic"] = {
                            "pass": direct_code == 0,
                            "host": sanitize(xctest_host),
                            "testBundle": sanitize(TEST_BUNDLE),
                            "matrixUnaffected": True,
                        }
                    else:
                        PROBES["directXCTestDiagnostic"] = {
                            "pass": None,
                            "host": None,
                            "testBundle": sanitize(TEST_BUNDLE),
                            "matrixUnaffected": True,
                            "note": "No xctest host executable was found for the diagnostic.",
                        }
            else:
                matrix["XCODE TESTS"] = FAIL
                if test_build_code != 0:
                    NOTES.append("Xcode build-for-testing failed before XCTest execution.")
                elif test_bundle_probe.get("pass") is not True:
                    NOTES.append("Xcode produced LibreReplaceCoreTests.xctest without the expected executable/Info.plist metadata; XCTest execution was skipped so the packaging failure remains explicit.")
                else:
                    NOTES.append("Xcode build-for-testing did not produce an .xctestrun manifest that references the verified LibreReplaceCoreTests.xctest product.")
        else:
            if not is_mac:
                NOTES.append("Xcode build/tests require macOS.")
            elif not full_xcode_dir:
                NOTES.append("Xcode build/tests not run because full Xcode was not found.")
            elif not generated:
                NOTES.append("Xcode build/tests not run because project generation did not succeed.")

        RESOURCE_CHECKS.update(resource_checks(APP_BUNDLE))
        bundle_ok = all([
            RESOURCE_CHECKS.get("appBundleExists"),
            RESOURCE_CHECKS.get("executableExists"),
            RESOURCE_CHECKS.get("infoPlistReadable"),
            RESOURCE_CHECKS.get("bundleIdentifierCorrect"),
            RESOURCE_CHECKS.get("coreFrameworkExists"),
            RESOURCE_CHECKS.get("coreFrameworkInfoPlistReadable"),
            RESOURCE_CHECKS.get("coreFrameworkBundleIdentifierCorrect"),
            RESOURCE_CHECKS.get("bundledCatalogExists"),
            RESOURCE_CHECKS.get("bundledCatalogJSONReadable"),
            RESOURCE_CHECKS.get("bundledCatalogMatchesSource"),
        ])
        if build_attempted:
            matrix["APP BUNDLE CREATED"] = PASS if build_passed and bundle_ok else FAIL

        bundled_catalog = APP_BUNDLE / "Contents" / "Resources" / "catalog.json"
        if bundled_catalog.is_file():
            py_bundle_code, _, _ = run_command("Validate catalog inside built app", [sys.executable, "Scripts/validate_catalog.py", str(bundled_catalog)], env=developer_env, timeout=180)
            swift_bundle_code, _, _ = run_command("Swift-validate catalog inside built app", [swift_path, "run", "libreplace", "validate", str(bundled_catalog)], env=developer_env, timeout=600)
            RESOURCE_CHECKS["bundledCatalogValidatorsPass"] = py_bundle_code == 0 and swift_bundle_code == 0
            if not RESOURCE_CHECKS["bundledCatalogValidatorsPass"]:
                matrix["APP BUNDLE CREATED"] = FAIL

        # The installation smoke test uses the same HomebrewExecutor as the GUI.
        # Only call this PASS when the harmless brew probe passed AND the GUI target
        # compiled, proving the shared path is linked into the application.
        install_probe = PROBES.get("installationWiring")
        if isinstance(install_probe, dict):
            if install_probe.get("homebrewProbe") == FAIL or install_probe.get("commandGenerationPass") is not True:
                matrix["HOMEBREW WIRING"] = FAIL
            elif install_probe.get("homebrewAvailable") is True and install_probe.get("homebrewProbe") == PASS and matrix["XCODE BUILD"] == PASS:
                matrix["HOMEBREW WIRING"] = PASS
            elif install_probe.get("homebrewAvailable") is False:
                matrix["HOMEBREW WIRING"] = NOT_VERIFIED

        # Launch only after a verified bundle exists. `open` success is not treated
        # as proof that a SwiftUI window rendered; that requires the user's answer.
        if matrix["APP BUNDLE CREATED"] == PASS and not args.no_launch:
            open_code, _, _ = run_command("Launch Debug app", ["/usr/bin/open", "-n", str(APP_BUNDLE)], env=developer_env, timeout=60)
            if open_code != 0:
                matrix["APP LAUNCH"] = FAIL
            elif args.non_interactive or not sys.stdin.isatty():
                matrix["APP LAUNCH"] = NEEDS_MANUAL
            else:
                print("\nLibreReplace was handed to macOS with `open -n`. No install or migration action has been triggered.")
                launch_answer = ask("MANUAL CHECK 1", "Did the LibreReplace main window load without crashing?")
                scan_answer = ask("MANUAL CHECK 2", "Did the app finish its installed-application scan and show its normal summary/detected-app UI?")
                privacy_answer = ask("MANUAL CHECK 3", "Did LibreReplace avoid asking for Documents/Desktop/Keychain or other unrelated private-data access?")
                matrix["APP LAUNCH"] = PASS if launch_answer == "yes" else (FAIL if launch_answer == "no" else NEEDS_MANUAL)
                if scan_answer == "no":
                    matrix["REAL APP SCAN"] = FAIL
                if privacy_answer == "no":
                    NOTES.append("Manual privacy check failed: the app requested unrelated private-data access. Investigate before release.")
        elif args.no_launch and matrix["APP BUNDLE CREATED"] == PASS:
            matrix["APP LAUNCH"] = NEEDS_MANUAL
            NOTES.append("App launch was skipped by --no-launch.")

        # Explain missing optional Homebrew without converting it into a product failure.
        if not brew_path:
            NOTES.append("Homebrew is optional for scanning/comparison, but Homebrew-backed installation execution remains NOT VERIFIED on this Mac until Homebrew is available. No software was installed by the harness.")

    except KeyboardInterrupt:
        NOTES.append("Verification interrupted by user. Completed results were preserved.")
    except Exception as exc:
        NOTES.append("Harness exception: {}: {}".format(type(exc).__name__, sanitize(exc)))
        print("\nHarness error: {}".format(exc), file=sys.stderr)
    finally:
        write_reports(environment, matrix, prerequisites)
        print("\nReports written:")
        print("  {}".format(TXT_REPORT))
        print("  {}".format(JSON_REPORT))
        print("\nFINAL VERIFICATION MATRIX")
        for key in (
            "ENVIRONMENT", "PORTABLE TESTS", "CATALOG VALIDATION", "XCODEGEN", "XCODE BUILD", "XCODE TESTS",
            "APP BUNDLE CREATED", "APP LAUNCH", "REAL APP SCAN", "HOMEBREW WIRING", "MIGRATION PREVIEW",
            "MIGRATION BACKUP", "MIGRATION ROLLBACK"
        ):
            print("{} {}".format(key, matrix.get(key, NOT_VERIFIED)))

    # The reports, not this aggregate exit code, are the source of truth. Return 1
    # when an applicable automated acceptance check failed; manual/deferred/not-
    # verified states do not masquerade as success but also do not prevent report creation.
    automated_failures = [
        key for key, value in matrix.items()
        if value == FAIL and key not in ("APP LAUNCH", "HOMEBREW WIRING")
    ]
    return 1 if automated_failures else 0


if __name__ == "__main__":
    sys.exit(main())
