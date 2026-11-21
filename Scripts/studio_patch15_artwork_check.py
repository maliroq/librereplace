#!/usr/bin/env python3
"""Static guardrails for high-integrity product artwork.

This test does not claim to validate current network images or Mac rendering.
"""
from pathlib import Path
import json, re, sys
root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / 'Catalog/app_artwork.json').read_text())
catalog = json.loads((root / 'Catalog/catalog.json').read_text())
swift = (root / 'App/LibreReplaceApp/AppPresentation.swift').read_text()
keys = {a['name'].lower() for a in catalog['apps']}
keys |= {alt['name'].lower() for a in catalog['apps'] for alt in a['alternatives']}
records = manifest['apps']
icons = [(k, v['iconFile']) for k, v in records.items() if v.get('iconFile')]
forbidden = {'adobe photoshop', 'adobe acrobat pro', 'adobe illustrator',
             'adobe indesign', 'adobe premiere pro', 'adobe audition', 'adobe lightroom'}
reused = len({v for k,v in icons}) != len(icons)
checks = {
    'Complete catalog artwork identity registry': manifest.get('schemaVersion') == 2 and keys == set(records),
    'No website favicon mappings': all('domain' not in entry for entry in records.values()),
    'Individual product images have identity-specific filenames': all(re.fullmatch(r'[a-z0-9][a-z0-9-]*\.png', v) for _,v in icons),
    'No repeated product art for different catalog entries': not reused,
    'No restricted Adobe images distributed or referenced': all(not records[k].get('iconFile') for k in forbidden if k in records),
    'No LibreOffice suite icon labeled as Draw': not records['libreoffice draw'].get('iconFile'),
    'No generic five-icon set accepted from exported Mac scan': all(not records[k].get('iconFile') for k in ('adobe photoshop','adobe acrobat pro','bear','cleanmymac','tower')),
    'Curated artwork retained for known products': len(icons) >= 25,
    'Only explicit product-specific icons load remotely': 'entry.artworkStatus == "product-specific"' in swift,
    'Generic fallback fingerprint checked': '0x0f332b45552933cc' in swift and 'isDistinctAppIcon' in swift,
    'Installed app lookup uses exact identity': 'Bundle(url: url)?.bundleIdentifier == id' in swift,
    'Fuzzy prefix app matching removed': 'installedName.hasPrefix' not in swift,
    'Brand favicon service eliminated': 'google.com/s2/favicons' not in swift,
    'Five-tab UI preserved': 'case community = "Community"' in (root / 'App/LibreReplaceApp/Views/MainView.swift').read_text(),
}
for name, passed in checks.items():
    print(('PASS' if passed else 'FAIL') + ': ' + name)
if not all(checks.values()): sys.exit('PATCH 15 ARTWORK GUARDRAIL FAILED')
print('PATCH 15 ARTWORK CONTRACT PASS')
print(f'Product-specific curated artworks: {len(icons)}/{len(records)}; intentionally withheld: {len(records)-len(icons)}.')
