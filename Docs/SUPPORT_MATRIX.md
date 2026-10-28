# Support matrix

Verified against the catalog evidence on **2026-10-27**. Coverage is the catalog's weighted score for the listed capabilities; it is not a claim of universal workflow parity, polish, performance, accessibility, privacy, or support quality. `Keep` means the catalog does not currently support switching for the defined critical workflow.

| Commercial app | Catalog alternative | Result | Weighted coverage | Verified minimum macOS for alternative | Migration |
|---|---|---:|---:|---:|---|
| CleanShot X | Snapzy | Strong | 95% | 13.0 | — |
| Bartender | Ice | Partial | 62% | 14.0 | — |
| DaisyDisk | OpenDisk | Strong | 100% | 14.0 | — |
| CleanMyMac | Dusty | Partial | 58% | — | — |
| Paste | Maccy | Partial | 72% | 14.0 | — |
| Magnet | Rectangle | Strong | 100% | 14.0 | — |
| Moom | Rectangle | Partial | 74% | 14.0 | — |
| Little Snitch | LuLu | Partial | 82% | 10.15 | — |
| iStat Menus | Stats | Strong | 100% | 12.0 | — |
| BetterTouchTool | Hammerspoon | Partial | 76% | 13.0 | — |
| Keyboard Maestro | Hammerspoon | Partial | 56% | 13.0 | — |
| Parallels Desktop | UTM | Partial | 72% | — | — |
| Transmit | Cyberduck | Partial | 79% | — | — |
| Tower | GitHub Desktop | Partial | 79% | 13.0 | — |
| Sublime Text | Zed | Strong | 89% | — | Sublime → Zed settings |
| TablePlus | Beekeeper Studio Community Edition | Strong | 100% | 12.0 | — |
| Paw / RapidAPI for Mac | Bruno | Strong | 100% | — | — |
| Ulysses | Zettlr | Partial | 74% | 12.0 | — |
| Bear | Joplin | Strong | 100% | 12.0 | — |
| MindNode | Freeplane | Partial | 71% | — | — |
| PDF Expert | Skim | Keep | 41% | 10.13 | — |
| Adobe Photoshop | GIMP | Partial | 68% | 11.0 | — |
| Adobe Illustrator | Inkscape | Partial | 82% | — | — |
| Adobe Premiere Pro | Kdenlive | Partial | 71% | 13.0 | — |
| Adobe Acrobat Pro | LibreOffice Draw | Keep | 31% | — | — |

## Reading the result

- **Strong**: weighted coverage clears the app-specific strong threshold, all required critical capabilities are present, and the supporting evidence is fresh.
- **Partial**: the alternative is useful but the catalog records meaningful missing or partial workflow coverage.
- **Keep**: coverage is below the partial threshold or the defined workflow has critical gaps severe enough that LibreReplace does not recommend switching.

Minimum macOS is shown only where a current first-party or installation source was verified. A dash means LibreReplace does not currently make a minimum-version claim.

For the actual capability states, limitations, evidence URLs, and verification dates, inspect [`Catalog/catalog.json`](../Catalog/catalog.json).
