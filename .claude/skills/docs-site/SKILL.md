---
name: docs-site
description: Add or change pages on the Antora docs site (asci-doc/) in this repo, build it locally, and publish it.
---

# Docs site (asci-doc)

Markdown in the repo is the source of truth; `asci-doc/scripts/md_to_adoc.py` converts it to AsciiDoc at build time.

## Add a page
1. Add `"<repo path>.md": "<page-name>"` to `MANIFEST` in `asci-doc/scripts/md_to_adoc.py`. `CLAUDE.md` is deliberately not in it.
2. Add an `xref:repo/<page-name>.adoc[Title]` line to `asci-doc/docs/modules/ROOT/nav.adoc`.
3. Use repo-relative links in the Markdown; the converter rewrites them to site xrefs or repo URLs.

## Build
```bash
cd asci-doc && npm ci && cd ..       # first time
asci-doc/scripts/build.sh            # needs kramdoc (kramdown-asciidoc gem)
open asci-doc/build/site/index.html
```
The build requires zero Antora warnings (`--log-failure-level=warn`). It re-renders diagrams and overwrites `diagrams/*.svg`; run `git checkout diagrams/*.svg` if that wasn't intended.

## Rules
- Run `python3 tests/policy/doc_path_refs.py`: no dead file paths or bare `*.tf` mentions in any doc.
- No internal tracker/story IDs in reader-facing docs.
- Publish only via the manual `docs-publish.yml` workflow on `main` (S3 + CloudFront). Confirm with the user before dispatching.
