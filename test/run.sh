#!/usr/bin/env bash
# Self-test for src/apply.sh. Runs against small stand-ins for the three Proxmox files it reads
# or edits, in a temp folder, so it needs no Proxmox node and no root. Needs GNU sed.
#   bash test/run.sh
set -euo pipefail
cd "$(dirname "$0")/.."

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/wt/themes" "$W/apt"

# stand-ins with the same shapes the real files have
cat > "$W/wt/proxmoxlib.js" <<'EOF'
Ext.define('Proxmox.Utils', {
    utilities: {
        theme_map: {
            crisp: 'Light theme',
            'proxmox-dark': 'Proxmox Dark',
        },
        other_map: { theme_map: {} },
    },
});
EOF
cat > "$W/tpl" <<'EOF'
<head>
    <link rel="stylesheet" type="text/css" href="/pwt/css/ext6-pmx.css?ver=[% wtversion %]" />
    [%- IF theme != 'crisp' %]
      [%- IF theme != 'auto' %]
    <link rel="stylesheet" type="text/css" href="/pwt/themes/theme-[% theme %].css?ver=[% wtversion %]" />
      [%- ELSE %]
    <link rel="stylesheet" type="text/css" media="(prefers-color-scheme: dark)" href="/pwt/themes/theme-proxmox-dark.css?ver=[% wtversion %]" />
      [%- END %]
    [%- END %]
    <script type="text/javascript" src="/proxmoxlib.js?ver=[% wtversion %]"></script>
    <script type="text/javascript" src="/pve2/js/pvemanagerlib.js?ver=[% version %]"></script>
</head>
EOF
printf '%s' ':root{--pwt-panel-background: #262626}.x-panel-body-default{background-color:#262626;border-color:#404040;color:#f2f2f2}.x-tool-img{filter:brightness(175%)}:root{color-scheme:dark}.x-btn-default-small{background-color:#0060a4}' > "$W/wt/themes/theme-proxmox-dark.css"
cp "$W/wt/proxmoxlib.js" "$W/lib.orig"; cp "$W/tpl" "$W/tpl.orig"

# the part of the node status code the temperature readout is added to
cat > "$W/Nodes.pm" <<'EOF'
        $res->{pveversion} = PVE::pvecfg::package() . "/" . PVE::pvecfg::version_text();

        my $dinfo = df('/', 1); # output is bytes

        $res->{rootfs} = {};
EOF
cp "$W/Nodes.pm" "$W/nodes.orig"

export MB_TEST=1 MB_NO_RELOAD=1 MB_WT_DIR="$W/wt" MB_TPL="$W/tpl" MB_ETC_DIR="$W/etc" MB_APT_HOOK="$W/apt/hook" MB_BIN="$W/bin" MB_NODES_PM="$W/Nodes.pm" MB_VERSION=9.9.9
run() { bash src/apply.sh "$@"; }
n=0
check() { n=$((n + 1)); if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; exit 1; fi; }
count() { ls "$W"/wt/themes/theme-*.css | wc -l | tr -d ' '; }

