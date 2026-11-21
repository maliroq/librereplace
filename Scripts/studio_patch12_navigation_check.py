#!/usr/bin/env python3
"""Read-only Patch 12 nav regression check, no Xcode required."""
from pathlib import Path
import re
root = Path(__file__).resolve().parents[1]
def read(path):
    return (root/path).read_text()
main = read('App/LibreReplaceApp/Views/MainView.swift')
replace = read('App/LibreReplaceApp/Views/StudioReplaceView.swift')
composer = read('App/LibreReplaceApp/Views/StudioComposerView.swift')
library = read('App/LibreReplaceApp/Views/StudioLibraryView.swift')
home = read('App/LibreReplaceApp/Views/StudioHomeView.swift')
twins = read('App/LibreReplaceApp/Views/StudioFreeTwinsView.swift')
checks = {
    'Five primary destinations only': re.findall(r'case \w+ = "[^"]+"',main.split('@EnvironmentObject')[0]) == [
        'case discover = "Discover"', 'case setups = "My Setups"', 'case tools = "Tools"',
        'case community = "Community"', 'case mac = "My Mac"'],
    'Single replacement planning page': 'StudioReplaceView(' in main and 'StudioComposerView(embedded: true' in replace and 'if !embedded {' in composer,
    'Single requirements selector on Discover': 'requirements(for: app)' in composer and 'studioReplacement' not in main and 'ForEach(app.capabilities' not in replace,
    'Recipe entry reachable from replacement and library': 'onOpenRecipes: { selection = .community }' in main and 'StudioRecipesView(onOpenComposer:' in main,
    'Saved setups and recipes retained': 'StudioFreeTwinsView(' in main and 'StudioRecipesView(' in main,
    'Existing consumer twins retained': 'StudioEspansoTwinView()' in twins and 'StudioFreeTwinEngine().prepare' in twins,
    'Existing tools retained': 'StudioWorkflowLabView(initialMode: requestedLabMode)' in main and 'openTools(.rescue)' in main,
    'My Mac utilities remain reachable': all(x in read('App/LibreReplaceApp/Views/StudioMyMacView.swift') for x in ['DetectedAppsView()', 'OverviewView()', 'CatalogView()', 'PrivacyView()']),
    'No duplicate setup recommendations in library': 'Find your next free setup' not in twins,
    'No duplicate Home and Discover search': 'case home = "Home"' not in main and 'StudioHomeView(' not in main and replace.count('TextField(') == 1,
    'Existing recipe and installation controls retained': all(x in composer for x in [
        'StudioGuidedSwitchView', 'StudioSavedSetupLibrary.add', 'StudioRecipeFactory.makeDraft']),
}
for title, passed in checks.items():
    print(('PASS' if passed else 'FAIL') + ': ' + title)
if not all(checks.values()):
    raise SystemExit('PATCH 12 NAVIGATION CONTRACT FAIL')
print('PATCH 12 NAVIGATION CONTRACT PASS')
