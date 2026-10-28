# Real demo capture

The public hero and demo must use real scan results. Do not hard-code demo recommendations, alter the catalog for marketing, or fabricate screenshots.

## Recommended real demo: Sublime Text → Zed

Sublime Text is a commercial application that can be evaluated without a purchased license. Its current stable macOS build is also available through the Homebrew `sublime-text` cask.

On the validation Mac:

```bash
brew install --cask sublime-text
open -a "Sublime Text"
```

In Sublime Text, open **Settings → Settings** and add a small, disposable preference set so the existing migration preview has real input:

```json
{
  "font_size": 14,
  "font_face": "Menlo",
  "tab_size": 4,
  "translate_tabs_to_spaces": true
}
```

Save the file. These are ordinary editor preferences; no project or document content is required.

Then relaunch LibreReplace or press **Command-R** to rescan. Open **Detected → Sublime Text** and verify that the detail view shows:

- Sublime Text as the detected source app;
- Zed as the recommended alternative;
- weighted feature coverage;
- Keeps / Partial / Missing sections;
- Known limitations;
- dated evidence links;
- the optional Sublime Text → Zed migration section.

The repository hero at `Docs/Images/hero-sublime-zed.png` is a crop of a real validation-Mac capture using this workflow. It contains no fabricated recommendation state.

When recapturing it, size the LibreReplace window to roughly 1120×760 and capture the app window only. Do not include the desktop, username, Terminal, menu-bar personal information, or unrelated applications. A simple macOS capture path is **Shift-Command-4**, then press **Space**, then click the LibreReplace window.

## 20–30 second screen recording storyboard

No face or narration is required.

1. **0–4 s — Local scan:** launch LibreReplace; show the scan finishing.
2. **4–10 s — Detected source app:** open Sublime Text from Detected and pause on the Zed recommendation.
3. **10–16 s — Tradeoffs:** scroll through Keeps, Partial, Missing, and Known limitations.
4. **16–20 s — Evidence:** expand Evidence long enough to show source links and verification dates.
5. **20–25 s — Safe migration:** click Preview migration and show the four proposed preference mappings; do not apply during the public demo unless using disposable settings.
6. **25–30 s — Safety:** show the install confirmation, then cancel. End on the local-only/privacy message.

## Short GIF storyboard

Keep the GIF under about 10 seconds and focus on one interaction:

- Detected → Sublime Text;
- Zed recommendation appears;
- quick scroll from Keeps to Missing;
- Preview migration opens.

Avoid looping installation, rollback, or modal confirmation interactions in the GIF; they are clearer in the full recording.