themes=$(ls src/themes/*.theme | wc -l | tr -d ' ')
autos=$(grep -c '^auto ' src/themes/index)
total=$((themes + autos))

run install > "$W/out.txt"
check "install builds $total stylesheets next to the stock one" '[ "$(count)" = "$((total + 1))" ]'
check "every entry is in theme_map, once"                      '[ "$(grep -c "// marleybop-pvetheme\$" "$W/wt/proxmoxlib.js")" = "$total" ]'
check "entries went into the first theme_map only"             'grep -q "other_map: { theme_map: {} }" "$W/wt/proxmoxlib.js"'
bad_keys() { grep "// marleybop-pvetheme\$" "$W/wt/proxmoxlib.js" | sed "s/^ *.\([a-z-]*\).*/\1/" | grep -Ev '^[a-z]{1,10}(-[a-z]{1,10}){0,5}$' || true; }
check "keys pass the server theme-name rule"                   '[ -z "$(bad_keys)" ]'
check "template loads the helper script"                       'grep -q "marleybop-theme.js?ver=9.9.9" "$W/tpl"'
check "template cache key carries the version"                 '[ "$(grep -c "wtversion %\]-mb9.9.9" "$W/tpl")" = 2 ]'
check "default theme replaces the automatic dark theme"        'grep -q "data-mb-media=\"(prefers-color-scheme: dark)\" href=\"/pwt/themes/theme-marleybop-auto.css" "$W/tpl"'
check "dark theme keeps the stock filters"                     'grep -q "filter:brightness(175%)" "$W/wt/themes/theme-marleybop.css"'
check "light theme drops the stock filters and dark scheme"    '! grep -q "filter:brightness(175%)\|color-scheme:dark" "$W/wt/themes/theme-marleybop-light.css"'
check "stock colours are mapped to variables"                  'grep -q "background-color:var(--mb-surface);border-color:var(--mb-border);color:var(--mb-text)" "$W/wt/themes/theme-marleybop.css"'
check "no unmapped stock grey is left"                         '! grep -q "#262626\|#404040\|#0060a4" "$W/wt/themes/theme-marleybop.css"'
check "auto entry imports its pair"                            'grep -q "theme-marleybop-light.css?v=9.9.9\") (prefers-color-scheme: light)" "$W/wt/themes/theme-marleybop-auto.css"'
check "helper has the manifest"                                'head -n 2 "$W/wt/themes/marleybop-theme.js" | grep -q "\"key\":\"mb-nord-dark\""'
check "manifest is valid JavaScript"                           '! command -v node >/dev/null || node --check "$W/wt/themes/marleybop-theme.js"'
check "apt hook written"                                       'grep -q "reapply --quiet" "$W/apt/hook"'

cp "$W/wt/proxmoxlib.js" "$W/lib.1"; cp "$W/tpl" "$W/tpl.1"
check "reapply changes nothing"                                'run reapply | grep -q "in place" && cmp -s "$W/lib.1" "$W/wt/proxmoxlib.js" && cmp -s "$W/tpl.1" "$W/tpl"'
cp "$W/lib.orig" "$W/wt/proxmoxlib.js"; cp "$W/tpl.orig" "$W/tpl"
check "reapply restores the edits after an update"             'run reapply | grep -q "re-applied" && cmp -s "$W/lib.1" "$W/wt/proxmoxlib.js" && cmp -s "$W/tpl.1" "$W/tpl"'

run default none > /dev/null
check "default none puts the automatic dark theme back"        'grep -q "media=\"(prefers-color-scheme: dark)\" href=\"/pwt/themes/theme-proxmox-dark.css" "$W/tpl" && ! grep -q data-mb-media "$W/tpl"'
run default mb-nord-dark > /dev/null
check "default <theme> works for any theme"                    'grep -q "data-mb-media=.*theme-mb-nord-dark.css" "$W/tpl"'
check "default refuses an unknown theme"                       '! run default nope-nope > /dev/null 2>&1'

run new my-theme mb-dracula > /dev/null
sed -i 's/^accent=.*/accent=#00ff88     # a comment after the value is allowed/' "$W/etc/themes/my-theme.theme"
run reapply > /dev/null
check "a theme of your own is built and listed"                'grep -q -- "--mb-accent: #00ff88" "$W/wt/themes/theme-my-theme.css" && grep -q "my-theme" "$W/wt/proxmoxlib.js"'
check "list shows it"                                          'run list > "$W/list.txt" && grep -q "^my-theme .*(yours)" "$W/list.txt"'
printf 'name=Bad\nmode=dark\nbg=red; }\n' > "$W/etc/themes/bad.theme"
printf 'name=x\nmode=dark\n' > "$W/etc/themes/Bad_Name.theme"
check "broken themes are skipped, not fatal"                   'run reapply > /dev/null 2>"$W/err.txt" && [ ! -f "$W/wt/themes/theme-bad.css" ] && grep -q "bg must be a hex colour" "$W/err.txt" && grep -q "file name must be" "$W/err.txt"'
rm -f "$W/etc/themes/bad.theme" "$W/etc/themes/Bad_Name.theme"

helper_head() { head -n 2 "$W/wt/themes/marleybop-theme.js"; }
run options accent=#3b82f6 radius=round density=compact > /dev/null
check "node options reach the helper"                          'helper_head | grep -q "defaults: {\"accent\":\"#3b82f6\",\"radius\":\"round\",\"density\":\"compact\"}"'
check "a bad option is refused"                                '! run options accent=red > /dev/null 2>&1 && ! run options "radius=round\"}" > /dev/null 2>&1'
printf 'not really a font' > "$W/f.woff2"
run font "My Font" "$W/f.woff2" > /dev/null
check "a font file is served and declared"                     '[ -f "$W/wt/themes/marleybop-userfont.woff2" ] && grep -q "font-family: \"My Font\"; .*marleybop-userfont.woff2" "$W/wt/themes/theme-marleybop.css" && helper_head | grep -q "\"font\":\"custom\",\"fontName\":\"My Font\""'
run font none > /dev/null
check "font none removes it"                                   '[ ! -f "$W/wt/themes/marleybop-userfont.woff2" ] && ! grep -q "My Font" "$W/wt/themes/theme-marleybop.css" "$W/wt/themes/marleybop-theme.js"'
run options reset > /dev/null
check "options reset clears them"                              'helper_head | grep -q "defaults: {},"'

line_of() { grep -n "$1" "$W/Nodes.pm" | head -n 1 | cut -d: -f1; }
perl_ok() {
    command -v perl >/dev/null || return 0
    { echo 'use strict; my $res = {};'; echo '{'; sed -n '/pvetheme sensors$/,/pvetheme sensors END$/p' "$W/Nodes.pm"; echo '}'; } > "$W/t.pl"
    perl -c "$W/t.pl" 2>/dev/null
}
run sensors on > /dev/null
check "sensors on adds the block before the disk lookup"       'grep -q "marleybop-sensors" "$W/Nodes.pm" && [ "$(line_of "sensors END")" -lt "$(line_of "my .dinfo")" ]'
check "the added Perl compiles"                                'perl_ok'
cp "$W/Nodes.pm" "$W/nodes.1"; cp "$W/nodes.orig" "$W/Nodes.pm"
run reapply > /dev/null
check "reapply puts it back after an update"                   'cmp -s "$W/nodes.1" "$W/Nodes.pm"'
run sensors off > /dev/null
check "sensors off restores the file byte for byte"            'cmp -s "$W/nodes.orig" "$W/Nodes.pm"'
run sensors on > /dev/null

# another tool's theme must survive everything
echo '/*!Someone Else*/' > "$W/wt/themes/theme-other.css"
run reapply > /dev/null
check "other tools' themes are left alone"                     '[ -f "$W/wt/themes/theme-other.css" ]'

run uninstall > /dev/null
check "uninstall restores proxmoxlib.js byte for byte"         'cmp -s "$W/lib.orig" "$W/wt/proxmoxlib.js"'
check "uninstall restores the template byte for byte"          'cmp -s "$W/tpl.orig" "$W/tpl"'
check "uninstall removes only its own files"                   '[ "$(ls "$W/wt/themes" | tr "\n" " ")" = "theme-other.css theme-proxmox-dark.css " ]'
check "uninstall restores the node status code"                'cmp -s "$W/nodes.orig" "$W/Nodes.pm"'
check "uninstall keeps your own themes"                        '[ -f "$W/etc/themes/my-theme.theme" ] && [ ! -e "$W/apt/hook" ]'

echo "$n checks passed"
