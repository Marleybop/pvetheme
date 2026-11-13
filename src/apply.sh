#!/usr/bin/env bash
# pvetheme: Marleybop themes for Proxmox VE. Builds, applies, re-applies and removes the themes on one node.
# Installed as /usr/local/sbin/pvetheme by install.sh. Run with no arguments for help.
set -euo pipefail

SHARE=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
VERSION=${MB_VERSION:-$(cat "$SHARE/VERSION" 2>/dev/null || echo dev)}
MARK='marleybop-pvetheme'
REPO_RAW='https://raw.githubusercontent.com/Marleybop/pvetheme/main'

WT=${MB_WT_DIR:-/usr/share/javascript/proxmox-widget-toolkit}
THEMES=$WT/themes
LIB=$WT/proxmoxlib.js
STOCK=${MB_STOCK:-$THEMES/theme-proxmox-dark.css}
TPL=${MB_TPL:-/usr/share/pve-manager/index.html.tpl}
NODES=${MB_NODES_PM:-/usr/share/perl5/PVE/API2/Nodes.pm}
JS=$THEMES/marleybop-theme.js
ETC=${MB_ETC_DIR:-/etc/pvetheme}
CUSTOM=$ETC/themes
HOOK=${MB_APT_HOOK:-/etc/apt/apt.conf.d/99pvetheme}
BIN=${MB_BIN:-/usr/local/sbin/pvetheme}

# the Proxmox server only accepts theme names made of lowercase segments of at most 10 letters
KEY_RE='^[a-z]{1,10}(-[a-z]{1,10}){0,5}$'
COLOURS=(bg surface raised border border_strong text text2 muted accent on_accent link sel on_sel bar good warn bad bad_fill chart1 chart2 chart3 chart4 chart5 chart6)

QUIET=0
say()  { [ "$QUIET" = 1 ] || printf '%s\n' "$*"; }
ok()   { say "  ok    $*"; }
warn() { printf '  warn  %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

is_root() { [ -n "${MB_TEST:-}" ] || [ "$(id -u)" = 0 ]; }
need_root() { is_root || die "run this as root"; }
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

# ---------- node-wide options ------------------------------------------------
# $ETC/options holds key=value lines: the starting point for every browser (each can override).

opt_valid() { # opt_valid <key> <value>
    case "$1" in
        accent)   [[ $2 =~ ^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$ ]] ;;
        radius)   [[ $2 =~ ^(soft|sharp|round)$ ]] ;;
        density)  [[ $2 =~ ^(comfortable|compact)$ ]] ;;
        font)     [[ $2 =~ ^(inter|system|mono|custom)$ ]] ;;
        fontName) [[ $2 =~ ^[A-Za-z0-9\ ._-]{1,60}$ ]] ;;
        logo)     [[ $2 =~ ^(original|accent)$ ]] ;;
        *) return 1 ;;
    esac
}
options_json() {
    local k v out='' sep=''
    [ -f "$ETC/options" ] || { printf '{}'; return 0; }
    while IFS='=' read -r k v || [ -n "$k" ]; do
        v=${v%$'\r'}
        opt_valid "$k" "$v" || continue
        out+="$sep\"$k\":\"$v\""; sep=','
    done < "$ETC/options"
    printf '{%s}' "$out"
}
# The font file given to "pvetheme font", if any: prints its path.
font_file() { local f; for f in "$ETC"/userfont.*; do if [ -f "$f" ]; then echo "$f"; return 0; fi; done; return 0; }
font_family() { [ -f "$ETC/options" ] || return 0; sed -n 's/^fontName=//p' "$ETC/options" | head -n 1; }

# Writes one theme's stylesheet to stdout. Needs T loaded.
emit_theme() { # emit_theme <key>
    local key=$1 c ff
    printf '/*!%s*/\n' "${T[name]}"
    printf '/* %s %s: built on this node from theme-proxmox-dark.css, the Marleybop layer and the "%s" palette. Do not edit; run "pvetheme reapply". */\n' "$MARK" "$VERSION" "$key"
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
    # 4. the node's own font file, when one was given to "pvetheme font"
    ff=$(font_file)
    if [ -n "$ff" ] && [ -n "$(font_family)" ]; then
        printf '@font-face { font-family: "%s"; font-weight: 100 900; font-display: swap; src: url("marleybop-userfont.%s?v=%s"); }\n' "$(font_family)" "${ff##*.}" "$VERSION"
    fi
}

