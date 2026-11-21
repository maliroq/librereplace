#!/usr/bin/env python3
"""Read-only Patch 14 source contract. Native image loading requires macOS acceptance."""
import json
from pathlib import Path
root = Path(__file__).resolve().parents[1]
manifest = json.loads((root/'Catalog/app_artwork.json').read_text())
catalog = json.loads((root/'Catalog/catalog.json').read_text())
main = (root/'App/LibreReplaceApp/Views/MainView.swift').read_text()
view = (root/'App/LibreReplaceApp/AppPresentation.swift').read_text()
expected = {a['name'].lower() for a in catalog['apps']}
expected.update(alt['name'].lower() for a in catalog['apps'] for alt in a['alternatives'])
checks = {
  'Five purposeful destinations': all(f'case {k} = "{v}"' in main for k,v in [('discover','Discover'),('setups','My Setups'),('tools','Tools'),('community','Community'),('mac','My Mac')]),
  'Five destinations only': main.split('@EnvironmentObject')[0].count(' = "') == 5,
  'Catalog has artwork entry for every known app': expected <= set(manifest['apps']),
  'Curated branded images': sum(bool(v.get('iconFile')) for v in manifest['apps'].values()) >= 25,
  'No fabricated monogram logos': 'Text(initials)' not in view,
  'Authentic local bundle icons retained': 'NSWorkspace.shared.icon(forFile:' in view,
  'Real remote app artwork loaded': 'AsyncImage(url: iconURL)' in view,
  'Artwork resources packaged': 'Catalog/app_artwork.json' in (root/'project.yml').read_text(),
  'Community is separate from saved setups': 'case .community:' in main and 'StudioRecipesView(' in main,
  'Mac utilities remain accessible': all(x in (root/'App/LibreReplaceApp/Views/StudioMyMacView.swift').read_text() for x in ['DetectedAppsView()', 'OverviewView()', 'CatalogView()', 'PrivacyView()']),
}
for name,ok in checks.items(): print(('PASS' if ok else 'FAIL')+': '+name)
if not all(checks.values()): raise SystemExit('PATCH 14 VISUAL CONTRACT FAILED')
print('PATCH 14 VISUAL CONTRACT PASS')
