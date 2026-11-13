#!/usr/bin/env bash
# Marleybop theme engine for Proxmox VE: builds, applies, re-applies and removes the themes on one node.
# Installed as /usr/local/sbin/marleybop-pve-theme by install.sh. Run with no arguments for help.
set -euo pipefail

SHARE=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
VERSION=${MB_VERSION:-$(cat "$SHARE/VERSION" 2>/dev/null || echo dev)}
MARK='marleybop-pve-theme'

WT=${MB_WT_DIR:-/usr/share/javascript/proxmox-widget-toolkit}
THEMES=$WT/themes
LIB=$WT/proxmoxlib.js
STOCK=${MB_STOCK:-$THEMES/theme-proxmox-dark.css}
TPL=${MB_TPL:-/usr/share/pve-manager/index.html.tpl}
JS=$THEMES/marleybop-theme.js
ETC=${MB_ETC_DIR:-/etc/marleybop-pve-theme}
CUSTOM=$ETC/themes
HOOK=${MB_APT_HOOK:-/etc/apt/apt.conf.d/99marleybop-pve-theme}
BIN=${MB_BIN:-/usr/local/sbin/marleybop-pve-theme}

# the Proxmox server only accepts theme names made of lowercase segments of at most 10 letters
KEY_RE='^[a-z]{1,10}(-[a-z]{1,10}){0,5}$'
COLOURS=(bg surface raised border border_strong text text2 muted accent on_accent link sel on_sel bar good warn bad bad_fill chart1 chart2 chart3 chart4 chart5 chart6)

QUIET=0
say()  { [ "$QUIET" = 1 ] || printf '%s\n' "$*"; }
ok()   { say "  ok    $*"; }
warn() { printf '  warn  %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

need_root() { [ -n "${MB_TEST:-}" ] || [ "$(id -u)" = 0 ] || die "run this as root"; }
need_pve() {
    [ -f "$TPL" ] && [ -f "$LIB" ] || die "Proxmox VE web UI files not found ($TPL, $LIB). This is for Proxmox VE 8 and 9."
    [ -f "$STOCK" ] || die "$STOCK not found: the stock dark theme is the base every theme is built from (needs Proxmox VE 7.4 or newer)."
}

# Replace a file's contents only when they differ, keeping its owner and mode. Returns 1 when unchanged.
put() { # put <new-file> <target>
    if [ -f "$2" ] && cmp -s "$1" "$2"; then rm -f "$1"; return 1; fi
    if [ -f "$2" ]; then cat "$1" > "$2"; rm -f "$1"; else install -m 0644 "$1" "$2"; rm -f "$1"; fi
    return 0
}

# ---------- themes -----------------------------------------------------------

declare -A T
# Reads a .theme file (key=value lines) into T. Values are checked, never executed.
load_theme() { # load_theme <file>  -> returns 1 with a message when the file is not usable
    local file=$1 k v c
    T=()
    while IFS='=' read -r k v || [ -n "$k" ]; do
        k=${k//[[:space:]]/}; v=${v%$'\r'}
        v=${v%%[[:space:]]#*}   # a comment after the value
        v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
        case "$k" in ''|'#'*) continue ;; esac
        [[ $k =~ ^[a-z_0-9]+$ ]] || continue
        T[$k]=$v
    done < "$file"
    [[ ${T[name]:-} =~ ^[A-Za-z0-9\ ().+-]{1,40}$ ]] || { warn "$file: name is missing or has characters other than letters, digits, spaces and ().+-"; return 1; }
    case "${T[mode]:-}" in dark|light) ;; *) warn "$file: mode must be dark or light"; return 1 ;; esac
    for c in "${COLOURS[@]}"; do
        [[ ${T[$c]:-} =~ ^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$ ]] || { warn "$file: $c must be a hex colour like #1c1e21"; return 1; }
    done
}