# Removes every stylesheet this tool generated (found by its marker line), leaving other themes alone.
remove_generated() {
    local f
    for f in "$THEMES"/theme-*.css; do
        [ -f "$f" ] || continue
        if head -n 3 "$f" | grep -q "$MARK"; then rm -f "$f"; fi
    done
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
    local f tmp ff
    for f in "$SHARE"/fonts/*.woff2; do
        tmp=$(mktemp); cat "$f" > "$tmp"; put "$tmp" "$THEMES/$(basename "$f")" || true
    done
    rm -f "$THEMES"/marleybop-userfont.*
    ff=$(font_file)
    if [ -n "$ff" ]; then tmp=$(mktemp); cat "$ff" > "$tmp"; put "$tmp" "$THEMES/marleybop-userfont.${ff##*.}" || true; fi
    tmp=$(mktemp)
    {
        printf '/* %s %s: generated, do not edit. */\n' "$MARK" "$VERSION"
        printf 'window.MarleybopThemes = { version: "%s", def: "%s", defaults: %s, themes: [%s] };\n' "$VERSION" "$(get_default)" "$(options_json)" "$MANIFEST"
        cat "$SHARE/marleybop-theme.js"
    } > "$tmp"
    put "$tmp" "$JS" || true
}

# ---------- the Proxmox files we edit ---------------------------------------

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
get_default() { cat "$ETC/default" 2>/dev/null || echo marleybop-auto; }

# The template gets three small edits, each one undone by clean_tpl:
#   1. a <script> line for the helper, after pvemanagerlib.js
#   2. "-mb<version>" added to the theme stylesheet's cache key, so an update reaches browsers
#   3. with a default theme: the line that loads Proxmox Dark for "Default (auto)" loads that theme
#      instead (its media attribute is parked in data-mb-media so it can be put back)
clean_tpl() { # stdin -> stdout
    sed -e "/<!-- $MARK -->/d" \
        -e '/\/pwt\/themes\/theme-/s/\(\[% wtversion %\]\)-mb[0-9A-Za-z.]*/\1/' \
        -e '/data-mb-media=/{s/ data-mb-media="\([^"]*\)"/ media="\1"/;s/theme-[a-z-]*\.css/theme-proxmox-dark.css/}'
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
            *) warn "default theme \"$def\" does not exist; leaving Proxmox's default. Fix with: pvetheme default <name>" ;;
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

# Temperatures on the node Summary: a block of Perl in the node status API (off unless asked for).
sensors_wanted() { [ "$(cat "$ETC/sensors" 2>/dev/null)" = on ]; }
nodes_patched() { [ -f "$NODES" ] && grep -q "# $MARK sensors\$" "$NODES"; }
reload_api() {
    [ -n "${MB_NO_RELOAD:-}" ] && return 0
    systemctl reload pvedaemon 2>/dev/null || systemctl restart pvedaemon 2>/dev/null || true
    systemctl reload pveproxy 2>/dev/null || systemctl restart pveproxy 2>/dev/null || true
}
# Returns 0 when the file was changed.
patch_nodes() {
    nodes_patched && return 1
    [ -f "$NODES" ] || { warn "$NODES not found; temperatures not enabled"; return 1; }
    grep -q '^[[:space:]]*my \$dinfo = df(' "$NODES" || { warn "this pve-manager version has a different node status code; temperatures not enabled, nothing changed"; return 1; }
    local tmp; tmp=$(mktemp --suffix=.pm)
    awk -v snippet="$SHARE/sensors.pl" '
        !done && /^[[:space:]]*my \$dinfo = df\(/ { while ((getline line < snippet) > 0) print line; print ""; done = 1 }
        { print }' "$NODES" > "$tmp"
    # never install a file Perl cannot compile
    if [ -z "${MB_TEST:-}" ] && ! perl -I/usr/share/perl5 -c "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"; warn "the patched node status code did not compile; temperatures not enabled, nothing changed"; return 1
    fi
    mkdir -p "$ETC/backup"; [ -f "$ETC/backup/Nodes.pm" ] || cp -p "$NODES" "$ETC/backup/Nodes.pm"
    put "$tmp" "$NODES"
}
unpatch_nodes() {
    nodes_patched || return 1
    local tmp; tmp=$(mktemp)
    # the block and the blank line added after it
    awk -v s="# $MARK sensors" -v e="# $MARK sensors END" '
        skip == 0 && index($0, s) && !index($0, e) { skip = 1; next }
        skip == 1 { if (index($0, e)) skip = 2; next }
        skip == 2 { skip = 0; if ($0 == "") next }
        { print }' "$NODES" > "$tmp"
    put "$tmp" "$NODES"
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
// pvetheme (Marleybop themes for Proxmox VE): put the themes back after a Proxmox package update replaces the patched files.
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

# Does everything; sets CHANGED=1 when one of the Proxmox files had to be edited.
CHANGED=0; API_CHANGED=0
apply_all() {
    CHANGED=0; API_CHANGED=0
    mkdir -p "$ETC" "$CUSTOM"
    backup_once
    build_all
    install_assets
    if patch_lib; then CHANGED=1; fi
    if patch_tpl; then CHANGED=1; fi
    if sensors_wanted; then
        if patch_nodes; then API_CHANGED=1; fi
    else
        if unpatch_nodes; then API_CHANGED=1; fi
    fi
    install_hook
}
reload_changed() { if [ "$API_CHANGED" = 1 ]; then reload_api; else reload_ui; fi; }

# ---------- commands ---------------------------------------------------------

cmd_install() {
    need_root; need_pve
    mkdir -p "$ETC"
    while [ $# -gt 0 ]; do
        case "$1" in
            --no-default) echo none > "$ETC/default" ;;
            --default) shift; [[ ${1:-} =~ $KEY_RE ]] || die "--default needs a theme name (see: pvetheme list)"; echo "$1" > "$ETC/default" ;;
            '') ;;
            *) die "unknown option: $1" ;;
        esac
        shift || true
    done
    say "pvetheme $VERSION: Marleybop themes for Proxmox VE"
    apply_all
    ok "$BUILT themes built from this node's Proxmox Dark, plus the follow-the-system entries"
    ok "fonts and helper script copied"
    ok "themes added to the Color Theme list"
    local def; def=$(get_default)
    if [ "$def" = none ]; then ok "page template updated"
    else ok "page template updated; browsers that have not picked a theme get $def"; fi
    ok "apt hook installed (themes return by themselves after Proxmox updates)"
    reload_changed; [ -n "${MB_NO_RELOAD:-}" ] || ok "web UI reloaded"
    say ""
    say "Done. In the web UI: your user name (top right) > Color Theme."
    say "If the old look stays, hard-refresh the browser once (Ctrl+Shift+R)."
    say "More: pvetheme help"
}

