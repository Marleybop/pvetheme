#!/usr/bin/env node
// Screenshots the Proxmox VE web UI with a theme stylesheet swapped in locally,
// so a theme can be developed without touching the host.
//
//   NODE_PATH=<dir with playwright-core>/node_modules node tools/shot.cjs \
//       --css dist/theme-marleybop.css --out shots [--only name,name]
//       --host <ssh host> --url https://<node>:8006 --node <node name> --vm qemu/<id> --ct lxc/<id>
//
// Without --css the UI is captured as installed on the host (--theme picks the theme cookie).
// Login: a ticket for a password-less read-only user is minted over SSH (root on the node).
const { chromium } = require('playwright-core');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const args = {};
for (let i = 2; i < process.argv.length; i += 2) args[process.argv[i].replace(/^--/, '')] = process.argv[i + 1];
const sshHost = args.host || 'pve';
const base = args.url || 'https://pve.example.lan:8006';
const user = args.user || 'marleybop-theme@pve';
const outDir = path.resolve(args.out || 'shots');
const theme = args.theme || 'proxmox-dark';
const only = args.only ? args.only.split(',') : null;
const cssFile = args.css ? path.resolve(args.css) : null;
const fontDir = args.fonts ? path.resolve(args.fonts) : null;
fs.mkdirSync(outDir, { recursive: true });

const NODE = args.node || 'pve';
const VM = args.vm || 'qemu/100';
const CT = args.ct || 'lxc/101';
const STORAGE = args.storage || `storage/${NODE}/local`;

// name, resource id, tab, optional async extra(page)
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
  ['node-disks', `node/${NODE}`, 'diskmgmt'],
  ['node-apt', `node/${NODE}`, 'apt'],
  ['node-repos', `node/${NODE}`, 'aptrepositories'],
  ['node-tasks', `node/${NODE}`, 'tasks'],
  ['node-syslog', `node/${NODE}`, 'syslog'],
  ['node-services', `node/${NODE}`, 'services'],
  ['node-certs', `node/${NODE}`, 'certificates'],
  ['vm-summary', VM, 'summary'],
  ['vm-hardware', VM, 'hardware'],
  ['vm-options', VM, 'options'],
  ['vm-snapshots', VM, 'snapshot'],
  ['vm-backup', VM, 'backup'],
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
};

(async () => {
  const perl = `perl -MPVE::AccessControl -e 'print PVE::AccessControl::assemble_ticket(shift)' '${user}'`;
  const ticket = execFileSync('ssh', ['-o', 'BatchMode=yes', sshHost, perl], { encoding: 'utf8' }).trim();
  const browser = await chromium.launch({ channel: args.channel || 'msedge', headless: true });
  const host = new URL(base).hostname;

  async function context(loggedIn, colorScheme = 'dark') {
    const ctx = await browser.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1600, height: 1000 }, colorScheme });
    // --theme auto leaves the cookie out: the server default applies
    const cookies = theme === 'auto' ? [] : [{ name: 'PVEThemeCookie', value: theme, domain: host, path: '/', secure: true }];
    if (loggedIn) cookies.push({ name: 'PVEAuthCookie', value: ticket, domain: host, path: '/', secure: true });
    await ctx.addCookies(cookies);
    if (cssFile) {
      await ctx.route(/\/pwt\/themes\/theme-[^/]+\.css/, r =>
        r.fulfill({ status: 200, contentType: 'text/css', body: fs.readFileSync(cssFile) }));
    }
    if (args.js) {
      // the host template is not patched during development: append the helper to pvemanagerlib.js
      await ctx.route(/\/pve2\/js\/pvemanagerlib\.js/, async r => {
        const resp = await r.fetch();
        await r.fulfill({ response: resp, body: (await resp.text()) + '\n' + fs.readFileSync(path.resolve(args.js), 'utf8') });
      });
    }
    if (fontDir) {
      await ctx.route(/\/pwt\/themes\/[^/]+\.woff2/, r => {
        const f = path.join(fontDir, path.basename(new URL(r.request().url()).pathname));
        return fs.existsSync(f) ? r.fulfill({ status: 200, contentType: 'font/woff2', body: fs.readFileSync(f) }) : r.continue();
      });
    }
    return ctx;
  }
  const want = n => !only || only.some(o => n === o || n.startsWith(o));
  // The UI polls all the time, so "network idle" never comes: wait a fixed time.
  const settle = (page, ms = 1500) => page.waitForTimeout(ms);

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
  page.on('pageerror', e => console.error('pageerror:', e.message));
  await page.goto(base + '/', { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => window.Ext && Ext.ComponentQuery && Ext.ComponentQuery.query('pveResourceTree').length > 0, null, { timeout: 30000 });
  await settle(page, 2500);
  // A cookie-only login renders before the capability list arrives (stock race);
  // it is cached in localStorage, so a second load builds the UI properly.
  await page.reload({ waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => window.Ext && Ext.ComponentQuery && Ext.ComponentQuery.query('pveResourceTree').length > 0, null, { timeout: 30000 });
  await settle(page, 2500);
  // Expand the tree fully so every row type is on screen.
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
            if (!panel.down('#' + tab)) return res('no tab ' + tab + ' in [' + Object.keys(panel.savedItems || {}).join(',') + ']');
          }
          panel.selectById(tab);
          res('ok');
        } catch (e) { res('error ' + e.message); }
      }, 400));
    }, [rid, tab]);
    if (ok !== 'ok') { console.error(name, ok); continue; }
    await settle(page, name.includes('summary') ? 3500 : 1500);
    await page.screenshot({ path: path.join(outDir, name + '.png') });
    console.log('shot', name);
  }

  for (const [name, js] of Object.entries(overlays)) {
    if (!want(name)) continue;
    try {
      await page.evaluate('void (' + js + ')');
      await settle(page, 1200);
      await page.screenshot({ path: path.join(outDir, name + '.png') });
      console.log('shot', name);
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
