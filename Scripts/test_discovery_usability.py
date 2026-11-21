#!/usr/bin/env python3
"""Static UI contracts for truthful, discoverable no-install comparisons."""
from pathlib import Path
import json

root = Path(__file__).resolve().parents[1]
def read(name):
    return (root / name).read_text(encoding="utf-8")

composer = read("App/LibreReplaceApp/Views/StudioComposerView.swift")
search = read("App/LibreReplaceApp/Views/StudioReplaceView.swift")
setups = read("App/LibreReplaceApp/Views/StudioFreeTwinsView.swift")
guided = read("App/LibreReplaceApp/Views/StudioGuidedSwitchView.swift")
installed = read("App/LibreReplaceApp/Views/DetectedAppsView.swift")

catalog = json.loads(read("Catalog/catalog.json"))
transmit = next(app for app in catalog["apps"] if app["name"] == "Transmit")
assert len(transmit["alternatives"]) == 1
assert transmit["alternatives"][0]["name"] == "Cyberduck"
assert "if app.alternatives.count > 1" in composer
assert r'Compare \(app.alternatives.count) individual free apps' in composer
assert composer.index('individualAlternatives(for: app)') < composer.index('plans(for: app)')
assert 'if app.alternatives.count > 1' in composer
assert 'Button("Save for later")' in composer
assert 'Menu("More")' in composer
assert 'showComparison = false' in composer
assert 'Catalog match' in composer
assert 'searchRank(_ app:' in search
assert 'return left == right' in search
assert 'Free app match:' in search
assert 'Open setup…' in setups
assert 'sourceApp: item.sourceApp' in setups
assert 'onDismiss: { loadSavedPlans() }' in setups
assert 'Review gaps…' in setups
assert '.disabled(sourceApp == nil || installer.isInstalling)' in guided
assert 'Save for later' in guided
assert 'Strong catalog match' in installed
assert 'restoreRequiredFeatures(savedPlan.requiredFeatureIDs' in setups
assert 'cleanshotRequiresLocalOCR.v1' in setups
assert '@AppStorage("LibreReplace.studio.cleanshotRequiresLocalOCR.v1")' in composer
assert '            requireLocalOCR = false' not in composer
assert 'hasTestedResult(plan)' in setups
assert 'A damaged trial history never hides saved plans.' in setups
print('Discovery, no-install, saved plan restoration and trial status checks OK')