cmd_reapply() {
    is_root || exit 0
    # during a package removal or a half-finished upgrade the files may be missing: nothing to do
    [ -f "$TPL" ] && [ -f "$LIB" ] && [ -f "$STOCK" ] || exit 0
    apply_all
    if [ "$CHANGED" = 1 ] || [ "$API_CHANGED" = 1 ]; then reload_changed; say "Themes re-applied ($BUILT themes)."; else say "Themes are in place ($BUILT themes)."; fi
}

cmd_uninstall() {
    need_root
    say "Removing pvetheme"
    unpatch_lib; ok "removed from the Color Theme list"
    unpatch_tpl || true; ok "page template restored"
    if unpatch_nodes; then API_CHANGED=1; ok "temperature readout removed from the node status code"; fi
    remove_generated
    rm -f "$JS" "$THEMES"/marleybop-*.woff2 "$THEMES"/marleybop-userfont.*; ok "theme files removed"
    rm -f "$HOOK" "$BIN"; ok "apt hook removed"
    if ls "$CUSTOM"/*.theme >/dev/null 2>&1; then
        find "$ETC" -mindepth 1 -maxdepth 1 ! -name themes -exec rm -rf {} +
        ok "your own themes kept in $CUSTOM"
    else
        rm -rf "$ETC"
    fi
    reload_changed; [ -n "${MB_NO_RELOAD:-}" ] || ok "web UI reloaded"
    case "$SHARE" in */pvetheme) rm -rf "$SHARE" ;; esac
    say ""
    say "Done. Browsers that had one of these themes selected fall back to the default theme."
}

cmd_status() {
    local s n
    say "pvetheme $VERSION"
    n=0; for s in "$THEMES"/theme-*.css; do [ -f "$s" ] && head -n 3 "$s" | grep -q "$MARK" && n=$((n + 1)); done
    say "  stylesheets       $n"
    s=no; [ -f "$LIB" ] && lib_patched && s=yes; say "  in theme list     $s"
    s=no; [ -f "$TPL" ] && grep -q "<!-- $MARK -->" "$TPL" && s=yes; say "  template patched  $s"
    say "  default theme     $(get_default)"
    say "  node options      $(options_json)"
    s=off; nodes_patched && s=on; say "  temperatures      $s"
    s=no; [ -f "$HOOK" ] && s=yes; say "  apt hook          $s"
    say "  pve-manager       $(dpkg-query -W -f='${Version}' pve-manager 2>/dev/null || echo '?')"
    say "  widget-toolkit    $(dpkg-query -W -f='${Version}' proxmox-widget-toolkit 2>/dev/null || echo '?')"
}

