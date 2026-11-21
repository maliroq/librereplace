# Replacement recipes · format v1

A LibreReplace recipe saves the structure of a replacement setup so that someone else can review and adapt it. Recipes are **declarative**: importing one never installs an app, changes preferences or executes a command.

## What a recipe contains

- `schemaVersion`: `1`
- `id`: a stable lowercase identifier
- `sourceWorkflow`: the paid-app workflow being addressed
- `requirements`: feature IDs and whether each is essential
- `componentIDs`: catalog tools and built-in bridges used by the setup
- `actions`: typed declarations such as a Homebrew package, a built-in bridge or a capability to verify

The authoritative validator is `StudioSafeRecipeLoader`; the companion `Recipes/schema.v1.json` describes the file format. App references and package tokens must match supported catalog components. Unsupported instructions and arbitrary shell commands are not accepted.

## Create and share a recipe

In Discover, choose a commercial app, select your essential features and choose a suitable free setup. Use **Export recipe** when available to create its JSON representation. Record what you actually tested, including manual steps and gaps.

In Community, you can **Import recipe** to add a validated setup to your local library. You can reopen it in Discover without losing its component choices. Public submissions go through GitHub review before being included in the Community gallery.

[Community build guide](STUDIO_COMMUNITY_BUILD_GUIDE.md) · [Studio overview](STUDIO_GUIDE.md)

## Local validation

```bash
swift run libreplace studio-validate-recipe Catalog/catalog.json cleanshot-x Recipes/cleanshot-capture-plus-local-ocr.v1.json
```

The supplied CleanShot example pairs a screenshot utility with local image OCR. Moving the screenshot from one component to the other can require a manual file handoff; recipe validation is not an interoperability test.
