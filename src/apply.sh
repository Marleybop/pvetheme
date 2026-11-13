#!/usr/bin/env bash
# Marleybop theme for Proxmox VE: applies, re-applies and removes the theme on one node.
# Installed as /usr/local/sbin/marleybop-pve-theme by install.sh. Run with no arguments for help.
set -euo pipefail

SHARE=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
VERSION=$(cat "$SHARE/VERSION" 2>/dev/null || echo dev)

KEY=marleybop
TITLE='Marleybop Dark'
MARK='marleybop-pve-theme'

WT=${MB_WT_DIR:-/usr/share/javascript/proxmox-widget-toolkit}
THEMES=$WT/themes
LIB=$WT/proxmoxlib.js
STOCK=$THEMES/theme-proxmox-dark.css
TPL=${MB_TPL:-/usr/share/pve-manager/index.html.tpl}
CSS=$THEMES/theme-$KEY.css
JS=$THEMES/marleybop-theme.js
ETC=${MB_ETC_DIR:-/etc/marleybop-pve-theme}
HOOK=${MB_APT_HOOK:-/etc/apt/apt.conf.d/99marleybop-pve-theme}
BIN=${MB_BIN:-/usr/local/sbin/marleybop-pve-theme}

QUIET=0
say()  { [ "$QUIET" = 1 ] || printf '%s\n' "$*"; }
ok()   { say "  ok    $*"; }
warn() { printf '  warn  %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

need_root() { [ "$(id -u)" = 0 ] || die "run this as root"; }
need_pve() {
    [ -f "$TPL" ] && [ -f "$LIB" ] || die "Proxmox VE web UI files not found ($TPL, $LIB). This theme is for Proxmox VE 8 and 9."
    [ -f "$STOCK" ] || die "$STOCK not found: the stock dark theme is the base this theme is built from (needs Proxmox VE 7.4 or newer)."
}

# "1" when Marleybop should also be the dark theme of the "Default (auto)" setting.
want_default() { [ "$(cat "$ETC/default" 2>/dev/null || echo 1)" = 1 ]; }

# Replace a file's contents only when they differ, keeping its owner and mode.
put() { # put <new-file> <target>
    if [ -f "$2" ] && cmp -s "$1" "$2"; then rm -f "$1"; return 1; fi
    if [ -f "$2" ]; then cat "$1" > "$2"; rm -f "$1"; else install -m 0644 "$1" "$2"; rm -f "$1"; fi
    return 0
}

build_css() {
    local tmp; tmp=$(mktemp)
    {
        # first line is the name convention used by other theme tools
        printf '/*!%s*/\n' "$TITLE"
        printf '/* Marleybop theme %s. Built on this node from theme-proxmox-dark.css (colours mapped to the Marleybop palette) plus the Marleybop layer. Do not edit: run "marleybop-pve-theme reapply". */\n' "$VERSION"
        sed -f "$SHARE/palette.sed" "$STOCK"
        printf '\n'
        sed "s/@MBVER@/$VERSION/g" "$SHARE/marleybop.css"
    } > "$tmp"
    put "$tmp" "$CSS" || true
}

install_assets() {
    local f tmp
    for f in "$SHARE"/fonts/*.woff2; do
        tmp=$(mktemp); cat "$f" > "$tmp"; put "$tmp" "$THEMES/$(basename "$f")" || true
    done
    tmp=$(mktemp); cat "$SHARE/marleybop-theme.js" > "$tmp"; put "$tmp" "$JS" || true
}

lib_patched() { grep -q "// $MARK\$" "$LIB"; }
patch_lib() {
    lib_patched && return 0
    grep -Eq 'theme_map:[[:space:]]*\{' "$LIB" || die "could not find theme_map in $LIB; this widget-toolkit version is not supported. Nothing was changed in that file."
    local tmp; tmp=$(mktemp)
    sed "0,/theme_map:[[:space:]]*{/s//&\n            $KEY: '$TITLE', \/\/ $MARK/" "$LIB" > "$tmp"
    grep -q "// $MARK\$" "$tmp" || { rm -f "$tmp"; die "patching $LIB failed; file left unchanged."; }
    put "$tmp" "$LIB" || true
}
unpatch_lib() {
    [ -f "$LIB" ] && lib_patched || return 0
    local tmp; tmp=$(mktemp)
    sed "/\/\/ $MARK\$/d" "$LIB" > "$tmp"
    put "$tmp" "$LIB" || true
}

# The template gets three small edits, each one reversible by clean_tpl:
#   1. a <script> line for the chart helper, after pvemanagerlib.js
#   2. "-mb<version>" added to the theme stylesheet's cache key, so a theme update reaches browsers
#   3. (default mode) the automatic dark theme points at Marleybop instead of Proxmox Dark
clean_tpl() { # stdin -> stdout
    sed -e "/<!-- $MARK -->/d" \
        -e '/\/pwt\/themes\/theme-/s/\(\[% wtversion %\]\)-mb[0-9A-Za-z.]*/\1/' \
        -e "/prefers-color-scheme: dark/s/theme-$KEY\.css/theme-proxmox-dark.css/"
}
patch_tpl() {
    grep -q 'pvemanagerlib\.js' "$TPL" || die "could not find pvemanagerlib.js in $TPL; this pve-manager version is not supported. Nothing was changed in that file."
    local tmp script
    tmp=$(mktemp)
    script="    <script type=\"text/javascript\" src=\"/pwt/themes/marleybop-theme.js?ver=$VERSION\"></script> <!-- $MARK -->"
    clean_tpl < "$TPL" \
        | sed -e "/pvemanagerlib\.js/a\\$script" \
              -e "/\/pwt\/themes\/theme-/s/\[% wtversion %\]/&-mb$VERSION/" > "$tmp"
    if want_default; then
        sed -i "/prefers-color-scheme: dark/s/theme-proxmox-dark\.css/theme-$KEY.css/" "$tmp"
    fi
    grep -q "<!-- $MARK -->" "$tmp" || { rm -f "$tmp"; die "patching $TPL failed; file left unchanged."; }
    put "$tmp" "$TPL"
}
unpatch_tpl() {
    [ -f "$TPL" ] || return 0
    local tmp; tmp=$(mktemp)
    clean_tpl < "$TPL" > "$tmp"
    put "$tmp" "$TPL"
}

backup_once() { # keep one untouched copy of each file we edit, per package version
    local ver dir
    ver=$(dpkg-query -W -f='${Version}' pve-manager 2>/dev/null || echo unknown)_$(dpkg-query -W -f='${Version}' proxmox-widget-toolkit 2>/dev/null || echo unknown)
    dir=$ETC/backup/$ver
    [ -d "$dir" ] && return 0
    lib_patched && return 0
    grep -q "<!-- $MARK -->" "$TPL" && return 0
    mkdir -p "$dir"
    cp -p "$TPL" "$LIB" "$dir/"
    # only the two newest sets are kept
    ls -1dt "$ETC"/backup/*/ 2>/dev/null | tail -n +3 | xargs -r rm -rf
}

install_hook() {
    local tmp; tmp=$(mktemp)
    cat > "$tmp" <<EOF
// Marleybop theme for Proxmox VE: put the theme back after a Proxmox package update replaces the patched files.
DPkg::Post-Invoke { "if [ -x $BIN ]; then $BIN reapply --quiet || true; fi"; };
EOF
    put "$tmp" "$HOOK" || true
}

reload_ui() {
    [ -n "${MB_NO_RELOAD:-}" ] && return 0
    command -v systemctl >/dev/null 2>&1 || return 0
    systemctl is-active --quiet pveproxy 2>/dev/null || return 0
    # reload restarts the workers without dropping open consoles and shells
    systemctl reload pveproxy 2>/dev/null || systemctl restart pveproxy 2>/dev/null || warn "could not reload pveproxy; run: systemctl restart pveproxy"
}

cmd_install() {
    need_root; need_pve
    mkdir -p "$ETC"
    case "${1:-}" in
        --no-default) echo 0 > "$ETC/default" ;;
        --default|"") [ -f "$ETC/default" ] && [ -z "${1:-}" ] || echo 1 > "$ETC/default" ;;
        *) die "unknown option: $1" ;;
    esac
    say "Marleybop theme $VERSION for Proxmox VE"
    backup_once
    build_css;      ok "theme stylesheet built from this node's Proxmox Dark"
    install_assets; ok "fonts and chart helper copied"
    patch_lib;      ok "\"$TITLE\" added to the Color Theme list"
    patch_tpl || true
    if want_default; then ok "page template updated; Marleybop is the dark theme for \"Default (auto)\""
    else ok "page template updated"; fi
    install_hook;   ok "apt hook installed (theme returns by itself after Proxmox updates)"
    reload_ui;      [ -n "${MB_NO_RELOAD:-}" ] || ok "web UI reloaded"
    say ""
    say "Done. In the web UI: user menu (top right) > Color Theme > $TITLE."
    say "If the old look stays, hard-refresh the browser once (Ctrl+Shift+R)."
    say "Remove with: marleybop-pve-theme uninstall"
}

cmd_reapply() {
    [ "$(id -u)" = 0 ] || exit 0
    # during a package removal or a half-finished upgrade the files may be missing: nothing to do
    [ -f "$TPL" ] && [ -f "$LIB" ] && [ -f "$STOCK" ] || exit 0
    local changed=0
    if ! lib_patched; then backup_once; patch_lib; changed=1; fi
    if ! grep -q "<!-- $MARK -->" "$TPL"; then backup_once; fi
    if patch_tpl; then changed=1; fi
    build_css; install_assets; install_hook
    if [ "$changed" = 1 ]; then reload_ui; say "Marleybop theme re-applied after a Proxmox update."; else say "Marleybop theme is in place."; fi
}

cmd_uninstall() {
    need_root
    say "Removing the Marleybop theme"
    unpatch_lib; ok "removed from the Color Theme list"
    unpatch_tpl || true; ok "page template restored"
    rm -f "$CSS" "$JS" "$THEMES"/marleybop-*.woff2; ok "theme files removed"
    rm -f "$HOOK" "$BIN"; ok "apt hook removed"
    rm -rf "$ETC"
    reload_ui; ok "web UI reloaded"
    case "$SHARE" in */marleybop-pve-theme) rm -rf "$SHARE" ;; esac
    say ""
    say "Done. Browsers that had Marleybop selected fall back to the default theme."
}