# Prints "key file" for every usable theme: the bundled ones in index order, then the node's own.
theme_files() {
    local kind rest f k
    while read -r kind rest; do
        [ "$kind" = theme ] && [ -f "$SHARE/themes/$rest.theme" ] && echo "$rest $SHARE/themes/$rest.theme"
    done < "$SHARE/themes/index"
    for f in "$CUSTOM"/*.theme; do
        [ -f "$f" ] || continue
        k=$(basename "$f" .theme)
        if [[ ! $k =~ $KEY_RE ]]; then warn "$f: skipped, the file name must be lowercase words of up to 10 letters joined by '-'"; continue; fi
        [ -f "$SHARE/themes/$k.theme" ] && { warn "$f: skipped, a bundled theme already has this name"; continue; }
        echo "$k $f"
    done
}
# Prints "key|title|light|dark" for the follow-the-system entries.
auto_entries() {
    local kind rest
    while read -r kind rest; do [ "$kind" = auto ] && echo "$rest"; done < "$SHARE/themes/index"
    return 0
}

# Writes one theme's stylesheet to stdout. Needs T loaded.
emit_theme() { # emit_theme <key>
    local key=$1 c
    printf '/*!%s*/\n' "${T[name]}"
    printf '/* %s %s: built on this node from theme-proxmox-dark.css, the Marleybop layer and the "%s" palette. Do not edit; run "marleybop-pve-theme reapply". */\n' "$MARK" "$VERSION" "$key"
    # 1. the stock dark theme, one rule per line, colours mapped to variables.
    #    Light themes drop its icon-inverting filters; everything else applies to both.
    if [ "${T[mode]}" = light ]; then
        sed 's/}/}\n/g' "$STOCK" | sed -f "$SHARE/palette.sed" | grep -v -e 'filter:' -e 'color-scheme' || true
    else
        sed 's/}/}\n/g' "$STOCK" | sed -f "$SHARE/palette.sed"
    fi
    printf '\n'
    # 2. the layer
    sed "s/@MBVER@/$VERSION/g" "$SHARE/layer.css"
    # 3. the palette
    printf '\n:root {\n  --mb-theme: %s;\n  --mb-mode: %s;\n' "$key" "${T[mode]}"
    printf '  --mb-bg: %s;\n  --mb-surface: %s;\n  --mb-raised: %s;\n  --mb-border: %s;\n  --mb-border-strong: %s;\n' "${T[bg]}" "${T[surface]}" "${T[raised]}" "${T[border]}" "${T[border_strong]}"
    printf '  --mb-text: %s;\n  --mb-text-2: %s;\n  --mb-muted: %s;\n' "${T[text]}" "${T[text2]}" "${T[muted]}"
    printf '  --mb-accent: %s;\n  --mb-on-accent: %s;\n  --mb-link: %s;\n  --mb-sel: %s;\n  --mb-on-sel: %s;\n  --mb-bar: %s;\n' "${T[accent]}" "${T[on_accent]}" "${T[link]}" "${T[sel]}" "${T[on_sel]}" "${T[bar]}"
    printf '  --mb-good: %s;\n  --mb-warn: %s;\n  --mb-bad: %s;\n  --mb-bad-fill: %s;\n' "${T[good]}" "${T[warn]}" "${T[bad]}" "${T[bad_fill]}"
    for c in 1 2 3 4 5 6; do printf '  --mb-chart-%s: %s;\n' "$c" "${T[chart$c]}"; done
    printf '  --mb-chart-fill-opacity: 0.16;\n'
    # the next ones are read by the stock gauge and chart code, which needs plain colours
    printf '  --pwt-panel-background: %s;\n  --pwt-text-color: %s;\n  --pwt-gauge-default: %s;\n  --pwt-gauge-back: %s;\n' "${T[surface]}" "${T[text]}" "${T[bar]}" "${T[raised]}"
    printf '  --pwt-gauge-warn: %s;\n  --pwt-gauge-crit: %s;\n  --pwt-chart-primary: %s;\n  --pwt-chart-grid-stroke: %s;\n' "${T[warn]}" "${T[bad_fill]}" "${T[border_strong]}" "${T[border]}"
    if [ "${T[mode]}" = light ]; then
        printf '  --mb-tool-filter: grayscale(1) brightness(0.75);\n  --mb-tool-filter-hover: grayscale(1) brightness(0.35);\n  --mb-sprite-filter: none;\n'
        printf '  --mb-mask: rgba(20, 22, 25, 0.32);\n  --mb-shadow: 0 14px 40px 2px rgba(20, 22, 25, 0.22);\n  color-scheme: light;\n'
    else
        printf '  --mb-tool-filter: grayscale(1) brightness(1.9);\n  --mb-tool-filter-hover: grayscale(1) brightness(2.4);\n  --mb-sprite-filter: none;\n'
        printf '  --mb-mask: rgba(0, 0, 0, 0.6);\n  --mb-shadow: 0 18px 50px 4px rgba(0, 0, 0, 0.6);\n  color-scheme: dark;\n'
    fi
    printf '}\n'
}

