#!/usr/bin/env python3
import json, math, pathlib, re, sys
from datetime import date, datetime
from urllib.parse import urlparse

ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_CATALOG = ROOT / "Catalog" / "catalog.json"


def valid_https_url(value):
    try:
        parsed = urlparse(value)
    except Exception:
        return False
    return parsed.scheme == "https" and bool(parsed.hostname) and parsed.username is None and parsed.password is None


def valid_app_store_url(value):
    try:
        parsed = urlparse(value)
    except Exception:
        return False
    if parsed.username is not None or parsed.password is not None:
        return False
    return parsed.scheme == "macappstore" or valid_https_url(value)


def normalize_matcher(value):
    return re.sub(r"[^a-z0-9]", "", value.lower())


def fail(msg):
    print(f"ERROR: {msg}")
    return 1


def main():
    catalog = pathlib.Path(sys.argv[1]).expanduser().resolve() if len(sys.argv) > 1 else DEFAULT_CATALOG
    if len(sys.argv) > 2:
        print("Usage: python3 Scripts/validate_catalog.py [catalog.json]", file=sys.stderr)
        return 2
    try:
        data = json.loads(catalog.read_text())
    except Exception as exc:
        return fail(f"cannot parse {catalog}: {exc}")
    apps = data.get("apps", [])
    errors = []
    if data.get("schemaVersion") != "1.0":
        errors.append(f"unsupported schemaVersion {data.get('schemaVersion')!r}")
    today = date.today()
    try:
        generated_at = datetime.strptime(data["generatedAt"], "%Y-%m-%d").date()
        if generated_at > today:
            errors.append("generatedAt cannot be in the future")
    except Exception:
        errors.append("generatedAt must be a valid YYYY-MM-DD date")
    if not 20 <= len(apps) <= 40:
        errors.append(f"expected 20-40 catalog apps, found {len(apps)}")
    ids, bundles = set(), set()
    name_matchers = {}
    for app in apps:
        aid = app.get("id", "")
        if not aid or aid in ids: errors.append(f"duplicate/empty id {aid!r}")
        ids.add(aid)
        if not app.get("bundleIdentifiers") and not app.get("nameAliases"): errors.append(f"{aid}: no matchers")
        for matcher in [app.get("name", ""), *app.get("nameAliases", [])]:
            normalized = normalize_matcher(matcher)
            if not normalized:
                errors.append(f"{aid}: empty normalized name matcher")
            elif normalized in name_matchers and name_matchers[normalized] != aid:
                errors.append(f"ambiguous name matcher {matcher!r}: used by {name_matchers[normalized]} and {aid}")
            else:
                name_matchers[normalized] = aid
        for bundle in app.get("bundleIdentifiers", []):
            b = bundle.lower()
            if b in bundles: errors.append(f"duplicate bundle id {bundle}")
            bundles.add(b)
        cap_list = app.get("capabilities", [])
        caps = set()
        for cap in cap_list:
            cid = cap.get("id", "")
            if not cid or cid in caps: errors.append(f"{aid}: duplicate/empty capability id {cid!r}")
            caps.add(cid)
            if not cap.get("label"): errors.append(f"{aid}: capability {cid!r} missing label")
            weight = cap.get("weight")
            if isinstance(weight, bool) or not isinstance(weight, (int, float)) or not math.isfinite(weight) or weight <= 0:
                errors.append(f"{aid}: capability {cid!r} must have finite positive numeric weight")
        if not caps: errors.append(f"{aid}: no capabilities")
        if not app.get("name"): errors.append(f"{aid}: name is required")
        if not app.get("vendor"): errors.append(f"{aid}: vendor is required")
        if not app.get("alternatives"): errors.append(f"{aid}: no alternatives")
        if not app.get("evidence"): errors.append(f"{aid}: no source-app evidence")
        policy = app.get("policy", {})
        strong = policy.get("strongThreshold")
        partial = policy.get("partialThreshold")
        numeric = lambda value: isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)
        if not numeric(strong) or not numeric(partial) or not (0 <= partial <= strong <= 1):
            errors.append(f"{aid}: invalid recommendation thresholds")
        alt_ids = set()
        for alt in app.get("alternatives", []):
            alt_id = alt.get("id", "")
            if not alt_id or alt_id in alt_ids: errors.append(f"{aid}: duplicate/empty alternative id {alt_id!r}")
            alt_ids.add(alt_id)
            if not alt.get("license"): errors.append(f"{aid}/{alt_id}: missing license")
            if not alt.get("evidence"): errors.append(f"{aid}/{alt_id}: no alternative evidence")
            support = alt.get("support", {})
            if set(support) != caps:
                errors.append(f"{aid}/{alt.get('id')}: support keys differ from capability ids")
            for field in ("homepageURL",):
                if not valid_https_url(alt.get(field, "")):
                    errors.append(f"{aid}/{alt.get('id')}: bad {field}")
            repo = alt.get("repositoryURL")
            if repo and not valid_https_url(repo):
                errors.append(f"{aid}/{alt.get('id')}: bad repositoryURL")
            install = alt.get("install", {})
            if install.get("kind", "").startswith("homebrew"):
                token = install.get("value", "")
                if not re.fullmatch(r"[A-Za-z0-9@+._/-]+", token) or ".." in token or token.startswith("/"):
                    errors.append(f"{aid}/{alt.get('id')}: unsafe brew token")
            elif install.get("kind") in ("githubRelease", "officialDownload") and not valid_https_url(install.get("value", "")):
                errors.append(f"{aid}/{alt.get('id')}: install URL must use credential-free https")
            elif install.get("kind") == "macAppStore" and not valid_app_store_url(install.get("value", "")):
                errors.append(f"{aid}/{alt.get('id')}: invalid Mac App Store URL")
            try:
                alt_last = datetime.strptime(alt["lastVerified"], "%Y-%m-%d").date()
                if alt_last > today: errors.append(f"{aid}/{alt.get('id')}: alternative lastVerified is in the future ({alt_last})")
                elif (today - alt_last).days > 180: errors.append(f"{aid}/{alt.get('id')}: alternative entry is stale ({alt_last})")
            except Exception:
                errors.append(f"{aid}/{alt.get('id')}: bad lastVerified")
        pricing_url = app.get("pricing", {}).get("sourceURL")
        if pricing_url and not valid_https_url(pricing_url): errors.append(f"{aid}: bad pricing source URL")
        for evidence in app.get("evidence", []) + [e for a in app.get("alternatives", []) for e in a.get("evidence", [])]:
            if not valid_https_url(evidence.get("url", "")):
                errors.append(f"{aid}: bad evidence URL")
            try:
                evidence_date = datetime.strptime(evidence["lastVerified"], "%Y-%m-%d").date()
                if evidence_date > today: errors.append(f"{aid}: evidence date is in the future ({evidence_date})")
                elif (today - evidence_date).days > 180: errors.append(f"{aid}: stale evidence ({evidence_date})")
            except Exception: errors.append(f"{aid}: bad evidence date")
        try:
            last = datetime.strptime(app["lastVerified"], "%Y-%m-%d").date()
            if last > today:
                errors.append(f"{aid}: lastVerified is in the future ({last})")
            elif (today - last).days > 180:
                errors.append(f"{aid}: catalog entry is stale ({last})")
        except Exception:
            errors.append(f"{aid}: bad lastVerified")
    if errors:
        print("Catalog validation failed:")
        for error in errors: print(" -", error)
        return 1
    print(f"Catalog validation OK: {len(apps)} apps, {len(bundles)} bundle IDs")
    return 0

if __name__ == "__main__":
    sys.exit(main())