cmd_list() {
    local key file entry title light dark def
    def=$(get_default)
    printf '%-24s %-6s %s\n' NAME MODE TITLE
    while read -r key file; do
        load_theme "$file" 2>/dev/null || continue
        printf '%-24s %-6s %s%s%s\n' "$key" "${T[mode]}" "${T[name]}" "$([ "$file" = "$CUSTOM/$key.theme" ] && echo '  (yours)')" "$([ "$key" = "$def" ] && echo '  (default)')"
    done < <(theme_files 2>/dev/null)
    while IFS='|' read -r entry title light dark; do
        [ -n "$entry" ] && printf '%-24s %-6s %s%s\n' "$entry" auto "$title" "$([ "$entry" = "$def" ] && echo '  (default)')"
    done < <(auto_entries)
}

cmd_default() {
    need_root; need_pve
    local want=${1:-}
    [ -n "$want" ] || { say "default theme: $(get_default)"; return 0; }
    if [ "$want" != none ]; then
        [[ $want =~ $KEY_RE ]] || die "not a theme name: $want"
        cmd_list > "$ETC/.list" 2>/dev/null || true
        awk 'NR>1 {print $1}' "$ETC/.list" | grep -qx "$want" || { rm -f "$ETC/.list"; die "no such theme: $want (see: pvetheme list)"; }
        rm -f "$ETC/.list"
    fi
    mkdir -p "$ETC"; echo "$want" > "$ETC/default"
    apply_all; reload_changed
    if [ "$want" = none ]; then say "Browsers that have not picked a theme get Proxmox's own themes again."
    else say "Browsers that have not picked a theme now get $want. Anyone who picked one keeps their choice."; fi
}

cmd_new() {
    need_root
    local key=${1:-} from=${2:-marleybop} src
    [[ $key =~ $KEY_RE ]] || die "usage: pvetheme new <name> [copy-from]   (name: lowercase words of up to 10 letters joined by '-')"
    [ -f "$SHARE/themes/$key.theme" ] && die "a bundled theme is already called $key"
    src=$SHARE/themes/$from.theme; [ -f "$src" ] || src=$CUSTOM/$from.theme
    [ -f "$src" ] || die "no such theme to copy from: $from"
    mkdir -p "$CUSTOM"
    [ -f "$CUSTOM/$key.theme" ] && die "$CUSTOM/$key.theme already exists"
    {
        echo "# Your own theme. Edit the colours, then run: pvetheme reapply"
        echo "# bg = page behind the panels, surface = panels, raised = buttons and chips,"
        echo "# sel/on_sel = selected tab and checked box, bar = usage bars and gauges."
        sed "s/^name=.*/name=$key/" "$src"
    } > "$CUSTOM/$key.theme"
    say "Created $CUSTOM/$key.theme (copied from $from)."
    say "Edit it, then run: pvetheme reapply"
}

