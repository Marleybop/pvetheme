#!/usr/bin/env node
// Screenshots the Proxmox VE web UI, optionally with locally built theme files swapped in
// by the browser, so a theme can be developed without installing anything on the node.
//
//   NODE_PATH=<dir with playwright-core>/node_modules node tools/shot.cjs \
//       --host <ssh host> --url https://<node>:8006 --node <node name> --vm qemu/<id> --ct lxc/<id> \
//       --theme marleybop --serve dist/dev/themes --out shots [--only name,name]
//
//   --serve <dir>    answer /pwt/themes/<file> from this folder when the file is there
//   --inject         also append <dir>/marleybop-theme.js to the page (node without the theme installed)
//   --theme <key>    theme cookie; "auto" sends none (the server default applies)
//   --scheme <s>     dark (default) or light: the browser's system setting
//   --options a=b,.. the per-browser options: accent=#6db04a,radius=round,density=compact,font=system
//   --anonymize      replace guest names, addresses and the user name before each shot
//   --scrub a=b,c=d  extra text replacements for --anonymize
//
// Login: a ticket for a password-less read-only user is minted over SSH (root on the node):
//   pveum user add marleybop-theme@pve && pveum acl modify / -user marleybop-theme@pve -role PVEAuditor
const { chromium } = require('playwright-core');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const args = {};
for (let i = 2; i < process.argv.length; i++) {
  const k = process.argv[i].replace(/^--/, '');
  if (i + 1 < process.argv.length && !process.argv[i + 1].startsWith('--')) args[k] = process.argv[++i];
  else args[k] = true;
}
const sshHost = args.host || 'pve';
const base = args.url || 'https://pve.example.lan:8006';
const user = args.user || 'marleybop-theme@pve';
const outDir = path.resolve(args.out || 'shots');
const theme = args.theme || 'proxmox-dark';
const only = args.only ? args.only.split(',') : null;
const serveDir = args.serve ? path.resolve(args.serve) : null;
fs.mkdirSync(outDir, { recursive: true });

const NODE = args.node || 'pve';
const VM = args.vm || 'qemu/100';
const CT = args.ct || 'lxc/101';
const STORAGE = args.storage || `storage/${NODE}/local`;

// name, resource id, tab
const views = [
  ['dc-summary', 'root', 'summary'],
  ['dc-search', 'root', 'search'],
  ['dc-options', 'root', 'options'],
  ['dc-storage', 'root', 'storage'],
  ['dc-backup', 'root', 'backup'],
  ['dc-users', 'root', 'users'],
  ['dc-roles', 'root', 'roles'],
  ['dc-firewall', 'root', 'firewall'],
  ['dc-notes', 'root', 'notes'],
  ['dc-support', 'root', 'support'],
  ['node-summary', `node/${NODE}`, 'summary'],
  ['node-network', `node/${NODE}`, 'network'],
  ['node-tasks', `node/${NODE}`, 'tasks'],
  ['node-services', `node/${NODE}`, 'services'],
  ['node-certs', `node/${NODE}`, 'certificates'],
  ['vm-summary', VM, 'summary'],
  ['vm-hardware', VM, 'hardware'],
  ['vm-options', VM, 'options'],
  ['vm-snapshots', VM, 'snapshot'],
  ['vm-firewall', VM, 'firewall'],
  ['ct-summary', CT, 'summary'],
  ['ct-resources', CT, 'resources'],
  ['ct-network', CT, 'network'],
  ['storage-summary', STORAGE, 'summary'],
  ['storage-content', STORAGE, 'contentIso'],
];

