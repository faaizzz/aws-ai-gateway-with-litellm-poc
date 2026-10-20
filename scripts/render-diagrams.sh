#!/usr/bin/env bash
# Render diagrams/*.mmd to SVG.
# Optional overrides: MMDC (mermaid-cli command, default: npx), MMDC_PUPPETEER_CONFIG.
set -euo pipefail
cd "$(dirname "$0")/../diagrams"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
for name in architecture-overview architecture; do
  python3 - "$name" "$tmp" <<'PY'
import base64, re, sys, pathlib
name, tmp = sys.argv[1:3]
src = pathlib.Path(f"{name}.mmd").read_text()
def inline(m):
    data = base64.b64encode(pathlib.Path(m.group(2)).read_bytes()).decode()
    return f"{m.group(1)}data:image/svg+xml;base64,{data}{m.group(3)}"
pathlib.Path(tmp, f"{name}.mmd").write_text(re.sub(r"""(src='|img: ")(icons/[^'"]+)(['"])""", inline, src))
PY
  # shellcheck disable=SC2086
  ${MMDC:-npx -y @mermaid-js/mermaid-cli} ${MMDC_PUPPETEER_CONFIG:+-p "$MMDC_PUPPETEER_CONFIG"} -c mermaid-config.json -i "$tmp/$name.mmd" -o "$name.svg"
  # Mermaid cannot put an icon outside a node, so draw them above their shapes.
  node ../asci-doc/scripts/add-diagram-icons.mjs "$name.svg" "$name.mmd"
  # Opened on its own, the SVG should fit the window instead of scrolling vertically.
  sed -i.bak 's/style="max-width:/style="max-height: 100vh; max-width:/' "$name.svg" && rm -f "$name.svg.bak"
done
