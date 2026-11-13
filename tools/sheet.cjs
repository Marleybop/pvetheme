#!/usr/bin/env node
// Makes one contact sheet (a grid of thumbnails) from a list of screenshots, so many themes
// can be checked or shown at once.
//   node tools/sheet.cjs out.png 4 label1=a.png label2=b.png ...     (4 = columns)
const { chromium } = require('playwright-core');
const fs = require('fs');
const path = require('path');

const [out, cols, ...items] = process.argv.slice(2);
(async () => {
  const cells = items.map(i => {
    const [label, file] = i.split('=');
    const data = fs.readFileSync(path.resolve(file)).toString('base64');
    return `<figure><img src="data:image/png;base64,${data}"><figcaption>${label}</figcaption></figure>`;
  }).join('');
  const html = `<style>body{margin:0;padding:16px;background:#111214;font:600 15px system-ui;color:#f6f5f2}
    .g{display:grid;grid-template-columns:repeat(${cols},1fr);gap:14px}figure{margin:0}img{width:100%;display:block;border-radius:6px;border:1px solid #3a3e44}
    figcaption{padding:6px 2px 0}</style><div class="g">${cells}</div>`;
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  const page = await browser.newPage({ viewport: { width: 520 * Number(cols), height: 800 } });
  await page.setContent(html);
  await page.screenshot({ path: path.resolve(out), fullPage: true });
  await browser.close();
})().catch(e => { console.error(e); process.exit(1); });
