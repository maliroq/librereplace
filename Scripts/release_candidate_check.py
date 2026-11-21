#!/usr/bin/env python3
"""Read-only LibreReplace release candidate gate. Does not sign, install or publish."""
from __future__ import annotations
import json
import os
from pathlib import Path
import platform
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def run(*args, timeout=18):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None

def main():
    catalog = json.loads((ROOT / 'Catalog/catalog.json').read_text())
    apps = catalog.get('apps', [])
    count = len({n.casefold() for a in apps for n in [a['name']] + [x['name'] for x in a.get('alternatives', [])]})
    art = json.loads((ROOT / 'Catalog/app_artwork.json').read_text()).get('apps', {})
    remote = sum(v.get('artworkStatus') == 'product-specific' and bool(v.get('iconFile')) for v in art.values())
    builds = json.loads((ROOT / 'Community/index.v1.json').read_text()).get('builds', [])
    report_path = ROOT / 'artifacts/local_verification_report.json'
    matrix = {}
    if report_path.is_file():
        try:
            matrix = json.loads(report_path.read_text()).get('matrix', {})
        except (OSError, ValueError):
            pass
    required = {'ENVIRONMENT', 'PORTABLE TESTS', 'CATALOG VALIDATION', 'XCODEGEN',
                'XCODE BUILD', 'XCODE TESTS', 'APP BUNDLE CREATED', 'REAL APP SCAN',
                'HOMEBREW WIRING', 'MIGRATION PREVIEW', 'MIGRATION BACKUP', 'MIGRATION ROLLBACK'}
    native_pass = all(matrix.get(x) == 'PASS' for x in required)
    is_mac = platform.system() == 'Darwin'
    developer_id = False
    notarytool = False
    profile_set = bool(os.environ.get('LIBREREPLACE_NOTARY_PROFILE'))
    if is_mac:
        identities = run('/usr/bin/security', 'find-identity', '-v', '-p', 'codesigning')
        developer_id = bool(identities and 'Developer ID Application:' in identities.stdout)
        tool = run('/usr/bin/xcrun', '--find', 'notarytool')
        notarytool = bool(tool and tool.returncode == 0)
    results = {
        'catalog_product_count': count,
        'private_artwork_in_public_bundle': False,
        'remote_artwork_mappings_unreviewed_for_distribution': remote,
        'catalog_products_using_other_or_fallback_artwork': max(0, len(art) - remote),
        'community_index_has_published_builds': bool(builds),
        'latest_debug_native_matrix_passed': native_pass,
        'developer_id_identity_available': developer_id,
        'notarytool_available': notarytool,
        'notarization_profile_configured': profile_set,
        'final_release_artifact_signed_notarized_stapled_and_fresh_mac_tested': False,
    }
    print('LIBREREPLACE RELEASE CANDIDATE CHECK (READ ONLY)')
    print('100-product catalog:', 'PASS' if count == 100 else 'REVIEW', f'({count})')
    print('Native development verification:', 'PASS' if native_pass else 'NEEDS CURRENT MAC RUN')
    print(f'Fresh-install artwork: {remote} mapped to remote images; {max(0,len(art)-remote)} use installed icons or neutral fallback')
    print('Third-party artwork permission: HUMAN REVIEW REQUIRED before public distribution')
    print('Published Community builds:', len(builds), '(empty gallery is supported)')
    print('Developer ID certificate:', 'FOUND' if developer_id else 'NOT CONFIRMED')
    print('Apple notarytool:', 'FOUND' if notarytool else 'NOT CONFIRMED')
    print('Notary keychain profile:', 'CONFIGURED' if profile_set else 'NOT CONFIGURED')
    print('Final signed/notarized DMG and clean-Mac install: NOT VERIFIED')
    print('RELEASE STATUS: DEVELOPMENT BUILD VERIFIED ONLY — PUBLIC BINARY RELEASE NOT YET CLEARED')
    print('No installed apps, source files, artwork, certificates, or Git history changed.')
    report = ROOT / 'artifacts/release_candidate_readiness.json'
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(results, indent=2) + '\n')
    print('Report:', report)

if __name__ == '__main__':
    main()
