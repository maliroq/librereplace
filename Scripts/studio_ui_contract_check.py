#!/usr/bin/env python3
"""Read-only source-level UI regression checks; not a substitute for visual QA."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parent.parent


def source(relative: str) -> str:
    return (root / relative).read_text(encoding="utf-8")

lab = source("App/LibreReplaceApp/Views/StudioWorkflowLabView.swift")
files = source("App/LibreReplaceApp/Views/StudioFileToolsView.swift")
recipes = source("App/LibreReplaceApp/Views/StudioRecipesView.swift")
main = source("App/LibreReplaceApp/Views/MainView.swift")
empty = source("App/LibreReplaceApp/Views/StudioCompactEmptyState.swift")

checks = {
    "Single accessible workflow selector": (
        lab.count('Picker("Choose a workflow", selection: $labMode)') == 1
        and '.labelsHidden()' in lab
        and '.accessibilityLabel("Choose a workflow")' in lab
        and 'Text("Tool")' not in lab
    ),
    "Distinct PDF/image input state": '.id(labMode)' in lab,
    "Searchable PDF is a real selectable workflow": (
        'case searchable = "Searchable PDF"' in lab
        and 'StudioSearchablePDFView().id(labMode)' in lab
        and (root / "App/LibreReplaceApp/Views/StudioSearchablePDFView.swift").exists()
    ),
    "Compact empty states in all three tools": (
        'StudioCompactEmptyState(' in lab
        and 'StudioCompactEmptyState(' in files
        and 'accessibilityElement(children: .combine)' in empty
    ),
    "Single accessible image-format selector": (
        files.count('Picker("Output format", selection: $format)') == 1
        and '.accessibilityLabel("Output image format")' in files
    ),
    "Recipe creation opens Composer": (
        'Button {' in recipes
        and 'onOpenComposer()' in recipes
        and 'Button("Start a setup") { onOpenComposer() }' in recipes
        and 'StudioRecipesView(onOpenComposer:' in main
    ),
    "Document rescue combines OCR and PDF merge with a real UI": (
        'case rescue = "PDF Rescue"' in lab
        and 'StudioPDFRescueView().id(labMode)' in lab
        and (root / "App/LibreReplaceApp/Views/StudioPDFRescueView.swift").exists()
        and (root / "Sources/LibreReplaceCore/StudioPDFRescueBridge.swift").exists()
    ),
    "Acrobat trial opens PDF Rescue directly": (
        'onOpenPDFRescue()' in source("App/LibreReplaceApp/Views/StudioComposerView.swift")
        and 'openTools(.rescue)' in main
    ),
    "Unified discovery and cross-catalog workflows": (
        'case discover = "Discover"' in main
        and 'StudioReplaceView(' in main
        and 'onBuild: build' in main
        and 'StudioComposerView(embedded: true' in source("App/LibreReplaceApp/Views/StudioReplaceView.swift")
    ),
    "Defensive footer copy removed": (
        "We won't pretend every comparison" not in source("App/LibreReplaceApp/Views/StudioFreeTwinsView.swift")
        and "There is no arbitrary snippet count limit" not in source("App/LibreReplaceApp/Views/StudioFreeTwinsView.swift")
    ),
    "Existing file actions preserved": (
        all(x in lab for x in ('chooseFiles()', 'run()', 'saveResult()'))
        and all(x in files for x in ('pickFiles()', 'start()', 'reveal()'))
    ),
}
for name, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
if not all(checks.values()):
    print("UI SOURCE CONTRACT FAIL: resolve the above regressions.")
    sys.exit(1)
print("UI SOURCE CONTRACT PASS (static checks; inspect native layout on macOS).")
