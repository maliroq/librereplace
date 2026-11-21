#!/usr/bin/env python3
"""Non-macOS regression checks for install-optional Guided Switch UI contracts."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
view = (root / "App/LibreReplaceApp/Views/StudioGuidedSwitchView.swift").read_text()
composer = (root / "App/LibreReplaceApp/Views/StudioComposerView.swift").read_text()

sections = [
    'section(1, "Check the match")',
    "section(2, \"See what's ready on your Mac\")",
    'section(3, "Try it out")',
    'section(4, "Record what worked")',
]
assert all(view.count(item) == 1 for item in sections), "missing/duplicate Guided Switch section"
assert [view.index(item) for item in sections] == sorted(view.index(item) for item in sections), "step definitions out of sequence"
assert 'Button("Save for later") { saveForLater() }' in view
assert 'StudioSavedSetupLibrary.add(saved, in: support)' in view
assert 'Saved in My Setups.' in view
assert "matchSection\n                    readySection\n                    trySection\n                    recordSection" in view, "UI step sequence regression"
assert '_selectedIDs = State(initialValue: [])' in view, "installation selections must start empty"
assert 'DisclosureGroup("Install missing free apps (optional)", isExpanded: $showInstallOptions)' in view
assert '@State private var showInstallOptions = false' in view, "installation disclosure must start closed"
assert 'Button("Review selected installations…") { showInstallConfirmation = true }' in view
assert '.alert("Approve Homebrew installation?"' in view
assert 'StudioInstallApproval.approve(plan: plan, selectedIDs: Set(selected.map(\\.id)))' in view
assert 'installer.preflightReady && !installer.isInstalling && !installer.checking' in view
assert 'Text(nextTrialStep)' in view, "disabled save controls need an explanation"
assert 'StudioWorkflowTrialStore.essentialIDs(for: plan)' in view
assert 'plan.components.count < 2 || testedHandoff' in view
assert 'Button("Save my tested result") { saveTrial() }' in view
assert '.disabled(!canRecordTrial)' in view
assert 'Coverage is based on the catalog. Try your own tasks before switching.' in view
assert 'Explore setup…' in composer
assert 'Review gaps…' in composer
assert 'NSWorkspace.shared.open(installed.path)' in view, "only detected exact apps can open"

assert '.onChange(of: showInstallOptions)' in view, "Homebrew checks should start only when a user opens installation options"
assert 'await installer.check(items)' not in view.split('.task {', 1)[1].split('.onChange(of: showInstallOptions)', 1)[0], "No automatic Homebrew calls while browsing"
assert 'finishedAppScan && missingDesktopApps.isEmpty' in view, "cannot save a trial for a missing app"
assert '.disabled(!finishedAppScan || !missingDesktopApps.isEmpty)' in view
community = (root / "App/LibreReplaceApp/Views/StudioRecipesView.swift").read_text()
assert 'StudioRecipePlanResolver.resolve' in community
assert 'Button("Explore this setup…")' in community
assert 'StudioRecipeLibrary.remove' in community
assert 'onOpenLab: onOpenLab' in community
print('Guided Switch and Community no-install usability checks OK')