# pvetheme options [key=value ... | reset]: the starting options for every browser on this node
cmd_options() {
    need_root; need_pve
    [ $# -gt 0 ] || { say "node options: $(options_json)"; say "set with: pvetheme options accent=#3b82f6 radius=round density=compact font=system   (or: reset)"; return 0; }
    mkdir -p "$ETC"
    local pair k v tmp
    if [ "$1" = reset ]; then rm -f "$ETC/options" "$ETC"/userfont.*
    else
        for pair in "$@"; do
            k=${pair%%=*}; v=${pair#*=}
            opt_valid "$k" "$v" || die "not a valid option: $pair   (accent=#rrggbb radius=soft|sharp|round density=comfortable|compact font=inter|system|mono logo=original|accent)"
            tmp=$(mktemp); { grep -v "^$k=" "$ETC/options" 2>/dev/null || true; echo "$k=$v"; } > "$tmp"; cat "$tmp" > "$ETC/options"; rm -f "$tmp"
        done
    fi
    apply_all; reload_changed
    say "Node options are now: $(options_json)"
    say "Browsers where someone set their own options keep those."
}

# pvetheme font <family> [file] | none: a font for every browser on this node
cmd_font() {
    need_root; need_pve
    local family=${1:-} file=${2:-} ext
    [ -n "$family" ] || { say "font: $(font_family || true)$(f=$(font_file); [ -n "$f" ] && echo "  (file: $f)")"; say "set with: pvetheme font \"Family Name\" [file.woff2|.woff|.ttf]   (or: none)"; return 0; }
    mkdir -p "$ETC"
    rm -f "$ETC"/userfont.*
    if [ "$family" = none ]; then
        if [ -f "$ETC/options" ]; then sed -i '/^font=/d;/^fontName=/d' "$ETC/options"; fi
    else
        opt_valid fontName "$family" || die "font family may only have letters, digits, spaces and ._-"
        if [ -n "$file" ]; then
            [ -f "$file" ] || die "no such file: $file"
            ext=${file##*.}; ext=${ext,,}
            case "$ext" in woff2|woff|ttf) ;; *) die "font file must be .woff2, .woff or .ttf" ;; esac
            [ "$(wc -c < "$file")" -le 4194304 ] || die "font file is larger than 4 MB"
            cp "$file" "$ETC/userfont.$ext"
        fi
        { grep -v -e '^font=' -e '^fontName=' "$ETC/options" 2>/dev/null || true; echo "font=custom"; echo "fontName=$family"; } > "$ETC/options.new"
        mv "$ETC/options.new" "$ETC/options"
    fi
    apply_all; reload_changed
    if [ "$family" = none ]; then say "Font back to the themes' own (Inter)."
    elif [ -n "$file" ]; then say "Font set to \"$family\", served from this node."
    else say "Font set to \"$family\". It shows on computers that have that font installed."; fi
}

cmd_sensors() {
    need_root; need_pve
    case "${1:-status}" in
        on)
            ls /sys/class/hwmon/hwmon*/temp*_input >/dev/null 2>&1 || [ -n "${MB_TEST:-}" ] || die "this machine exposes no temperature sensors (/sys/class/hwmon is empty)"
            mkdir -p "$ETC"; echo on > "$ETC/sensors"
            apply_all
            nodes_patched || { echo off > "$ETC/sensors"; die "temperatures could not be enabled; nothing was changed"; }
            reload_api
            if [ -z "${MB_TEST:-}" ] && ! pvesh get "/nodes/$(hostname -s)/status" --output-format json 2>/dev/null | grep -q 'marleybop-sensors'; then
                echo off > "$ETC/sensors"; unpatch_nodes || true; reload_api
                die "the node status API did not answer with temperatures after the change; it was undone"
            fi
            say "Temperatures are on: open a node's Summary (hard-refresh the browser once)."
            ;;
        off)
            mkdir -p "$ETC"; echo off > "$ETC/sensors"
            apply_all; reload_changed
            say "Temperatures are off; the node status code is back to stock."
            ;;
        status) if nodes_patched; then say "temperatures: on"; else say "temperatures: off   (turn on with: pvetheme sensors on)"; fi ;;
        *) die "usage: pvetheme sensors on|off|status" ;;
    esac
}

cmd_check() {
    local remote
    remote=$(curl -fsSL --max-time 15 "$REPO_RAW/VERSION" 2>/dev/null | tr -d ' \r\n') || die "could not reach GitHub"
    if [ "$remote" = "$VERSION" ]; then say "pvetheme $VERSION is the newest version."
    else say "pvetheme $remote is available (installed: $VERSION). Update with: pvetheme update"; fi
}
cmd_update() {
    need_root
    local tmp; tmp=$(mktemp)
    curl -fsSL --max-time 60 "$REPO_RAW/dist/install.sh" -o "$tmp" || { rm -f "$tmp"; die "could not download the installer"; }
    bash "$tmp" install; rm -f "$tmp"
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
pvetheme $VERSION: Marleybop themes for Proxmox VE

Everyone picks their theme in the web UI: your user name (top right) > Color Theme.

  pvetheme list                      the themes, and which one is the default
  pvetheme default [<name>|none]     theme for browsers that have not picked one
  pvetheme options [key=value ...]   starting accent, corners, density, font and logo for every browser
  pvetheme font "<family>" [file]    a font for every browser; with a file it is served from this node
  pvetheme sensors on|off            temperatures and fans on the node Summary
  pvetheme new <name> [copy-from]    start your own theme in $CUSTOM
  pvetheme reapply                   rebuild everything (after editing a theme)
  pvetheme status                    what is installed
  pvetheme check | update            look for, or install, a newer version
  pvetheme uninstall                 remove every change
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
    options)   cmd_options "$@" ;;
    font)      cmd_font "$@" ;;
    sensors)   cmd_sensors "$@" ;;
    new)       cmd_new "$@" ;;
    check)     cmd_check ;;
    update)    cmd_update ;;
    build-dev) cmd_build_dev ;;
    help|-h|--help) usage ;;
    *) usage; exit 1 ;;
esac
