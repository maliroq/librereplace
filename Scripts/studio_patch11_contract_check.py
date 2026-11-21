#!/usr/bin/env python3
"""Low-cost source integration guard. Native macOS build remains authoritative."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
checks = {
    'App/LibreReplaceApp/Views/StudioLibraryView.swift': ['StudioFreeTwinsView', 'onOpenLab:'],
    'App/LibreReplaceApp/Views/StudioFreeTwinsView.swift': ['StudioEspansoTwinView()', 'StudioSavedSetupLibrary', 'StudioGuidedSwitchView'],
    'App/LibreReplaceApp/Views/StudioEspansoTwinView.swift': ['StudioEspansoTwin.prepare', 'StudioEspansoTwin.undo', 'allowsMultipleSelection = true'],
    'App/LibreReplaceApp/Views/StudioComposerView.swift': ['Button("Save for later")', 'StudioSavedSetupLibrary.add'],
    'Sources/LibreReplaceCore/StudioEspansoTwin.swift': ['approved: Bool', 'fingerprint(bytes)', 'linkItem(at: temp, to: dest)', 'StudioEspansoTwinError.modifiedFile'],
    'Sources/LibreReplaceCore/StudioSnippetSwitch.swift': ['func audit(files:', 'type: clipboard', 'type: date', 'maximumSnippets = 100_000'],
    'Sources/LibreReplaceCore/StudioSavedSetups.swift': ['public static func resolve', 'current catalog', 'public static func add'],
    'Tests/LibreReplaceCoreTests/StudioEspansoTwinTests.swift': ['testBulkConversionWithLargeLibraryAndEscaping', 'testEditedGeneratedFileCannotBeRolledBack'],
    'Tests/LibreReplaceCoreTests/StudioSavedSetupTests.swift': ['testInvalidSavedDataIsNeverOverwritten'],
}
for relative, patterns in checks.items():
    text = (root / relative).read_text()
    for pattern in patterns:
        if pattern not in text:
            raise SystemExit(f'FAIL: missing {pattern!r} in {relative}')
print(f'PATCH 11 SOURCE INTEGRATION PASS ({len(checks)} files checked)')
