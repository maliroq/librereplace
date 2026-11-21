# Community Builds — publication and review

The macOS Community page reads a curated public registry from
`https://raw.githubusercontent.com/maliroq/librereplace/main/Community/index.v1.json`.
The source currently contains an **empty** registry. It must be committed and
published on `main` before the first online build appears. The app also offers
local JSON import when offline; importing a recipe never executes its actions.

## Contributor flow

1. In Discover, select the paid app and requirements and create a real replacement plan.
2. Export its `.json` recipe, test the intended free setup, and record limitations.
3. Select **Community → Share your build** and file a GitHub submission using
   `.github/ISSUE_TEMPLATE/community-build.yml` (this form becomes available
   after the branch containing it is published).
4. Attach the JSON or ZIP file, explain all manual steps, and identify tested
   app/macOS versions. Do not attach personal data.

## Maintainer publishing procedure

1. Review the submission and licensing, and reproduce the claimed capabilities.
2. Decode the JSON with `StudioSafeRecipeLoader` using the current component
   catalog; reject any unknown action or unsupported component.
3. Store the unmodified recipe at `Community/recipes/<id>.json`. Require the recipe
   ID to match `<id>`; the registry slug must be lower-case ASCII with hyphens.
4. Compute the recipe file's **SHA-256** (not the metadata file's hash), then add
   the record to `Community/index.v1.json` with that exact 64-character checksum.
5. Include the source app, the actual free apps, contributor, and review date.
   The app says *reviewed*—not "end-to-end verified"—because a file review
   alone does not prove the replacement works for everyone.
6. Publish a pull request, inspect the change, and merge to the `main` branch.
   The app automatically fetches the published registry on its next visit.

The app enforces a 128 KiB registry limit, 250 records, constrained recipe paths,
exact SHA-256 matching, HTTPS host scoping, and the existing 256 KiB safe recipe
loader. An imported recipe **never runs an installation or command on import**.

## Future hosted community features

The curated, GitHub-backed approach is an initial real publication channel,
not a social network: ratings, in-app accounts, votes, comments, and authenticated
in-app uploads are not part of this patch. Those require a trusted service and
moderation system. Keep the interface accurate about that distinction.
