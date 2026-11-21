#!/usr/bin/env python3
"""Read-only audit of LibreReplace icon coverage and exact local approvals.

Runs on macOS or another Python 3 host. No downloads or modifications.
"""
import argparse
import hashlib
import json
import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APPROVED = Path.home() / 'Library/Application Support/LibreReplace/Approved Artwork'
PNG_MAGIC = b'\x89PNG\r\n\x1a\n'


def image_size(data):
    if len(data) < 24 or data[:8] != PNG_MAGIC:
        return None
    width, height = struct.unpack('>II', data[16:24])
    if not (1 <= width <= 16384 and 1 <= height <= 16384):
        return None
    return width, height


def inventory(root=ROOT, approved=APPROVED):
    records = json.loads((root / 'Catalog/app_artwork.json').read_text())['apps']
    approved_manifest = approved / 'manifest.json'
    try:
        local = json.loads(approved_manifest.read_text())
        if local.get('schemaVersion') != 1:
            local = {'apps': {}}
    except (OSError, ValueError):
        local = {'apps': {}}
    results = []
    used_hashes = {}
    for name, metadata in sorted(records.items()):
        status = 'missing'
        issue = None
        local_entry = local.get('apps', {}).get(name)
        if local_entry:
            filename = local_entry.get('filename', '')
            expected = local_entry.get('sha256', '')
            if not re.fullmatch(r'[a-z0-9][a-z0-9-]*\.png', filename) or not re.fullmatch(r'[0-9a-f]{64}', expected):
                issue = 'invalid approved artwork record'
            else:
                path = approved / filename
                try:
                    if path.is_symlink():
                        raise ValueError('symbolic link')
                    data = path.read_bytes()
                    if not (0 < len(data) < 12 * 1024 * 1024 and image_size(data)):
                        raise ValueError('invalid PNG')
                    actual = hashlib.sha256(data).hexdigest()
                    if actual != expected:
                        raise ValueError('checksum mismatch')
                    if actual in used_hashes and used_hashes[actual] != name:
                        raise ValueError('duplicate icon for ' + used_hashes[actual])
                    used_hashes[actual] = name
                    status = 'approved-local'
                except (OSError, ValueError) as exc:
                    issue = str(exc)
        if status != 'approved-local' and metadata.get('artworkStatus') == 'product-specific' and metadata.get('iconFile'):
            status = 'curated-remote'
        results.append({'app': name, 'status': status, 'issue': issue})
    return results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--json', action='store_true', help='Machine-readable output')
    args = ap.parse_args()
    rows = inventory()
    if args.json:
        print(json.dumps(rows, indent=2))
        return
    totals = {key: sum(r['status'] == key for r in rows) for key in ('approved-local', 'curated-remote', 'missing')}
    print('LIBREREPLACE ARTWORK INVENTORY — exact product identities')
    print('Approved on this Mac:', totals['approved-local'])
    print('Curated remote images:', totals['curated-remote'])
    print('No approved image:', totals['missing'])
    print('Total product identities:', len(rows))
    bad = [r for r in rows if r['issue']]
    for row in bad:
        print(f"INVALID: {row['app']}: {row['issue']}")
    print('\nPRODUCTS STILL MISSING ARTWORK:')
    print(', '.join(r['app'] for r in rows if r['status'] == 'missing') or '(none)')
    print('\nNo repository, application, or approved asset files were changed.')


if __name__ == '__main__':
    main()
