<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/marleybop-lockup-on-dark-560.png">
  <img src="docs/marleybop-lockup-on-light-560.png" alt="Marleybop" width="260">
</picture>

# pvetheme

Themes for the Proxmox VE web interface. 26 of them, light and dark, with a picker built into the web UI.

![Marleybop Dark](docs/shots/dark/node-summary.png)

## Install

On the Proxmox node, as root:

```bash
curl -fsSL https://raw.githubusercontent.com/Marleybop/pvetheme/main/dist/install.sh | bash
```

Then hard-refresh the web UI once (Ctrl+Shift+R). For Proxmox VE 8 and 9. In a cluster, run it on each node.

## Use

Click your **user name** (top right) > **Color Theme**.

![The theme picker](docs/shots/dark/ov-theme.png)

1. Click a card to preview that theme on the page behind.
2. Optionally set the accent colour, corners, density, font, and whether the Proxmox logo takes the theme colours.
3. Press **Apply**.

Your choice is saved in your browser, so everyone can have their own.

## Themes

![All themes](docs/shots/all-themes.png)

Marleybop (Dark, Light, Black) · Nord · Catppuccin (Mocha, Macchiato, Frappé, Latte) · Gruvbox · Solarized ·
GitHub · Rosé Pine · Everforest · Ayu · Dracula · Tokyo Night · One Dark · Monokai · Kanagawa

Families with a light and a dark theme also have an "auto" entry that follows your system setting.

## Commands

Run on the node as root.

| Command | What it does |
|---|---|
| `pvetheme list` | Show the themes |
| `pvetheme default <name>` | Theme for browsers that have not picked one (`none` = Proxmox's own) |
| `pvetheme options accent=#3b82f6 radius=round logo=accent` | Starting options for every browser: `accent`, `radius`, `density`, `font`, `logo` (`reset` to clear) |
| `pvetheme font "Family" [file.woff2]` | Font for every browser; with a file it is served from the node (`none` to clear) |
| `pvetheme sensors on` | Show temperatures and fan speeds on the node Summary (`off` to remove) |
| `pvetheme new <name> [copy-from]` | Start your own theme |
| `pvetheme reapply` | Rebuild after editing a theme |
| `pvetheme status` | Show what is installed |
| `pvetheme update` | Install the newest version (`check` only looks) |
| `pvetheme uninstall` | Remove everything |

## Make your own theme

```bash
pvetheme new my-theme mb-nord-dark
nano /etc/pvetheme/themes/my-theme.theme
pvetheme reapply
```

A theme is a short file of colours:

```ini
name=My Theme
mode=dark               # or light
bg=#111214              # page behind the panels
surface=#1c1e21         # panels
raised=#26292d          # buttons
border=#2b2e33
border_strong=#3a3e44   # input and button edges
text=#f6f5f2
text2=#b9bdc2           # secondary text and icons
muted=#8c9198           # column headers
accent=#c8452a          # main button in dialogs
on_accent=#ffffff
link=#e2683f
sel=#f6f5f2             # selected tab, checked box
on_sel=#16181b
bar=#b9bdc2             # usage bars and gauges
good=#6db04a
warn=#e0a93b
bad=#ff8a80
bad_fill=#e5534b
chart1=#b9bdc2          # chart1 to chart6: chart lines
```

Theme names are lowercase words of up to 10 letters joined by `-` (a Proxmox rule).
Your themes are kept through updates and uninstall.

## Remove

```bash
pvetheme uninstall
```

This puts every Proxmox file it edited back exactly as it was.

## More

- [What it changes on the node, and how it works](docs/details.md)
- Not themed: the noVNC and xterm.js consoles, the mobile UI, Proxmox Backup Server.

MIT licence. Fonts (Inter, JetBrains Mono, Space Grotesk) are under the SIL Open Font License.
Not affiliated with Proxmox Server Solutions GmbH. Thanks to [ProxMorph](https://github.com/IT-BAER/proxmorph) for the idea.
