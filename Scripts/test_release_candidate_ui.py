#!/usr/bin/env python3
"""Fast, portable regression contract for the consumer release candidate UX."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
def content(path):
    return (ROOT / path).read_text(encoding='utf-8')
library = content('App/LibreReplaceApp/Views/StudioFreeTwinsView.swift')
switch = content('App/LibreReplaceApp/Views/StudioGuidedSwitchView.swift')
lab = content('App/LibreReplaceApp/Views/StudioWorkflowLabView.swift')
main = content('App/LibreReplaceApp/Views/MainView.swift')
art = content('App/LibreReplaceApp/AppPresentation.swift')
assert library.count('savedSetupSection') >= 2
assert 'DisclosureGroup(isExpanded: $showMigrationTools)' in library
assert library.index('savedSetupSection\n') < library.index('DisclosureGroup(isExpanded: $showMigrationTools)')
assert 'StudioEspansoTwinView()' in library
assert 'Move settings from another app' in library
assert '.navigationTitle("My Setups")' in library
assert 'Save for later' in switch
assert 'Install missing free apps (optional)' in switch
assert 'Record what worked' in switch
assert 'Coverage is based on the catalog' in switch
assert 'imageOnly: state.toolContinuation?.plan.components.contains' in main
assert 'imageOnly ? [.png, .jpeg, .heic, .tiff]' in lab
assert 'Text(imageOnly ? "Extract text from images"' in lab
assert 'let initials = name.split' in art
assert 'ApprovedArtwork.image(for: name)' in art
assert 'BrandArtwork.url(for: name)' in art
assert 'GroupBox' in library and 'StudioWorkflowTrial' in library
print('Release candidate UX contracts PASS')
