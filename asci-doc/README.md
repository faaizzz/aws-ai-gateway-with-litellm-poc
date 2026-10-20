# `asci-doc`

An [Antora](https://antora.org) site that publishes the repo's documentation and the architecture diagrams as one navigable website. The Markdown files stay the single source of truth: they are converted to AsciiDoc at build time and the result is not committed.

## What is hand-written and what is generated

| Path | Kind |
|---|---|
| `antora-playbook.yml`, `asci-doc/docs/antora.yml` | Hand-written. Site and component config. |
| `asci-doc/docs/modules/ROOT/nav.adoc`, the landing page and the diagrams page | Hand-written. |
| the `repo/` pages folder, the `images/` folder, `build/`, `node_modules/` | Generated, gitignored. |

`asci-doc/scripts/md_to_adoc.py` holds the manifest of Markdown files that become pages (`CLAUDE.md` is deliberately not one). It runs `kramdoc`, then rewrites links: links between published files become `xref:`, other repo paths (Terraform files, YAML, directories) point at GitHub, and the diagram files point at the diagrams page.

## Build locally

Needs Node 20+, Ruby, Python 3 and the `kramdown-asciidoc` gem (CI pins `2.1.1`).

```bash
gem install kramdown-asciidoc -v 2.1.1
cd asci-doc && npm ci && cd ..
asci-doc/scripts/build.sh
open asci-doc/build/site/index.html
```

The build re-renders both diagrams from `diagrams/*.mmd` with the pinned `mermaid-cli`, so it overwrites the committed `diagrams/*.svg` in your working tree. Run `git checkout diagrams/*.svg` if you did not mean to change them. On Linux CI, set `MMDC_PUPPETEER_CONFIG=asci-doc/puppeteer-config.json` (Chrome cannot use its sandbox there).

Antora runs with `--log-failure-level=warn`, so a broken xref fails the build. The site URL comes from `DOCS_SITE_URL` (default `https://localhost`); Antora only writes `404.html` when the site has a URL.

## Publishing

`.github/workflows/docs-publish.yml` is manual only. It builds the site and, with `publish=true` on `main`, syncs it to a private S3 bucket behind CloudFront using the `github-actions-docs` OIDC role. Hosting and setup: `terraform/bootstrap/README.md` ("Docs site"). Workflow inputs and settings: `docs/ci.md`.

## Add a page

1. Add the Markdown file to `MANIFEST` in `asci-doc/scripts/md_to_adoc.py`.
2. Add an `xref:` line to `asci-doc/docs/modules/ROOT/nav.adoc`.
3. Build and check that Antora prints no warnings.

## Known limits

- Mermaid code blocks inside the Markdown (for example in the bootstrap README) show as source, not as rendered diagrams. Only the two architecture diagrams are rendered.
- Default Antora UI with the placeholder navbar links removed (`asci-doc/supplemental-ui`). Search is client-side via `@antora/lunr-extension` (index built with the site, no server).
