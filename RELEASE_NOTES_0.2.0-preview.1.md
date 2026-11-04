# LibreReplace v0.2.0-preview.1

**Explore open-source replacements for paid Mac apps before you switch.**

### What's new
- Browse **45 commercial applications** and **70 open-source comparisons**, even if the paid app is not installed.
- Pick the exact capabilities you need to keep. See **Strong / Partial / Keep**, source links and known gaps.
- Better app detection with **55 researched macOS bundle-ID mappings** (not all independently verified on real app installations).
- Cleaner potential-savings estimate: curated free desktop alternatives such as GIMP default to $0 in recurring software costs. Hosted/paid-plan alternatives are excluded when their costs are unknown.
- Matching, installation and migration safety fixes; local privacy-first scanning remains unchanged.

### Important limits
This is an **open-source preview**, not an assertion of identical app or document compatibility. The estimate is not money already saved; confirm migration before cancelling. No Spotify subscription streaming equivalent is provided.

The downloadable Mac app is **ad-hoc signed but not Apple Developer ID signed or notarized**. macOS 14+ is required. If Gatekeeper blocks the downloaded preview, see Apple's per-app approval interface; no command to weaken Gatekeeper is recommended. Alternatively, build from source with `./Scripts/install_local.sh`.

The DMG SHA-256 and exact source commit are documented in the release assets / provenance produced by the local release command.

**Binary platform:** packaged DMG built for Apple Silicon (arm64); Intel Macs can build from source.
