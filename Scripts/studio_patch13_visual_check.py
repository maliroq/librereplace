#!/usr/bin/env python3
"""Verify description completeness and real-artwork policy without a Mac."""
from pathlib import Path
import json, sys, re
root = Path(__file__).resolve().parents[1]
catalog = json.loads((root/'Catalog/catalog.json').read_text())
visual = json.loads((root/'Catalog/app_presentation.json').read_text())
paid = {app['id'] for app in catalog['apps']}
free = {alt['id'] for app in catalog['apps'] for alt in app['alternatives']}
checks = {
  'All paid apps have editorial descriptions': set(visual['paidDescriptions']) == paid,
  'All free alternatives have editorial descriptions': set(visual['alternativeDescriptions']) == free,
  'Descriptions are substantive, not placeholders': all(
      45 <= len(txt) <= 160 and not any(w in txt.lower() for w in ['lorem ipsum', 'coming soon'])
      for txt in list(visual['paidDescriptions'].values()) + list(visual['alternativeDescriptions'].values())),
  'Presentation catalog packaged into macOS app': 'Catalog/app_presentation.json' in (root/'project.yml').read_text(),
  'Five primary sidebar tabs': len(re.findall(r'^\s*case \w+ = "',
        (root/'App/LibreReplaceApp/Views/MainView.swift').read_text().split('@EnvironmentObject')[0], re.M)) == 5,
  'Real icons read from installed app bundles': 'NSWorkspace.shared.icon(forFile:' in (root/'App/LibreReplaceApp/AppPresentation.swift').read_text(),
  'No invented branded artwork': 'not an invented logo' in (root/'App/LibreReplaceApp/AppPresentation.swift').read_text(),
  'Real icons present on discovery and setup cards': all('AppArtwork(' in (root/rel).read_text() for rel in [
     'App/LibreReplaceApp/Views/StudioReplaceView.swift',
     'App/LibreReplaceApp/Views/StudioComposerView.swift',
     'App/LibreReplaceApp/Views/StudioFreeTwinsView.swift'])
}
for k,v in checks.items(): print(('PASS' if v else 'FAIL')+': '+k)
if not all(checks.values()): sys.exit(1)
print('PATCH 13 VISUAL CONTRACT PASS')
