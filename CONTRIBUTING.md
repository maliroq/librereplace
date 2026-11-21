# Build a better free Mac workflow with us

The most exciting LibreReplace contributions answer one simple question: **How can someone do this work with free software?**

There are lots of ways to help, from one excellent catalog correction to a complete, repeatable Community setup.

## Share an alternative that deserves attention

Found a great free app? Tell us which paid app it can help replace, which features you tried, the macOS version you used and any steps that made the workflow click. Strong contributions include links to product documentation and clear notes on supported features.

## Build a Community recipe

Use Discover to select a source app, choose what's essential and assemble a free setup. Export the recipe, describe the steps and submit it for review. A good recipe gives another Mac user something they can understand and reproduce.

[How to contribute a Community build](Docs/STUDIO_COMMUNITY_BUILD_GUIDE.md) · [Recipe format](Docs/STUDIO_RECIPE_V1.md)

## Improve the app

SwiftUI polish, accessibility, workflow tools, performance, catalog coverage, migrations, tests and documentation are all welcome. We value changes that make the product easier for a nontechnical person to use.

Run the portable checks:

```bash
make check
```

For native macOS changes, also run:

```bash
python3 dev.py --non-interactive --no-launch
```

`project.yml` generates the Xcode project. Keep installation approval, file access and migration backups intact as you improve the experience.

**Have a promising idea?** [Open an issue](https://github.com/maliroq/librereplace/issues) and show what it would help people accomplish.
