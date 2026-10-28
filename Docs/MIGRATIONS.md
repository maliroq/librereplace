# Migration adapters

Migration is optional and independent from recommendation ranking. The preview release contains one adapter only.

Every adapter must be:

1. **detectable** — check only its documented source state;
2. **preview-first** — enumerate the exact intended changes without writing;
3. **path constrained** — use reviewed source/target paths and reject symlink redirection;
4. **backup-first** — byte-verify any backup before modifying existing target state;
5. **stale-plan safe** — refuse to apply when the target changed after preview;
6. **verified** — read the result back and confirm the intended output;
7. **rollback-capable** — restore the previous bytes, or remove a target created by the migration;
8. **explicit about limits** — state what is not migrated.

## Preview adapter: Sublime Text → Zed

Supported mappings:

| Sublime preference | Zed preference |
|---|---|
| `font_size` | `buffer_font_size` |
| `font_face` | `buffer_font_family` |
| `tab_size` | `tab_size` |
| `translate_tabs_to_spaces` | inverse of `hard_tabs` |

The adapter preserves unrelated Zed JSON keys. Existing target settings are backed up under `~/Library/Application Support/LibreReplace/Backups` before modification. JSON comments in the target may be lost because the file is parsed and re-serialized; the preview warns about this.

It does **not** migrate plugins, packages, projects, snippets, keybindings, themes, recent files, document contents, credentials, passwords, Keychain data, or browser data.
