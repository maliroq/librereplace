# Catalog schema and evidence rules

`Catalog/catalog.json` is the source of recommendation claims. `Catalog/schema.json` documents its JSON shape; the Swift and Python validators enforce the cross-field invariants that JSON Schema cannot express cleanly.

## Source application

Each cataloged commercial app has:

- stable `id`, display `name`, vendor, bundle identifiers, and conservative name aliases;
- informational pricing metadata and a primary pricing/product source when available;
- weighted user-visible capabilities, with workflow-critical capabilities marked `critical`;
- one or more alternatives;
- app-specific strong/partial thresholds;
- dated evidence records and `lastVerified`.

Bundle identifiers must be unique across the catalog. Normalized app names/aliases may not collide across different source apps because name fallback must never be ambiguous.

## Alternative

Each alternative has:

- license name and license kind;
- source repository when applicable and an HTTPS homepage;
- a typed installation method;
- a support state for every source capability;
- explicit limitations;
- dated feature/license/maintenance/installation evidence;
- optional verified minimum macOS version;
- optional compiled migration-adapter ID.

Support states:

- `full` — materially satisfies the stated capability;
- `partial` — useful but meaningfully incomplete/different;
- `none` — does not provide it;
- `unknown` — evidence is insufficient.

`unknown` scores the same as `none` so uncertainty cannot inflate parity.

## Freshness

Evidence older than 180 days is stale. Future-dated `generatedAt`, `lastVerified`, or evidence dates are invalid; future dates cannot be used to manufacture freshness. The Python catalog validator rejects stale app, alternative, and evidence records. The ranking layer independently requires fresh app + alternative + supporting evidence before a recommendation can be `strong`.

## Pricing

Pricing is informational only. The catalog may describe a current one-time/subscription/freemium model and cite a pricing page, but LibreReplace never treats that as proof of the user's actual plan. Savings use only an annual recurring amount explicitly entered by the user for the current session.

## Installation safety

Homebrew installation values are validated package tokens. Download/evidence/pricing URLs must be credential-free HTTPS URLs; Mac App Store actions may use its dedicated scheme. Catalog data cannot inject arbitrary migration scripts or shell commands.
