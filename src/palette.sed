# Maps the colours of Proxmox's own dark theme (theme-proxmox-dark.css) to the
# engine's variables. Run on the node at install time, so the base always matches
# the installed widget-toolkit version. Every theme, light ones included, uses the
# result: the stock dark theme is the list of everything that needs a colour.
# GNU sed; I = case-insensitive, \b stops #333 matching #333333.

# surfaces
s/#262626\b/var(--mb-surface)/gI
s/#1a1a1a\b/var(--mb-bg)/gI
s/#0d0d0d\b/var(--mb-bg)/gI
s/#333333\b/var(--mb-raised)/gI
s/#333\b/var(--mb-raised)/gI

# borders, hover and selection greys
s/#404040\b/var(--mb-border)/gI
s/#474747\b/var(--mb-selected)/gI
s/#4d4d4d\b/var(--mb-selected)/gI
s/#595959\b/var(--mb-border-strong)/gI
s/#666666\b/var(--mb-border-strong)/gI
s/#666\b/var(--mb-border-strong)/gI

# text and icons
s/#f2f2f2\b/var(--mb-text)/gI
s/#ffffff\b/var(--mb-text)/gI
s/#fff\b/var(--mb-text)/gI
s/#e6e6e6\b/var(--mb-icon)/gI
s/#bfbfbf\b/var(--mb-text-2)/gI
s/#a6a6a6\b/var(--mb-muted)/gI
s/#9e9e9e\b/var(--mb-muted)/gI
s/#999999\b/var(--mb-muted)/gI
s/#999\b/var(--mb-muted)/gI
s/#8c8c8c\b/var(--mb-muted)/gI

# Proxmox blue becomes neutral; the accent is placed by hand in the layer
s/#0060a4\b/var(--mb-border-strong)/gI
s/#0078cf\b/var(--mb-border-strong)/gI
s/#004a80\b/var(--mb-selected)/gI
s/#005da0\b/var(--mb-muted)/gI
s/#1b384c\b/var(--mb-raised)/gI
s/#4db5ff\b/var(--mb-link)/gI
s/#99d5ff\b/var(--mb-link-hover)/gI

# status
s/#ffae0b\b/var(--mb-warn)/gI
s/#ce3c3c\b/var(--mb-bad-fill)/gI
s/#ff4d4d\b/var(--mb-bad)/gI
s/#640\b/var(--mb-warning-row)/gI
s/#521414\b/var(--mb-invalid-row)/gI

# translucent masks
s/rgba(38, *38, *38, *[0-9.]*)/var(--mb-mask)/gI
s/rgba(51, *51, *51, *[0-9.]*)/var(--mb-border)/gI

# named colours the stock theme uses for text and shadows
s/box-shadow:black /box-shadow:rgba(0,0,0,.5) /gI