# Removes every stylesheet this tool generated (found by its marker line), leaving other themes alone.
remove_generated() {
    local f
    for f in "$THEMES"/theme-*.css; do
        [ -f "$f" ] || continue
        if head -n 3 "$f" | grep -q "$MARK"; then rm -f "$f"; fi
    done
    # version 1 wrote this file without the marker on a line of its own
    [ -f "$THEMES/theme-marleybop.css" ] && head -n 2 "$THEMES/theme-marleybop.css" | grep -q 'Marleybop theme' && rm -f "$THEMES/theme-marleybop.css"
    return 0
}

# Builds every theme, the follow-the-system entries, the list for proxmoxlib.js and the manifest for the dialog.
MAP_LINES=''; MANIFEST=''; BUILT=0; KEYS=' '
build_all() {
    local key file tmp entry title light dark first=1
    MAP_LINES=''; MANIFEST=''; BUILT=0; KEYS=' '
    remove_generated
    while read -r key file; do
        load_theme "$file" || continue
        tmp=$(mktemp); emit_theme "$key" > "$tmp"; put "$tmp" "$THEMES/theme-$key.css" || true
        MAP_LINES+="            '$key': '${T[name]}', // $MARK"$'\n'
        [ "$first" = 1 ] || MANIFEST+=','
        first=0
        MANIFEST+="{\"key\":\"$key\",\"title\":\"${T[name]}\",\"mode\":\"${T[mode]}\",\"bg\":\"${T[bg]}\",\"surface\":\"${T[surface]}\",\"border\":\"${T[border]}\",\"text\":\"${T[text]}\",\"muted\":\"${T[muted]}\",\"accent\":\"${T[accent]}\",\"sel\":\"${T[sel]}\",\"link\":\"${T[link]}\"}"
        KEYS+="$key "; BUILT=$((BUILT + 1))
    done < <(theme_files)
    [ "$BUILT" -gt 0 ] || die "no usable themes found in $SHARE/themes"
    while IFS='|' read -r entry title light dark; do
        [ -n "$entry" ] || continue
        case "$KEYS" in *" $light "*) ;; *) continue ;; esac
        case "$KEYS" in *" $dark "*) ;; *) continue ;; esac
        tmp=$(mktemp)
        {
            printf '/*!%s*/\n' "$title"
            printf '/* %s %s: follows the system light/dark setting. */\n' "$MARK" "$VERSION"
            printf '@import url("theme-%s.css?v=%s") (prefers-color-scheme: light);\n' "$light" "$VERSION"
            printf '@import url("theme-%s.css?v=%s") (prefers-color-scheme: dark);\n' "$dark" "$VERSION"
        } > "$tmp"
        put "$tmp" "$THEMES/theme-$entry.css" || true
        MAP_LINES+="            '$entry': '$title', // $MARK"$'\n'
        MANIFEST+=",{\"key\":\"$entry\",\"title\":\"$title\",\"mode\":\"auto\",\"light\":\"$light\",\"dark\":\"$dark\"}"
        KEYS+="$entry "
    done < <(auto_entries)
}

install_assets() {
    local f tmp
    for f in "$SHARE"/fonts/*.woff2; do
        tmp=$(mktemp); cat "$f" > "$tmp"; put "$tmp" "$THEMES/$(basename "$f")" || true
    done
    tmp=$(mktemp)
    {
        printf '/* %s %s: generated, do not edit. */\n' "$MARK" "$VERSION"
        printf 'window.MarleybopThemes = { version: "%s", def: "%s", themes: [%s] };\n' "$VERSION" "$(get_default)" "$MANIFEST"
        cat "$SHARE/marleybop-theme.js"
    } > "$tmp"
    put "$tmp" "$JS" || true
}

