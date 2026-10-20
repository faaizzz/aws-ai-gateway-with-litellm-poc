#!/usr/bin/env bash
# Build the Antora site into asci-doc/build/site (local and CI entry point).
# Needs: node + `npm ci` in asci-doc, and the kramdown-asciidoc gem (kramdoc).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cd "$here/../.."
root="$PWD"

# Render the diagrams fresh from the .mmd sources with the pinned mermaid-cli.
# render-diagrams.sh runs from diagrams/, so make the puppeteer config absolute.
if [[ -n "${MMDC_PUPPETEER_CONFIG:-}" && "$MMDC_PUPPETEER_CONFIG" != /* ]]; then
  export MMDC_PUPPETEER_CONFIG="$root/$MMDC_PUPPETEER_CONFIG"
fi
MMDC="$root/asci-doc/node_modules/.bin/mmdc" ./scripts/render-diagrams.sh
content=asci-doc/docs
images="$content/modules/ROOT/images"
mkdir -p "$images"
cp diagrams/*.svg "$images/"

python3 "$here/md_to_adoc.py"

cd asci-doc
# Antora only emits 404.html when the site has a URL. DOCS_SITE_URL is the
# CloudFront URL in CI; the default is a placeholder for local builds.
npx antora --log-failure-level=warn --url "${DOCS_SITE_URL:-https://localhost}" antora-playbook.yml
echo "Site: asci-doc/build/site/index.html"