const overlays = {
  'ov-wizard-vm': `Ext.create('PVE.qemu.CreateWizard', { nodename: '${NODE}' }).show()`,
  'ov-wizard-ct': `Ext.create('PVE.lxc.CreateWizard', { nodename: '${NODE}' }).show()`,
  'ov-theme': `Ext.create('Proxmox.window.ThemeEditWindow', { cookieName: 'PVEThemeCookie', autoShow: true })`,
  'ov-msg': `Ext.Msg.show({ title: 'Confirm', icon: Ext.Msg.WARNING, msg: 'Are you sure you want to remove entry 101?', buttons: Ext.Msg.YESNO })`,
  'ov-error': `Ext.Msg.alert('Error', 'Connection error 500: unable to open file - Permission denied')`,
  'ov-usermenu': `(() => { const b = Ext.ComponentQuery.query('button').find(x => x.menu && /@/.test(x.getText() || '')); b.showMenu(); })()`,
  'ov-treemenu': `(() => { const t = Ext.ComponentQuery.query('pveResourceTree')[0]; const r = t.getStore().findNode('id', '${VM}'); const m = Ext.create('PVE.qemu.CmdMenu', { pveSelNode: r, nodename: '${NODE}' }); m.showAt(260, 300); })()`,
  'ov-backupjob': `Ext.create('PVE.dc.BackupEdit', { autoShow: true })`,
  'ov-combo': `(() => { const w = Ext.create('PVE.qemu.CreateWizard', { nodename: '${NODE}' }); w.show(); const tp = w.down('tabpanel'); tp.setActiveTab(1); setTimeout(() => { const c = w.query('combobox').filter(x => x.isVisible(true))[0]; if (c) { c.focus(); c.expand(); } }, 600); })()`,
  'ov-forms': `(() => { const w = Ext.create('Ext.window.Window', { title: 'Controls', width: 420, bodyPadding: 12, layout: 'anchor', defaults: { anchor: '100%' }, items: [
      { xtype: 'textfield', fieldLabel: 'Text', value: 'hello' }, { xtype: 'textfield', fieldLabel: 'Invalid', allowBlank: false, value: '' },
      { xtype: 'numberfield', fieldLabel: 'Number', value: 4 }, { xtype: 'datefield', fieldLabel: 'Date', value: new Date(2026, 0, 15) },
      { xtype: 'checkbox', boxLabel: 'Checked box', checked: true }, { xtype: 'checkbox', boxLabel: 'Empty box' },
      { xtype: 'radiogroup', fieldLabel: 'Radio', items: [{ boxLabel: 'One', name: 'r', checked: true }, { boxLabel: 'Two', name: 'r' }] },
      { xtype: 'progressbar', value: 0.6, text: '60%' }, { xtype: 'textarea', fieldLabel: 'Notes', value: 'line one', height: 60 } ],
      buttons: [{ text: 'Cancel', ui: 'default-toolbar' }, { text: 'OK' }] }); w.show(); w.down('textfield[allowBlank=false]').validate(); })()`,
};

// Runs in the page: swaps names and addresses in the visible text for generic ones.
function anonymise(extra) {
  const pool = ['web-01', 'db-01', 'proxy', 'git', 'media', 'dns', 'vpn', 'mail', 'monitor', 'backup', 'build-01', 'cache', 'files', 'auth', 'wiki', 'home', 'lab-01', 'lab-02', 'ci-runner', 'registry', 'search', 'queue', 'metrics', 'docs', 'staging', 'sandbox'];
  if (!window.__mbMap) {
    const map = [];
    let n = 0;
    const seen = {};
    try {
      PVE.data.ResourceStore.each(r => {
        const name = r.get('name');
        if ((r.get('type') === 'qemu' || r.get('type') === 'lxc') && name && !seen[name]) { seen[name] = 1; map.push([name, pool[n++ % pool.length]]); }
      });
    } catch (e) { /* not logged in yet */ }
    map.sort((a, b) => b[0].length - a[0].length);
    if (Proxmox.NodeName) map.push([Proxmox.NodeName, 'pve1']);
    if (Proxmox.UserName) map.unshift([Proxmox.UserName, 'admin@pve']);
    (extra || []).forEach(p => map.unshift(p));
    window.__mbMap = map.map(([from, to]) => [new RegExp(from.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'gi'), to]);
  }
  const fix = s => {
    let out = s;
    window.__mbMap.forEach(([re, to]) => { out = out.replace(re, to); });
    out = out.replace(/\b(?:10|172|192)\.\d{1,3}\.\d{1,3}\.(\d{1,3})\b/g, '192.0.2.$1');
    out = out.replace(/\b([0-9A-F]{2}:){5}[0-9A-F]{2}\b/gi, 'BC:24:11:00:00:01');
    out = out.replace(/\benx[0-9a-f]{12}\b/g, 'enp3s0');
    return out;
  };
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  let node;
  while ((node = walker.nextNode())) {
    const v = fix(node.nodeValue);
    if (v !== node.nodeValue) node.nodeValue = v;
  }
  document.querySelectorAll('input, textarea').forEach(i => { const v = fix(i.value || ''); if (v !== i.value) i.value = v; });
}