# ---------- the two Proxmox files we edit -----------------------------------

lib_patched() { grep -q "// $MARK\$" "$LIB"; }
# Puts our entries at the top of theme_map; returns 1 when the file already had exactly these.
patch_lib() {
    grep -Eq 'theme_map:[[:space:]]*\{' "$LIB" || die "could not find theme_map in $LIB; this widget-toolkit version is not supported. Nothing was changed in that file."
    local tmp lines
    tmp=$(mktemp); lines=$(mktemp)
    printf '%s' "$MAP_LINES" > "$lines"
    sed "/\/\/ $MARK\$/d" "$LIB" | sed "0,/theme_map:[[:space:]]*{/{/theme_map:[[:space:]]*{/r $lines
}" > "$tmp"
    rm -f "$lines"
    grep -q "// $MARK\$" "$tmp" || { rm -f "$tmp"; die "patching $LIB failed; file left unchanged."; }
    put "$tmp" "$LIB"
}
unpatch_lib() {
    [ -f "$LIB" ] && lib_patched || return 0
    local tmp; tmp=$(mktemp)
    sed "/\/\/ $MARK\$/d" "$LIB" > "$tmp"
    put "$tmp" "$LIB" || true
}

# Default theme for browsers that have not chosen one: a theme key, or "none".
get_default() {
    local d; d=$(cat "$ETC/default" 2>/dev/null || echo marleybop-auto)
    case "$d" in 1) d=marleybop-auto ;; 0) d=none ;; esac   # values written by version 1
    echo "$d"
}

# The template gets three small edits, each one undone by clean_tpl:
#   1. a <script> line for the helper, after pvemanagerlib.js
#   2. "-mb<version>" added to the theme stylesheet's cache key, so an update reaches browsers
#   3. with a default theme: the line that loads Proxmox Dark for "Default (auto)" loads that theme
#      instead (its media attribute is parked in data-mb-media so it can be put back)
clean_tpl() { # stdin -> stdout
    sed -e "/<!-- $MARK -->/d" \
        -e '/\/pwt\/themes\/theme-/s/\(\[% wtversion %\]\)-mb[0-9A-Za-z.]*/\1/' \
        -e '/data-mb-media=/{s/ data-mb-media="\([^"]*\)"/ media="\1"/;s/theme-[a-z-]*\.css/theme-proxmox-dark.css/}' \
        -e '/prefers-color-scheme: dark/s/theme-[a-z-]*\.css/theme-proxmox-dark.css/'
}
patch_tpl() {
    grep -q 'pvemanagerlib\.js' "$TPL" || die "could not find pvemanagerlib.js in $TPL; this pve-manager version is not supported. Nothing was changed in that file."
    local tmp script def
    tmp=$(mktemp)
    script="    <script type=\"text/javascript\" src=\"/pwt/themes/marleybop-theme.js?ver=$VERSION\"></script> <!-- $MARK -->"
    clean_tpl < "$TPL" \
        | sed -e "/pvemanagerlib\.js/a\\$script" \
              -e "/\/pwt\/themes\/theme-/s/\[% wtversion %\]/&-mb$VERSION/" > "$tmp"
    def=$(get_default)
    if [ "$def" != none ]; then
        case "$KEYS" in
            *" $def "*) sed -i "/media=\"(prefers-color-scheme: dark)\"/{s/ media=\"\([^\"]*\)\"/ data-mb-media=\"\1\"/;s/theme-proxmox-dark\.css/theme-$def.css/}" "$tmp" ;;
            *) warn "default theme \"$def\" does not exist; leaving Proxmox's default. Fix with: marleybop-pve-theme default <name>" ;;
        esac
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
// Marleybop themes for Proxmox VE: put the themes back after a Proxmox package update replaces the patched files.
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

# Does everything; sets CHANGED=1 when one of the two Proxmox files had to be edited.
CHANGED=0
apply_all() {
    CHANGED=0
    mkdir -p "$ETC" "$CUSTOM"
    backup_once
    build_all
    install_assets
    if patch_lib; then CHANGED=1; fi
    if patch_tpl; then CHANGED=1; fi
    install_hook
}

