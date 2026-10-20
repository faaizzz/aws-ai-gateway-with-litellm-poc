#!/usr/bin/env python3
"""Convert the repo's Markdown docs to AsciiDoc pages for Antora (build time).

Markdown stays the source of truth. Each file in MANIFEST is converted with
`kramdoc` (kramdown-asciidoc) into pages/repo/<name>.adoc, then its links are
rewritten so they resolve inside the site or point at the repo on GitHub.
The generated pages are gitignored.

    python3 asci-doc/scripts/md_to_adoc.py
"""

from __future__ import annotations

import os
import posixpath
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = REPO_ROOT / "asci-doc/docs/modules/ROOT/pages/repo"
IMAGES_DIR = REPO_ROOT / "asci-doc/docs/modules/ROOT/images"
MMDC = REPO_ROOT / "asci-doc/node_modules/.bin/mmdc"

# source (repo-relative) -> page name. CLAUDE.md is deliberately absent.
MANIFEST = {
    "README.md": "overview",
    "design.md": "design",
    "architecture.md": "architecture",
    "docs/model-analysis.md": "model-analysis",
    "data/README.md": "data-readme",
    "docs/ci.md": "ci",
    "docs/known-limitations.md": "known-limitations",
    "docs/demo-runtime-evidence.md": "demo-runtime-evidence",
    "terraform/modules/use-case/README.md": "module-use-case",
    "terraform/modules/llm-gateway/README.md": "module-llm-gateway",
    "terraform/modules/use-case-observability/README.md": "module-use-case-observability",
    "terraform/bootstrap/README.md": "bootstrap",
    "terraform/environments/dev/README.md": "env-dev",
}

REPO_URL = "{repo-url}/blob/main"
TREE_URL = "{repo-url}/tree/main"

XREF = re.compile(r"xref:([^\[\s]+?)\.adoc(#[^\[\s]*)?\[")
LINK = re.compile(r"link:([^\[\s]+)\[")
IMAGE = re.compile(r"image::([^\[\s]+)\[")
MERMAID_BLOCK = re.compile(r"^\[mermaid\]\n\.\.\.\.\n(.*?)\n\.\.\.\.$", re.S | re.M)
MERMAID_SOURCE = re.compile(r"^\[source,mermaid\]\n----\n(.*?)\n----$", re.S | re.M)


def resolve(src: str, target: str) -> str:
    """Repo-relative path of `target`, written relative to the file `src`."""
    return posixpath.normpath(posixpath.join(posixpath.dirname(src), target))


def page_for(path: str) -> str | None:
    return MANIFEST.get(path)


def rewrite_xref(src: str, m: re.Match) -> str:
    path = resolve(src, m.group(1) + ".md")
    anchor = m.group(2) or ""
    page = page_for(path)
    if page:
        return f"xref:repo/{page}.adoc{anchor}["
    # A .md that is not published (e.g. CLAUDE.md): point at GitHub.
    return f"link:{REPO_URL}/{path}{anchor}["


def rewrite_link(src: str, m: re.Match) -> str:
    target = m.group(1)
    if re.match(r"^[a-z][a-z0-9+.-]*:", target) or target.startswith("#"):
        return m.group(0)
    path_part, _, anchor = target.partition("#")
    anchor = f"#{anchor}" if anchor else ""
    path = resolve(src, path_part)
    if path.startswith("diagrams/") and path.endswith((".svg", ".mmd")):
        return "xref:diagrams.adoc["
    page = page_for(path)
    if page:
        return f"xref:repo/{page}.adoc{anchor}["
    is_dir = path_part.endswith("/") or not Path(path).suffix
    base = TREE_URL if is_dir else REPO_URL
    return f"link:{base}/{path}{anchor}["


def rewrite_image(src: str, m: re.Match) -> str:
    path = resolve(src, m.group(1))
    if path.startswith("diagrams/") and path.endswith(".svg"):
        return f"image::{posixpath.basename(path)}["
    return m.group(0)


def render_mermaid(name: str, text: str) -> str:
    """Render each ```mermaid block to an SVG image with the pinned mermaid-cli."""
    counter = 0

    def render(m: re.Match) -> str:
        nonlocal counter
        counter += 1
        image = f"{name}-diagram-{counter}.svg"
        IMAGES_DIR.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory() as tmp:
            mmd = Path(tmp) / "in.mmd"
            mmd.write_text(m.group(1) + "\n", encoding="utf-8")
            cmd = [str(MMDC), "-i", str(mmd), "-o", str(IMAGES_DIR / image)]
            config = os.environ.get("MMDC_PUPPETEER_CONFIG")
            if config:
                cmd += ["-p", str((REPO_ROOT / config).resolve())]
            subprocess.run(cmd, check=True, cwd=REPO_ROOT)
        return f"image::{image}[Diagram {counter}]"

    return MERMAID_SOURCE.sub(render, text)


def convert(src: str, name: str) -> None:
    out = OUT_DIR / f"{name}.adoc"
    subprocess.run(
        ["kramdoc", "-o", str(out), str(REPO_ROOT / src)],
        check=True,
        cwd=REPO_ROOT,
    )
    text = out.read_text(encoding="utf-8")
    text = XREF.sub(lambda m: rewrite_xref(src, m), text)
    text = LINK.sub(lambda m: rewrite_link(src, m), text)
    text = IMAGE.sub(lambda m: rewrite_image(src, m), text)
    text = MERMAID_BLOCK.sub(lambda m: f"[source,mermaid]\n----\n{m.group(1)}\n----", text)
    text = render_mermaid(name, text)
    out.write_text(text, encoding="utf-8")


def main() -> int:
    if shutil.which("kramdoc") is None:
        print("kramdoc not found: gem install kramdown-asciidoc", file=sys.stderr)
        return 1
    if OUT_DIR.exists():
        shutil.rmtree(OUT_DIR)
    OUT_DIR.mkdir(parents=True)
    for src, name in MANIFEST.items():
        if not (REPO_ROOT / src).is_file():
            print(f"missing source: {src}", file=sys.stderr)
            return 1
        convert(src, name)
    print(f"converted {len(MANIFEST)} page(s) into {OUT_DIR.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
