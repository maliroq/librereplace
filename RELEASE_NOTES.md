# LibreReplace v0.1.0-preview.1

**Replace paid Mac apps without losing what matters.**

LibreReplace starts from supported commercial apps already installed on your Mac and shows evidence-backed open-source alternatives with explicit gains, losses, and conservative Strong / Partial / Keep outcomes.

## Install

Recommended no-cost route:

```bash
git clone https://github.com/maliroq/LibreReplace.git
cd LibreReplace
./Scripts/install_local.sh
```

A downloadable Release DMG is also provided for convenience. It is **ad-hoc signed**, **not Developer ID signed**, and **not Apple-notarized**. The release record publishes the exact source commit and DMG SHA-256.

If macOS blocks the downloaded preview, users who independently decide to trust it may use Apple's normal per-app **System Settings → Privacy & Security → Open Anyway** process after first trying to open LibreReplace. No Gatekeeper-disable or quarantine-removal command is supported.

LibreReplace remains local-only, has no account or telemetry, never automatically removes an existing app, and keeps its narrow migration preview-first, backup-verified, and rollback-capable.