# ---------- commands ---------------------------------------------------------

cmd_install() {
    need_root; need_pve
    mkdir -p "$ETC"
    while [ $# -gt 0 ]; do
        case "$1" in
            --no-default) echo none > "$ETC/default" ;;
            --default) shift; [[ ${1:-} =~ $KEY_RE ]] || die "--default needs a theme name (see: marleybop-pve-theme list)"; echo "$1" > "$ETC/default" ;;
            '') ;;
            *) die "unknown option: $1" ;;
        esac
        shift || true
    done
    say "Marleybop themes $VERSION for Proxmox VE"
    apply_all
    ok "$BUILT themes built from this node's Proxmox Dark, plus the follow-the-system entries"
    ok "fonts and helper script copied"
    ok "themes added to the Color Theme list"
    local def; def=$(get_default)
    if [ "$def" = none ]; then ok "page template updated"
    else ok "page template updated; browsers on \"Default (auto)\" get $def"; fi
    ok "apt hook installed (themes return by themselves after Proxmox updates)"
    reload_ui; [ -n "${MB_NO_RELOAD:-}" ] || ok "web UI reloaded"
    say ""
    say "Done. In the web UI: user menu (top right) > Color Theme."
    say "If the old look stays, hard-refresh the browser once (Ctrl+Shift+R)."
    say "More: marleybop-pve-theme help"
}

cmd_reapply() {
    [ -n "${MB_TEST:-}" ] || [ "$(id -u)" = 0 ] || exit 0
    # during a package removal or a half-finished upgrade the files may be missing: nothing to do
    [ -f "$TPL" ] && [ -f "$LIB" ] && [ -f "$STOCK" ] || exit 0
    apply_all
    if [ "$CHANGED" = 1 ]; then reload_ui; say "Marleybop themes re-applied ($BUILT themes)."; else say "Marleybop themes are in place ($BUILT themes)."; fi
}

cmd_uninstall() {
    need_root
    say "Removing the Marleybop themes"
    unpatch_lib; ok "removed from the Color Theme list"
    unpatch_tpl || true; ok "page template restored"
    remove_generated
    rm -f "$JS" "$THEMES"/marleybop-*.woff2; ok "theme files removed"
    rm -f "$HOOK" "$BIN"; ok "apt hook removed"
    if ls "$CUSTOM"/*.theme >/dev/null 2>&1; then
        rm -rf "$ETC/backup" "$ETC/default"
        ok "your own themes kept in $CUSTOM"
    else
        rm -rf "$ETC"
    fi
    reload_ui; [ -n "${MB_NO_RELOAD:-}" ] || ok "web UI reloaded"
    case "$SHARE" in */marleybop-pve-theme) rm -rf "$SHARE" ;; esac
    say ""
    say "Done. Browsers that had one of these themes selected fall back to the default theme."
}

cmd_status() {
    local s n
    say "Marleybop themes $VERSION"
    n=0; for s in "$THEMES"/theme-*.css; do [ -f "$s" ] && head -n 3 "$s" | grep -q "$MARK" && n=$((n + 1)); done
    say "  stylesheets       $n"
    s=no; [ -f "$LIB" ] && lib_patched && s=yes; say "  in theme list     $s"
    s=no; [ -f "$TPL" ] && grep -q "<!-- $MARK -->" "$TPL" && s=yes; say "  template patched  $s"
    say "  default theme     $(get_default)"
    s=no; [ -f "$HOOK" ] && s=yes; say "  apt hook          $s"
    say "  pve-manager       $(dpkg-query -W -f='${Version}' pve-manager 2>/dev/null || echo '?')"
    say "  widget-toolkit    $(dpkg-query -W -f='${Version}' proxmox-widget-toolkit 2>/dev/null || echo '?')"
}

cmd_list() {
    local key file entry title light dark def
    def=$(get_default)
    printf '%-22s %-6s %s\n' NAME MODE TITLE
    while read -r key file; do
        load_theme "$file" 2>/dev/null || continue
        printf '%-22s %-6s %s%s%s\n' "$key" "${T[mode]}" "${T[name]}" "$([ "$file" = "$CUSTOM/$key.theme" ] && echo '  (yours)')" "$([ "$key" = "$def" ] && echo '  (default)')"
    done < <(theme_files 2>/dev/null)
    while IFS='|' read -r entry title light dark; do
        [ -n "$entry" ] && printf '%-22s %-6s %s%s\n' "$entry" auto "$title" "$([ "$entry" = "$def" ] && echo '  (default)')"
    done < <(auto_entries)
}

