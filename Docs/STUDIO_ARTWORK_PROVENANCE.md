# LibreReplace Studio — Artwork provenance and acceptance

This document concerns **visual identity**, not the replacement capability tests.

## What changed in Patch 15

- Icon lookup no longer substitutes website favicons for unrelated macOS application icons.
- Bundle identifier matching is exact; fuzzy prefix matching no longer assigns an unrelated installed application's icon.
- The app rejects the common generic macOS placeholder as if it were vendor artwork. The Mac-exported icon archive had five different commercial apps with identical rendered placeholders.
- Known product-specific artwork from the previously catalogued Dashboard Icons filenames remains available. Those images are served remotely; their vendor permissions and upstream contents should be reviewed before a public release.
- Adobe product-specific icon URLs are intentionally omitted: Adobe's published third-party permissions generally prohibit product-icon use without a qualifying agreement. Logos shouldn't be copied into the app just to fill space.

## Source audit, November 15, 2026

Source user-provided archive: `LibreReplace-Real-Icons-20261115-201955-986005.zip`, containing 85 icon records. Exported fallback artwork for Acrobat Pro, Photoshop, Bear, CleanMyMac, and Tower shared one identical SHA-256 hash: `1500b000c0604beb4cca5390416df55a57ceb973a95826d25923317599b31b41`. The `StudioArtworkQuality` check uses its 64-bit difference-hash fingerprint and also checks the current macOS system default icon.

This is a filter rather than a guarantee: icon variants, OS rendering, and user custom icons may yield false results. A real native macOS visual test is required.

## Remaining artwork work

There are 100 names in the paid/free catalog. The first curated subset contains 29 product-specific references; 71 have no approved product-specific remote artwork. This is **not** a finished 100-icon collection.

To fill gaps in future patches, record each image's exact product, official source or repository, use permission, dimensions, checksum, current version, date audited, and whether the image represents a Mac Dock app icon or a product logo. Do not automatically borrow Adobe corporate artwork, a macOS Generic App icon, or a company favicon. Do not distribute unrelated icons from an individual's installed-app scan.

Vendor sources for authorized follow-up:

- Tower Dock Icon: https://www.git-tower.com/company/press/
- CleanMyMac brand kit: https://macpaw.com/press
- Bear current icon information: https://bear.app/faq/bear-app-icons/
- Adobe restrictions: https://www.adobe.com/legal/permissions/icons-web-logos.html
- Dashboard Icons artwork (third-party trademarks remain subject to owner guidelines): https://github.com/homarr-labs/dashboard-icons

## Acceptance requirements

1. Xcode build and tests pass on macOS.
2. Discover and My Mac never show five identical blank symbols as five "authentic" product icons.
3. Every image displayed is an exact installed icon or an explicitly keyed product image; unmatched entries show neutral system artwork.
4. Confirm image quality at 32, 48, 64, and 96 points, standard and Retina displays, with and without an internet connection.
5. Confirm the five-tab UI and existing migration/file tool actions are unaffected.
