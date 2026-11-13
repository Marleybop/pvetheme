<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/marleybop-lockup-on-dark-560.png">
  <img src="docs/marleybop-lockup-on-light-560.png" alt="Marleybop" width="280">
</picture>

# Marleybop theme for Proxmox VE

**Marleybop · Tools**

A dark theme for the Proxmox VE web interface in the Marleybop look: grey surfaces, hairline borders,
Inter for text, and Rust kept for the one main button in a dialog. It shows up in Proxmox's own
**Color Theme** list as **Marleybop Dark** and comes back by itself after Proxmox updates.

Works on Proxmox VE 8 and 9 (built and tested on 9.1.1, widget-toolkit 5.1.2).

## Install

Run on the Proxmox node as root. The installer is one file with everything inside it; it downloads nothing else.

```bash
curl -fsSL https://raw.githubusercontent.com/Marleybop/marleybop-pve-theme/main/dist/install.sh | bash
```

From a PC that can SSH to the node, without hosting the file anywhere:

```bash
ssh root@<node> bash -s < dist/install.sh
```

Then open the web UI and hard-refresh once (Ctrl+Shift+R). Browsers on "Default (auto)" with a dark
system setting get Marleybop straight away; anyone else picks it under user menu > **Color Theme**.

| | |
|---|---|
| Only add it to the list, leave "Default (auto)" alone | `curl -fsSL https://raw.githubusercontent.com/Marleybop/marleybop-pve-theme/main/dist/install.sh \| bash -s -- install --no-default` |
| See what is installed | `marleybop-pve-theme status` |
| Put it back by hand after an update | `marleybop-pve-theme reapply` |
| Remove every change | `marleybop-pve-theme uninstall` |

In a cluster, run it on each node: the web UI files are per node.

## What it changes on the node

Everything is undone by `marleybop-pve-theme uninstall`, which leaves the two edited Proxmox files
byte-for-byte as they were.

| Where | What |
|---|---|
| `/usr/local/share/marleybop-pve-theme/` | The theme sources and the `apply.sh` script (`/usr/local/sbin/marleybop-pve-theme` links to it) |
| `/usr/share/javascript/proxmox-widget-toolkit/themes/` | `theme-marleybop.css`, five `marleybop-*.woff2` fonts, `marleybop-theme.js` |
| `.../proxmox-widget-toolkit/proxmoxlib.js` | One line added to `theme_map` so the theme is in the Color Theme list |
| `/usr/share/pve-manager/index.html.tpl` | One `<script>` line; `-mb<version>` added to the theme stylesheet's cache key; in default mode the automatic dark theme points at Marleybop |
| `/etc/apt/apt.conf.d/99marleybop-pve-theme` | Re-applies the two edits after a Proxmox package update replaces those files |
| `/etc/marleybop-pve-theme/` | The default-mode setting and an untouched copy of the two edited files |

`pveproxy` is reloaded (not restarted), so open consoles stay connected.

## How it works

Proxmox's dark theme is a small stylesheet of colour overrides on top of ExtJS. At install time the
theme is **built on the node**: the installed `theme-proxmox-dark.css` has its colours mapped to the
Marleybop palette (`src/palette.sed`), then the Marleybop layer (`src/marleybop.css`) is added on top:
fonts, thin scrollbars, grids and column headers, buttons, tabs, side navigation, forms, menus,
windows, progress bars, date picker. Because the base comes from the node itself, new widgets that a
Proxmox update adds to its dark theme are picked up on the next re-apply.

The RRD charts take their colours from JavaScript, not CSS, so a small script
(`src/marleybop-theme.js`) recolours them from CSS variables. It does nothing when another theme is active.

## Changing the theme

| File | What |
|---|---|
| `src/palette.sed` | Stock dark colour to Marleybop colour |
| `src/marleybop.css` | The style layer; colours and fonts are variables at the top |
| `src/marleybop-theme.js` | Chart colours (`--mb-chart-1` … `-6` in the CSS) |
| `src/apply.sh` | Install, re-apply, status, uninstall |
| `build.sh` | Packs everything into `dist/install.sh` |

```bash
./build.sh          # dist/install.sh
./build.sh --dev    # also dist/dev/theme-marleybop.css, from dev/theme-proxmox-dark.css (copy it from a node)
```

`tools/shot.cjs` screenshots about 40 views and dialogs of a real node with the dev stylesheet
swapped in by the browser, so nothing has to be installed to see a change. It needs `playwright-core`
(uses the installed Edge) and a password-less read-only user on the node:

```bash
# on the node, once
pveum user add marleybop-theme@pve && pveum acl modify / -user marleybop-theme@pve -role PVEAuditor
# on the PC
node tools/shot.cjs --host root@<node> --url https://<node>:8006 --node <name> --vm qemu/<id> --ct lxc/<id> \n    --css dist/dev/theme-marleybop.css --fonts dist/dev --js src/marleybop-theme.js --out shots
node tools/shot.cjs --host ... --url ... --theme marleybop --out shots/live      # the theme as installed
```

Bump `VERSION` for every release: it is part of the stylesheet's cache key, so browsers fetch the new one.

## Not covered

- The noVNC and xterm.js consoles, the mobile UI and the API viewer are separate pages with their own styles.
- Proxmox Backup Server and Datacenter Manager.
- A light variant.

## Credits

The approach (theme in the native selector, apt hook) follows
[ProxMorph](https://github.com/IT-BAER/proxmorph) by IT-BAER, found through
[Virtualization Howto](https://www.virtualizationhowto.com/2026/02/a-small-change-to-my-proxmox-web-ui-made-it-feel-more-modern/).
No ProxMorph code or CSS is included.

Code: MIT. Fonts: Inter, JetBrains Mono and Space Grotesk under the SIL Open Font License (`src/fonts/`).
Proxmox is a trademark of Proxmox Server Solutions GmbH; this project is not affiliated with it.