cmd_default() {
    need_root; need_pve
    local want=${1:-}
    [ -n "$want" ] || { say "default theme: $(get_default)"; return 0; }
    if [ "$want" != none ]; then
        [[ $want =~ $KEY_RE ]] || die "not a theme name: $want"
        cmd_list | awk 'NR>1 {print $1}' | grep -qx "$want" || die "no such theme: $want (see: marleybop-pve-theme list)"
    fi
    mkdir -p "$ETC"; echo "$want" > "$ETC/default"
    apply_all; reload_ui
    if [ "$want" = none ]; then say "Browsers on \"Default (auto)\" get Proxmox's own themes again."
    else say "Browsers on \"Default (auto)\" now get $want. Anyone who picked a theme keeps their choice."; fi
}

cmd_new() {
    need_root
    local key=${1:-} from=${2:-marleybop} src
    [[ $key =~ $KEY_RE ]] || die "usage: marleybop-pve-theme new <name> [copy-from]   (name: lowercase words of up to 10 letters joined by '-')"
    [ -f "$SHARE/themes/$key.theme" ] && die "a bundled theme is already called $key"
    src=$SHARE/themes/$from.theme; [ -f "$src" ] || src=$CUSTOM/$from.theme
    [ -f "$src" ] || die "no such theme to copy from: $from"
    mkdir -p "$CUSTOM"
    [ -f "$CUSTOM/$key.theme" ] && die "$CUSTOM/$key.theme already exists"
    {
        echo "# Your own theme. Edit the colours, then run: marleybop-pve-theme reapply"
        echo "# bg = page behind the panels, surface = panels, raised = buttons and chips,"
        echo "# sel/on_sel = selected tab and checked box, bar = usage bars and gauges."
        sed "s/^name=.*/name=$key/" "$src"
    } > "$CUSTOM/$key.theme"
    say "Created $CUSTOM/$key.theme (copied from $from)."
    say "Edit it, then run: marleybop-pve-theme reapply"
}

# Development: build every theme and the helper into $MB_WT_DIR/themes from $MB_STOCK, touching nothing else.
cmd_build_dev() {
    [ -n "${MB_WT_DIR:-}" ] && [ -f "$STOCK" ] || die "build-dev needs MB_WT_DIR (output) and MB_STOCK (a copy of theme-proxmox-dark.css)"
    mkdir -p "$THEMES"
    build_all
    install_assets
    say "$BUILT themes in $THEMES"
}

usage() {
    cat <<EOF
Marleybop themes $VERSION for Proxmox VE

  marleybop-pve-theme list                      the themes, and which one is the default
  marleybop-pve-theme default [<name>|none]     theme for browsers that have not picked one
  marleybop-pve-theme new <name> [copy-from]    start your own theme in $CUSTOM
  marleybop-pve-theme reapply                   rebuild everything (after editing a theme; the apt hook
                                                runs this after Proxmox updates)
  marleybop-pve-theme status                    show what is installed
  marleybop-pve-theme install [--default <name> | --no-default]
  marleybop-pve-theme uninstall                 remove every change

Each person picks their theme in the web UI: user menu > Color Theme. That dialog also has the
accent colour, corner, density and font options, which are saved per browser.
EOF
}

cmd=${1:-help}; shift || true
args=(); for a in "$@"; do if [ "$a" = --quiet ]; then QUIET=1; else args+=("$a"); fi; done
set -- "${args[@]+"${args[@]}"}"
case "$cmd" in
    install)   cmd_install "$@" ;;
    reapply)   cmd_reapply ;;
    uninstall) cmd_uninstall ;;
    status)    cmd_status ;;
    list)      cmd_list ;;
    default)   cmd_default "$@" ;;
    new)       cmd_new "$@" ;;
    build-dev) cmd_build_dev ;;
    help|-h|--help) usage ;;
    *) usage; exit 1 ;;
esac
