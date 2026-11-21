#!/usr/bin/env python3
"""Portable source-contract checks for the Community and artwork workflow."""
from pathlib import Path
import json
root = Path(__file__).resolve().parent.parent
view = (root/'App/LibreReplaceApp/Views/StudioRecipesView.swift').read_text()
art = (root/'App/LibreReplaceApp/AppPresentation.swift').read_text()
core = (root/'Sources/LibreReplaceCore/StudioCommunityRegistry.swift').read_text()
issue = (root/'.github/ISSUE_TEMPLATE/community-build.yml').read_text()
registry = json.loads((root/'Community/index.v1.json').read_text())
checks = {
    'Five primary navigation destinations unchanged': 'case community = "Community"' in (root/'App/LibreReplaceApp/Views/MainView.swift').read_text(),
    'Centered community introduction': 'Share setups that work' in view and '.multilineTextAlignment(.center)' in view,
    'Searchable community gallery': 'Search by app, task, or free tool' in view and 'ForEach(filtered)' in view,
    'Distinct local imports': 'Your imported builds' in view and 'StudioRecipeLibrary.store' in view,
    'Submission opens GitHub review': 'community-build.yml' in view and 'Share your build' in view,
    'Submission template includes evidence': 'What did you personally test?' in issue and 'Attach or link your JSON recipe' in issue,
    'Registry anchored to owner repository': 'maliroq/librereplace/main/Community/index.v1.json' in core,
    'Strict indexed recipe path': '"Community/recipes/\\(build.id).json"' in core,
    'Downloaded recipes checked with SHA256': 'SHA256.hash(data: data)' in view and 'build.recipeSHA256' in view,
    'Imported recipes are not executed': 'StudioRecipeLibrary.store' in view and 'Process(' not in view,
    'Locally approved exact artwork is supported': 'ApprovedArtwork.image(for: name)' in art and 'SHA256.hash(data: data)' in art,
    'Artwork sourcing does not modify apps': 'No applications are installed' in (root/'Scripts/studio_gather_official_artwork.py').read_text(),
    'Empty registry makes no fabricated submissions': registry == {'schemaVersion':1,'builds':[]},
}
for label, passed in checks.items():
    print(('PASS: ' if passed else 'FAIL: ')+label)
assert all(checks.values()), 'Patch 16 contract failed'
print('PATCH 16 COMMUNITY & ARTWORK CONTRACT PASS')
