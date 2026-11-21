# How LibreReplace works

LibreReplace pairs a native SwiftUI experience with a portable Swift core. The aim is straightforward: **turn a complex software replacement decision into a smooth, repeatable Mac workflow**.

## The product journey

**Discover → Compose → Explore → Try → Save → Switch → Share**

- **Discover:** local app metadata and a curated feature catalog identify relevant paid apps and free alternatives.
- **Compose:** the FreeStack engine evaluates combinations of apps and selected built-in tools against user-chosen requirements.
- **Explore:** setup cards explain the components, feature coverage and optional next actions.
- **Try:** local tools or detected installed apps let the user test a real task.
- **Save:** exact setup components, requirements and user-confirmed trial results remain available across sessions.
- **Switch:** explicit installation approvals and supported migration adapters preview and verify changes.
- **Share:** declarative recipes carry a combination's ingredients and requirements into the Community workflow.

## Code organization

- `App/LibreReplaceApp` — native interface, five destinations and guided setup flows.
- `Sources/LibreReplaceCore` — catalog, matching, ranking, setup composition, local bridges, saved plans, recipe handling, installation and migrations.
- `Catalog` — product and capability data, presentation metadata and artwork mappings.
- `Recipes` and `Community` — recipe schema, examples and curated gallery registry.
- `Tests`, `Scripts` and `dev.py` — portable verification, macOS builds, UI contracts and migration checks.

`project.yml` is the source of truth for the generated Xcode project.

## Design principles

Use existing macOS controls. Keep normal app discovery metadata-only. Open documents only when chosen by the user. Treat external recipes as data rather than executable instructions. Separate optional installation from exploration, and build recoverable migrations around scoped changes.

[Building](BUILDING.md) · [Privacy](PRIVACY.md) · [Contributing](../CONTRIBUTING.md)
