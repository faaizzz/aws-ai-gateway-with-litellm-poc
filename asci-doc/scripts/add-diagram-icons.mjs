// Draw icons centred above their shapes in a rendered Mermaid SVG.
// Usage (from diagrams/): node add-diagram-icons.mjs <name>.svg <name>.mmd
// The .mmd lists the targets as comment lines: `%% icon: <node or subgraph id> icons/<file>.svg` or `emoji:<char>`.
// Mermaid cannot place an image outside a node, so this runs after mmdc.
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import puppeteer from 'puppeteer';

const [svgPath, mmdPath] = process.argv.slice(2);
const SIZE = 56;
const GAP = 6;

const icons = [...fs.readFileSync(mmdPath, 'utf8').matchAll(/^\s*%% icon: (\w+) (\S+)\s*$/gm)].map(
  ([, id, file]) =>
    file.startsWith('emoji:')
      ? { id, emoji: file.slice('emoji:'.length) }
      : { id, href: `data:image/svg+xml;base64,${fs.readFileSync(file).toString('base64')}` },
);

const config = process.env.MMDC_PUPPETEER_CONFIG
  ? JSON.parse(fs.readFileSync(process.env.MMDC_PUPPETEER_CONFIG, 'utf8'))
  : {};
const browser = await puppeteer.launch({ headless: 'shell', ...config });
try {
  const page = await browser.newPage();
  await page.goto(pathToFileURL(path.resolve(svgPath)).href);
  const missing = await page.evaluate(
    (icons, size, gap) => {
      const NS = 'http://www.w3.org/2000/svg';
      const missing = [];
      for (const { id, href, emoji } of icons) {
        // Mermaid prefixes ids with the svg id (e.g. `my-svg-flowchart-ID-3`, `my-svg-ID`).
        const el = [...document.querySelectorAll('g.node, g.cluster')].find((g) =>
          new RegExp(`^[\\w-]*?(flowchart-${id}-\\d+|-${id})$`).test(g.id),
        );
        if (!el) {
          missing.push(id);
          continue;
        }
        const box = el.getBBox();
        let img;
        if (emoji) {
          img = document.createElementNS(NS, 'text');
          img.textContent = emoji;
          img.setAttribute('x', box.x + box.width / 2);
          img.setAttribute('y', box.y - gap - 8);
          img.setAttribute('text-anchor', 'middle');
          img.setAttribute('font-size', size * 0.85);
        } else {
          img = document.createElementNS(NS, 'image');
          img.setAttribute('href', href);
          img.setAttribute('width', size);
          img.setAttribute('height', size);
          img.setAttribute('x', box.x + box.width / 2 - size / 2);
          img.setAttribute('y', box.y - size - gap);
        }
        el.appendChild(img);
      }
      return missing;
    },
    icons,
    SIZE,
    GAP,
  );
  // Icons can poke out above the top row: grow the viewBox to fit everything.
  await page.evaluate(() => {
    const svg = document.documentElement;
    const b = svg.getBBox();
    const [x, y, w, h] = svg.getAttribute('viewBox').split(/\s+/).map(Number);
    const nx = Math.min(x, b.x - 8);
    const ny = Math.min(y, b.y - 8);
    const nw = Math.max(x + w, b.x + b.width + 8) - nx;
    const nh = Math.max(y + h, b.y + b.height + 8) - ny;
    svg.setAttribute('viewBox', `${nx} ${ny} ${nw} ${nh}`);
    svg.style.maxWidth = `${nw}px`;
  });
  if (missing.length) throw new Error(`icon targets not found in ${svgPath}: ${missing.join(', ')}`);
  const xml = await page.evaluate(() => new XMLSerializer().serializeToString(document.documentElement));
  fs.writeFileSync(svgPath, xml);
} finally {
  await browser.close();
}
