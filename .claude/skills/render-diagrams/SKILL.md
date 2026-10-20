---
name: render-diagrams
description: Edit and regenerate the Mermaid architecture diagrams (diagrams/*.mmd -> *.svg) in this repo, keeping them readable on GitHub dark mode and consistent with the code.
---

# Architecture diagrams

Files: `diagrams/architecture.mmd` (detailed), `diagrams/architecture-overview.mmd` (one screen), `diagrams/mermaid-config.json` (spacing, local render only), generated `*.svg`, `diagrams/icons/`.

## Editing `.mmd` conventions
- Frontmatter first: `---\nconfig:\n  theme: neutral\n---`.
- Everything sits inside a `CANVAS` subgraph with `style CANVAS fill:#ffffff,stroke:none`: Mermaid can't set a page background, so this keeps GitHub dark mode readable.
- Include the legend. Built = solid, thick border; target-only = dashed and dimmed (`classDef target`); AWS = orange border + icon; non-AWS = grey.
- Icons: `%% icon: NODEID icons/x.svg` or `emoji:` comment lines; they are drawn after rendering.
- Target-state diagram: gateway, both providers, Langfuse (traces/content) vs Datadog (derived metrics only), Postgres request log / audit path, and the use-case onboarding module. Datadog is target state only. Keep both `.mmd` files consistent with each other and with `architecture.md`.

## Regenerate
```bash
MMDC="$PWD/asci-doc/node_modules/.bin/mmdc" ./scripts/render-diagrams.sh
```
It inlines icons, runs `mmdc` with `mermaid-config.json`, runs `asci-doc/scripts/add-diagram-icons.mjs`, and adds `max-height`. Use the pinned `mmdc` so output matches the docs build. If `asci-doc/node_modules` is missing: `npm ci` in `asci-doc`.

Then commit the `.mmd` and `.svg` together. `asci-doc/scripts/build.sh` re-renders too and overwrites the committed SVGs; `git checkout diagrams/*.svg` if that wasn't intended.

## Check
Render a PNG on a dark background (`mmdc ... -b '#0d1117'`) and look at it; confirm `git status` shows only intended files.