cmd_status() {
    local s
    say "Marleybop theme $VERSION"
    s=no; [ -f "$CSS" ] && s="yes ($(wc -c < "$CSS") bytes)"; say "  stylesheet        $s"
    s=no; [ -f "$LIB" ] && lib_patched && s=yes; say "  in theme list     $s"
    s=no; [ -f "$TPL" ] && grep -q "<!-- $MARK -->" "$TPL" && s=yes; say "  template patched  $s"
    s=no; [ -f "$TPL" ] && grep -q "prefers-color-scheme: dark.*theme-$KEY\.css" "$TPL" && s=yes; say "  auto dark theme   $s"
    s=no; [ -f "$HOOK" ] && s=yes; say "  apt hook          $s"
    say "  pve-manager       $(dpkg-query -W -f='${Version}' pve-manager 2>/dev/null || echo '?')"
    say "  widget-toolkit    $(dpkg-query -W -f='${Version}' proxmox-widget-toolkit 2>/dev/null || echo '?')"
}

usage() {
    cat <<EOF
Marleybop theme $VERSION for Proxmox VE

  marleybop-pve-theme install [--no-default]   install or update the theme on this node
  marleybop-pve-theme reapply                  put the theme back after a Proxmox update (the apt hook does this)
  marleybop-pve-theme status                   show what is installed
  marleybop-pve-theme uninstall                remove every change

By default Marleybop also becomes the dark theme of the "Default (auto)" setting,
so browsers with a dark system setting get it without choosing. --no-default only
adds it to the Color Theme list.
EOF
}

cmd=${1:-help}; shift || true
for a in "$@"; do [ "$a" = --quiet ] && QUIET=1; done
args=(); for a in "$@"; do [ "$a" = --quiet ] || args+=("$a"); done
case "$cmd" in
    install)   cmd_install "${args[@]:-}" ;;
    reapply)   cmd_reapply ;;
    uninstall) cmd_uninstall ;;
    status)    cmd_status ;;
    help|-h|--help) usage ;;
    *) usage; exit 1 ;;
esac
