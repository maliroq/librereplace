#!/usr/bin/env python3
"""Static macOS-UI wiring checks; native Xcode builds provide the final type check."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
state = (root/'App/LibreReplaceApp/AppState.swift').read_text()
main = (root/'App/LibreReplaceApp/Views/MainView.swift').read_text()
guided = (root/'App/LibreReplaceApp/Views/StudioGuidedSwitchView.swift').read_text()
core = (root/'Sources/LibreReplaceCore/StudioLocalToolRoute.swift').read_text()
assert 'state.beginLocalToolTrial(plan: plan, sourceApp: sourceApp, mode: mode)' in guided
assert 'guard let sourceApp, saveForLater() else { return }' in guided
assert 'Button(route.buttonTitle) { saveAndOpenLocalTool(route) }' in guided
assert 'if let route = StudioLocalToolRoute.forPlan(plan)' in guided
assert 'return true' in guided.split('private func saveForLater()',1)[1].split('private func saveAndOpenLocalTool',1)[0]
assert 'let plan: StudioComposedPlan' in state and 'let sourceApp: PaidApplication' in state
assert 'requestedLabMode = state.requestedLocalToolMode ?? mode' in main
assert 'Button("Return to setup") { returnToSetup = visit }' in main
assert 'StudioGuidedSwitchView(plan: visit.plan, sourceApp: visit.sourceApp' in main
assert 'Button("Finish") { state.toolContinuation = nil }' in main
assert 'bridge.image-ocr' in core and 'bridge.document-text-ocr' in core
assert 'return nil' in core
assert 'StudioWorkflowTrialStore.recordSuccessfulTrial(' in guided
assert 'try StudioSavedSetupLibrary.add(saved, in: support)' in guided
print('Exact-plan Tools continuation checks OK')
