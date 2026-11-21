#!/usr/bin/env python3
"""Regression checks for local-approved artwork priority and audit integrity."""
import hashlib, json, tempfile
from pathlib import Path
from studio_artwork_inventory import inventory

root = Path(__file__).resolve().parents[1]
swift = (root / 'App/LibreReplaceApp/AppPresentation.swift').read_text()
start = swift.index('var body: some View {', swift.index('struct AppArtwork: View'))
body = swift[start:swift.index('private var placeholder:', start)]
assert body.index('ApprovedArtwork.image(for: name)') < body.index('realInstalledIcon') < body.index('BrandArtwork.url(for: name)'), 'Approved local artwork must win'
assert 'entry.sha256' in swift and 'SHA256.hash(data: data)' in swift
assert 'Bundle(url: url)?.bundleIdentifier == id' in swift
assert 'isDistinctAppIcon' in swift
assert 'google.com/s2/favicons' not in swift
assert len(inventory()) == 100
with tempfile.TemporaryDirectory() as tmp:
    # Verify the audit gives priority to a hash-validated local app asset.
    approved = Path(tmp) / 'approved'; approved.mkdir()
    data = (b'\x89PNG\r\n\x1a\n' + b'\0' * 8 + (512).to_bytes(4, 'big') * 2 + b'\0' * 24)
    (approved / 'tower.png').write_bytes(data)
    (approved / 'manifest.json').write_text(json.dumps({'schemaVersion': 1, 'apps': {
        'tower': {'filename': 'tower.png', 'sha256': hashlib.sha256(data).hexdigest()}
    }}))
    rows = {v['app']: v for v in inventory(root, approved)}
    assert rows['tower']['status'] == 'approved-local'
    assert rows['textexpander']['status'] == 'missing'
    (approved / 'tower.png').write_bytes(data + b'tamper')
    assert {v['app']:v for v in inventory(root, approved)}['tower']['issue'] == 'checksum mismatch'
print('PATCH 17 APPROVED-ARTWORK PRIORITY & INVENTORY PASS')
