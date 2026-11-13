# Marleybop palette map for Proxmox's own dark theme (theme-proxmox-dark.css).
# Run on the host at install time, so the base always matches the installed
# widget-toolkit version. GNU sed; I = case-insensitive, \b stops #333 matching #333333.

# surfaces
s/#262626\b/#1c1e21/gI
s/#1a1a1a\b/#111214/gI
s/#333333\b/#26292d/gI
s/#333\b/#26292d/gI
s/#0d0d0d\b/#0b0c0d/gI

# borders, hover and selection greys
s/#404040\b/#2b2e33/gI
s/#474747\b/#30343a/gI
s/#4d4d4d\b/#30343a/gI
s/#595959\b/#3a3e44/gI
s/#666666\b/#3a3e44/gI
s/#666\b/#3a3e44/gI

# text
s/#f2f2f2\b/#f6f5f2/gI
s/#e6e6e6\b/#e6e4df/gI
s/#bfbfbf\b/#b9bdc2/gI
s/#a6a6a6\b/#9a9fa6/gI
s/#9e9e9e\b/#8c9198/gI
s/#999999\b/#8c9198/gI
s/#999\b/#8c9198/gI
s/#8c8c8c\b/#8c9198/gI

# Proxmox blue becomes neutral; Rust is added by hand in the Marleybop layer
s/#0060a4\b/#3a3e44/gI
s/#0078cf\b/#4a4f56/gI
s/#004a80\b/#30343a/gI
s/#005da0\b/#8c9198/gI
s/#1b384c\b/#26292d/gI
s/#4db5ff\b/#e2683f/gI
s/#99d5ff\b/#f08a66/gI

# status
s/#ffae0b\b/#e0a93b/gI
s/#ce3c3c\b/#e5534b/gI
s/#ff4d4d\b/#ff8a80/gI
s/#640\b/#3d2e12/gI
s/#521414\b/#4a1c1a/gI

# translucent masks
s/rgba(38, *38, *38,/rgba(11,12,13,/gI
s/rgba(51, *51, *51,/rgba(38,41,45,/gI
