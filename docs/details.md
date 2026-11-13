# pvetheme: details

## What it changes on the node

Everything is undone by `pvetheme uninstall`, which leaves the edited Proxmox files byte-for-byte as
they were (the self-test checks this).

| Where | What |
|---|---|
| `/usr/local/share/pvetheme/` | The engine: `apply.sh`, the style layer, the palettes. `/usr/local/sbin/pvetheme` links to it |
| `/usr/share/javascript/proxmox-widget-toolkit/themes/` | One `theme-*.css` per theme, five `marleybop-*.woff2` fonts, `marleybop-theme.js` |
| `.../proxmox-widget-toolkit/proxmoxlib.js` | One line per theme in `theme_map`, so they are in the Color Theme list |
| `/usr/share/pve-manager/index.html.tpl` | One `<script>` line; `-mb<version>` added to the theme stylesheet's cache key; the automatic dark theme points at the default theme |
| `/etc/apt/apt.conf.d/99pvetheme` | Re-applies the edits after a Proxmox package update replaces those files |
| `/etc/pvetheme/` | The default theme, node options, your own themes, and untouched copies of the edited files |
| `/usr/share/perl5/PVE/API2/Nodes.pm` | Only with `pvetheme sensors on`: a block that adds temperature readings to the node status |

`pveproxy` is reloaded, not restarted, so open consoles stay connected. Themes from other tools in
the same folder are left alone.

## Temperatures

`pvetheme sensors on` adds a "Temperatures" row to each node's Summary: CPU, drives, chipset and
fans, with the full list in the tooltip. Readings come straight from the kernel
(`/sys/class/hwmon`), so `lm-sensors` is not needed.

It works by adding about 30 lines to the node status API code. The change is compiled before it is
installed, checked against the live API afterwards, and undone automatically if either fails.
`pvetheme sensors off` removes it.

## How the themes are built

Proxmox's own dark theme is a small stylesheet: the list of everything in the UI that needs a
colour. At install time each theme is built on the node from three parts:

1. the node's `theme-proxmox-dark.css`, with every colour swapped for a variable (`src/palette.sed`).
   Light themes drop its icon-inverting filters.
2. the style layer (`src/layer.css`): type, spacing, shapes, drawn controls. It names no colours.
3. the theme's palette.

Because the base comes from the node itself, widgets that a Proxmox update adds to its dark theme
are picked up by every theme on the next re-apply.

The charts take their colours from JavaScript, not CSS, so `marleybop-theme.js` recolours them from
the palette. It also applies the per-browser options, provides the picker and shows the temperatures.
If the picker ever fails to open, Proxmox's own dialog opens instead.

## Working on it

| File | What |
|---|---|
| `src/layer.css` | The style layer |
| `src/palette.sed` | Stock dark colour to variable |
| `tools/gen-themes.sh` | The table the bundled palettes in `src/themes/` are written from |
| `src/marleybop-theme.js` | Options, chart colours, picker, temperatures |
| `src/sensors.pl` | The block added to the node status code |
| `src/apply.sh` | Build, install, re-apply, uninstall |
| `build.sh` | Packs everything into `dist/install.sh` |
| `test/run.sh` | Self-test against stand-in files; no node or root needed |

```bash
bash test/run.sh    # self-test
./build.sh          # dist/install.sh
./build.sh --dev    # also every theme into dist/dev/themes/, from dev/theme-proxmox-dark.css (copy it from a node)
```

`tools/shot.cjs` screenshots a real node with the dev build swapped in by the browser, so nothing
has to be installed to see a change; `tools/sheet.cjs` makes a contact sheet. They need
`playwright-core` and a password-less read-only user on the node:

```bash
pveum user add marleybop-theme@pve && pveum acl modify / -user marleybop-theme@pve -role PVEAuditor
node tools/shot.cjs --host root@<node> --url https://<node>:8006 --node <name> --vm qemu/<id> --ct lxc/<id> \
    --serve dist/dev/themes --inject --theme mb-nord-dark --out shots
```

`--anonymize` swaps guest names, addresses and the user name for generic ones. Bump `VERSION` for
every release: it is part of the stylesheet's cache key.