(async () => {
  const perl = `perl -MPVE::AccessControl -e 'print PVE::AccessControl::assemble_ticket(shift)' '${user}'`;
  const ticket = execFileSync('ssh', ['-o', 'BatchMode=yes', sshHost, perl], { encoding: 'utf8' }).trim();
  const browser = await chromium.launch({ channel: args.channel || 'msedge', headless: true });
  const host = new URL(base).hostname;
  const scrub = args.scrub ? String(args.scrub).split(',').map(p => p.split('=')) : [];
  const types = { '.css': 'text/css', '.js': 'application/javascript', '.woff2': 'font/woff2' };

  async function context(loggedIn) {
    const ctx = await browser.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1600, height: 1000 }, colorScheme: args.scheme || 'dark' });
    // --theme auto leaves the cookie out: the server default applies
    const cookies = theme === 'auto' ? [] : [{ name: 'PVEThemeCookie', value: theme, domain: host, path: '/', secure: true }];
    if (loggedIn) cookies.push({ name: 'PVEAuthCookie', value: ticket, domain: host, path: '/', secure: true });
    if (cookies.length) await ctx.addCookies(cookies);
    if (serveDir) {
      await ctx.route(/\/pwt\/themes\/[^/?]+/, r => {
        const name = path.basename(new URL(r.request().url()).pathname);
        const f = path.join(serveDir, name);
        return fs.existsSync(f)
          ? r.fulfill({ status: 200, contentType: types[path.extname(name)] || 'application/octet-stream', body: fs.readFileSync(f) })
          : r.continue();
      });
      const helper = path.join(serveDir, 'marleybop-theme.js');
      if (args.inject && fs.existsSync(helper)) {
        await ctx.route(/\/pve2\/js\/pvemanagerlib\.js/, async r => {
          const resp = await r.fetch();
          await r.fulfill({ response: resp, body: (await resp.text()) + '\n' + fs.readFileSync(helper, 'utf8') });
        });
      }
    }
    return ctx;
  }
  const want = n => !only || only.some(o => n === o || n.startsWith(o));
  // The UI polls all the time, so "network idle" never comes: wait a fixed time.
  const settle = (page, ms = 1500) => page.waitForTimeout(ms);
  const snap = async (page, name) => {
    if (args.anonymize) await page.evaluate(anonymise, scrub).catch(e => console.error('anonymise:', e.message));
    await page.screenshot({ path: path.join(outDir, name + '.png') });
    console.log('shot', name);
  };

  if (want('login')) {
    const ctx = await context(false);
    const page = await ctx.newPage();
    await page.goto(base + '/', { waitUntil: 'domcontentloaded' });
    await settle(page, 2500);
    await page.screenshot({ path: path.join(outDir, 'login.png') });
    await ctx.close();
  }

  const ctx = await context(true);
  const page = await ctx.newPage();
  page.on('pageerror', e => { if (!/Mapping\.Audit/.test(e.message)) console.error('pageerror:', e.message); });
  page.on('console', m => { if (m.type() === 'warning' && /Marleybop/.test(m.text())) console.error('console:', m.text()); });
  const ready = () => page.waitForFunction(() => window.Ext && Ext.ComponentQuery && Ext.ComponentQuery.query('pveResourceTree').length > 0, null, { timeout: 30000 });
  await page.goto(base + '/', { waitUntil: 'domcontentloaded' });
  await ready();
  await settle(page, 2500);
  // A cookie-only login renders before the capability list arrives (stock race);
  // it is cached in localStorage, so a second load builds the UI properly.
  if (args.options) {
    // --options accent=#6db04a,radius=round,density=compact,font=system
    const o = Object.fromEntries(String(args.options).split(',').map(p => p.split('=')));
    await page.evaluate(v => window.localStorage.setItem('marleybop-theme-options', v), JSON.stringify(o));
  }
  await page.reload({ waitUntil: 'domcontentloaded' });
  await ready();
  await settle(page, 2500);
  await page.evaluate(() => { Ext.ComponentQuery.query('pveResourceTree')[0].expandAll(); });
  console.log('ui ready');

  for (const [name, rid, tab] of views) {
    if (!want(name)) continue;
    const ok = await page.evaluate(([rid, tab]) => {
      const tree = Ext.ComponentQuery.query('pveResourceTree')[0];
      const rec = tree.getStore().findNode('id', rid);
      if (!rec) return 'no node ' + rid;
      tree.setSelection(rec);
      return new Promise(res => setTimeout(() => {
        try {
          const panels = Ext.ComponentQuery.query('pvePanelConfig');
          const panel = panels.find(p => p.rendered && p.isVisible(true)) || panels[panels.length - 1];
          if (!panel) return res('no panel');
          // Cards are created lazily; PVE.panel.Config takes the card's itemId.
          if (!panel.savedItems || !(tab in panel.savedItems)) {
            if (!panel.down('#' + tab)) return res('no tab ' + tab);
          }
          panel.selectById(tab);
          res('ok');
        } catch (e) { res('error ' + e.message); }
      }, 400));
    }, [rid, tab]);
    if (ok !== 'ok') { console.error(name, ok); continue; }
    await settle(page, name.includes('summary') ? 3500 : 1500);
    await snap(page, name);
  }

  for (const [name, js] of Object.entries(overlays)) {
    if (!want(name)) continue;
    try {
      await page.evaluate('void (' + js + ')');
      await settle(page, 1200);
      await snap(page, name);
    } catch (e) { console.error(name, e.message.split('\n')[0]); }
    await page.evaluate(() => {
      Ext.Msg.hide();
      Ext.ComponentQuery.query('window').forEach(w => { try { w.close ? w.close() : w.hide(); } catch (e) {} });
      Ext.ComponentQuery.query('menu').forEach(m => m.hide());
    }).catch(() => {});
    await page.waitForTimeout(300);
  }

  if (args.evalfile) args.eval = fs.readFileSync(path.resolve(args.evalfile), 'utf8');
  if (args.eval) console.log(JSON.stringify(await page.evaluate(args.eval), null, 1));
  await browser.close();
})().catch(e => { console.error(e); process.exit(1); });
