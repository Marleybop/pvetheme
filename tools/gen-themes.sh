#!/usr/bin/env bash
# Writes the bundled palettes in src/themes/ from the table below (one row per theme).
# Edit a row and re-run; hand-made themes for one node go in /etc/pvetheme/themes/ instead.
set -euo pipefail
mkdir -p "$(dirname "$0")/../src/themes"
cd "$(dirname "$0")/../src/themes"
rm -f ./*.theme index

FIELDS=(bg surface raised border border_strong text text2 muted accent on_accent link sel on_sel bar good warn bad bad_fill chart1 chart2 chart3 chart4 chart5 chart6)

t() {
    local key=$1 name=$2 mode=$3 i
    shift 3
    {
        echo "name=$name"
        echo "mode=$mode"
        local vals=("$@")
        for i in "${!FIELDS[@]}"; do
            echo "${FIELDS[$i]}=#${vals[$i]}"
        done
    } > "$key.theme"
    echo "theme $key" >> index
}

#  key                 name               mode  bg     surface raised border strong text   text2  muted  accent on_acc link   sel    on_sel bar    good   warn   bad    badfil chart1 chart2 chart3 chart4 chart5 chart6
t marleybop           "Marleybop Dark"   dark  111214 1c1e21 26292d 2b2e33 3a3e44 f6f5f2 b9bdc2 8c9198 c8452a ffffff e2683f f6f5f2 16181b b9bdc2 6db04a e0a93b ff8a80 e5534b b9bdc2 e2683f 6f9fc7 6db04a e0a93b 8c9198
t marleybop-light     "Marleybop Light"  light f6f5f2 ffffff e6e4df e0ddd7 d6d3cc 16181b 3a3e44 6b7078 c8452a ffffff a33620 16181b f6f5f2 3a3e44 3f7530 a86f00 b3261e c8372d 3a3e44 c8452a 3d6f9e 3f7530 a86f00 8c9198
t marleybop-black     "Marleybop Black"  dark  000000 0a0a0b 17181a 1f2124 2e3136 f6f5f2 b9bdc2 8c9198 c8452a ffffff e2683f f6f5f2 16181b b9bdc2 6db04a e0a93b ff8a80 e5534b b9bdc2 e2683f 6f9fc7 6db04a e0a93b 8c9198
t mb-nord-dark        "Nord Dark"        dark  272c36 2e3440 3b4252 3f4759 4c566a eceff4 d8dee9 9aa5b8 5e81ac ffffff 88c0d0 88c0d0 2e3440 81a1c1 a3be8c ebcb8b e08a92 bf616a 88c0d0 d08770 b48ead a3be8c ebcb8b 81a1c1
t mb-nord-light       "Nord Light"       light e5e9f0 f4f6f9 e5e9f0 d8dee9 b8c1d1 2e3440 434c5e 6b7689 5e81ac ffffff 4c6f9a 5e81ac ffffff 5e81ac 5f7a4a 9a6e12 a8424c bf616a 5e81ac c06a50 96708f 6f8a58 b08a2e 8fbcbb
t mb-dracula          "Dracula"          dark  21222c 282a36 343746 3a3d4d 44475a f8f8f2 d0d0dc 8f96b8 bd93f9 21222c 8be9fd bd93f9 21222c bd93f9 50fa7b f1fa8c ff6e6e ff5555 bd93f9 ff79c6 8be9fd 50fa7b ffb86c 6272a4
t mb-catppuccin-mocha "Catppuccin Mocha" dark  181825 1e1e2e 313244 313244 45475a cdd6f4 bac2de 9399b2 cba6f7 11111b 89b4fa cba6f7 11111b b4befe a6e3a1 f9e2af f38ba8 e06c8b 89b4fa f5c2e7 94e2d5 a6e3a1 fab387 9399b2
t mb-catppuccin-latte "Catppuccin Latte" light e6e9ef eff1f5 dce0e8 ccd0da bcc0cc 4c4f69 5c5f77 6c6f85 8839ef ffffff 1e66f5 8839ef ffffff 7287fd 40a02b b5730f d20f39 d20f39 1e66f5 ea76cb 179299 40a02b fe640b 8c8fa1
t mb-gruvbox-dark     "Gruvbox Dark"     dark  1d2021 282828 3c3836 3c3836 504945 ebdbb2 d5c4a1 a89984 d79921 1d2021 83a598 fabd2f 1d2021 d5c4a1 b8bb26 fabd2f fb4934 cc241d fabd2f fe8019 83a598 b8bb26 d3869b a89984
t mb-gruvbox-light    "Gruvbox Light"    light f2e5bc fbf1c7 ebdbb2 d5c4a1 bdae93 3c3836 504945 7c6f64 af3a03 fbf1c7 076678 af3a03 fbf1c7 7c6f64 79740e b57614 9d0006 cc241d b57614 af3a03 076678 79740e 8f3f71 928374
t mb-tokyo-night      "Tokyo Night"      dark  16161e 1a1b26 24283b 292e42 3b4261 c0caf5 a9b1d6 7f87b0 7aa2f7 16161e 7dcfff 7aa2f7 16161e 7aa2f7 9ece6a e0af68 f7768e db4b4b 7aa2f7 bb9af7 7dcfff 9ece6a ff9e64 737aa2
t mb-solarized-dark   "Solarized Dark"   dark  00222b 002b36 073642 0a4250 1c5462 eee8d5 93a1a1 839496 268bd2 fdf6e3 2aa198 268bd2 fdf6e3 93a1a1 859900 b58900 e8605d dc322f 268bd2 cb4b16 2aa198 859900 b58900 6c71c4
t mb-solarized-light  "Solarized Light"  light eee8d5 fdf6e3 eee8d5 e0d9c3 cfc8b0 073642 586e75 657b83 268bd2 fdf6e3 1f72ad 268bd2 fdf6e3 657b83 6b7a00 946f00 c12b28 dc322f 268bd2 cb4b16 2aa198 859900 b58900 6c71c4
t mb-github-dark      "GitHub Dark"      dark  010409 0d1117 21262d 30363d 484f58 e6edf3 c9d1d9 8d96a0 238636 ffffff 58a6ff 1f6feb ffffff 58a6ff 3fb950 d29922 ff7b72 da3633 58a6ff f78166 a371f7 3fb950 d29922 8d96a0
t mb-github-light     "GitHub Light"     light f6f8fa ffffff eaeef2 d8dee4 afb8c1 1f2328 424a53 656d76 1f883d ffffff 0969da 0969da ffffff 0969da 1a7f37 9a6700 cf222e cf222e 0969da bc4c00 8250df 1a7f37 9a6700 6e7781
t mb-rose-pine        "Rose Pine"        dark  191724 1f1d2e 26233a 312e45 403d52 e0def4 b4b0cc 908caa c4a7e7 191724 9ccfd8 c4a7e7 191724 ebbcba 9ccfd8 f6c177 eb6f92 d7557a c4a7e7 ebbcba 9ccfd8 31748f f6c177 908caa
t mb-rose-pine-dawn   "Rose Pine Dawn"   light f4ede8 fffaf3 f2e9e1 dfdad9 cecacd 575279 6a658a 797593 286983 ffffff 286983 907aa9 ffffff d7827e 3e8f8f b8771c b4637a b4637a 907aa9 d7827e 56949f 286983 ea9d34 9893a5
t mb-everforest-dark  "Everforest Dark"  dark  232a2e 2d353b 343f44 3d484d 4f585e d3c6aa c2b99f 9da9a0 a7c080 232a2e 7fbbb3 a7c080 232a2e a7c080 a7c080 dbbc7f e67e80 d0595c a7c080 e69875 7fbbb3 83c092 dbbc7f 859289
t mb-everforest-light "Everforest Light" light efebd4 fdf6e3 efebd4 e0dcc7 cfcab2 5c6a72 6f7b82 74826f 5f7d0a fdf6e3 2f7fae 5f7d0a fdf6e3 8da101 6b7d00 a37700 d9443f f85552 8da101 f57d26 3a94c5 35a77c dfa000 939f91
t mb-one-dark         "One Dark"         dark  21252b 282c34 2f343e 3a3f4b 4b5263 d7dae0 abb2bf 8b93a3 61afef 21252b 61afef 61afef 21252b 61afef 98c379 e5c07b e06c75 be5046 61afef c678dd 56b6c2 98c379 d19a66 5c6370
t mb-catppuccin-frappe "Catppuccin Frappe" dark  292c3c 303446 414559 414559 51576d c6d0f5 b5bfe2 949cbb ca9ee6 232634 8caaee ca9ee6 232634 babbf1 a6d189 e5c890 e78284 d0696b 8caaee f4b8e4 81c8be a6d189 ef9f76 949cbb
t mb-catppuccin-macchiato "Catppuccin Macchiato" dark 1e2030 24273a 363a4f 363a4f 494d64 cad3f5 b8c0e0 939ab7 c6a0f6 181926 8aadf4 c6a0f6 181926 b7bdf8 a6da95 eed49f ed8796 d86e7e 8aadf4 f5bde6 8bd5ca a6da95 f5a97f 939ab7
t mb-ayu-dark         "Ayu Dark"         dark  0b0e14 0f131a 1a1f29 1e232e 2d3340 e6e1cf bfbdb6 8a9199 e6b450 0b0e14 59c2ff e6b450 0b0e14 e6b450 aad94c ffb454 f07178 d95757 59c2ff ff8f40 d2a6ff aad94c e6b450 636a72
t mb-ayu-light        "Ayu Light"        light f3f4f5 fcfcfc eceef0 e3e6e9 cfd3d8 3c4043 5c6166 787b80 f29718 1a1a1a 2f8ad4 f29718 1a1a1a f29718 6c9900 c77f00 d6453f e65050 399ee6 fa8d3e a37acc 86b300 f2ae49 8a9199
t mb-monokai          "Monokai"          dark  1e1f1c 272822 3e3d32 3e3d32 57584f f8f8f2 cfcfc2 a59f85 a6e22e 1e1f1c 66d9ef a6e22e 1e1f1c e6db74 a6e22e e6db74 f92672 d81e5f 66d9ef f92672 ae81ff a6e22e fd971f 75715e
t mb-kanagawa         "Kanagawa"         dark  16161d 1f1f28 2a2a37 2a2a37 54546d dcd7ba c8c093 938f80 7e9cd8 16161d 7fb4ca 7e9cd8 16161d 7e9cd8 98bb6c e6c384 ff5d62 c34043 7e9cd8 957fb8 7aa89f 98bb6c ffa066 727169

# follow-the-system entries: key | title | light theme | dark theme
cat >> index <<'EOF'
auto marleybop-auto|Marleybop (auto)|marleybop-light|marleybop
auto mb-nord-auto|Nord (auto)|mb-nord-light|mb-nord-dark
auto mb-catppuccin-auto|Catppuccin (auto)|mb-catppuccin-latte|mb-catppuccin-mocha
auto mb-gruvbox-auto|Gruvbox (auto)|mb-gruvbox-light|mb-gruvbox-dark
auto mb-solarized-auto|Solarized (auto)|mb-solarized-light|mb-solarized-dark
auto mb-github-auto|GitHub (auto)|mb-github-light|mb-github-dark
auto mb-rose-pine-auto|Rose Pine (auto)|mb-rose-pine-dawn|mb-rose-pine
auto mb-everforest-auto|Everforest (auto)|mb-everforest-light|mb-everforest-dark
auto mb-ayu-auto|Ayu (auto)|mb-ayu-light|mb-ayu-dark
EOF

for f in *.theme; do
    k=${f%.theme}
    # the Proxmox server only accepts theme names of lowercase segments, 10 letters at most
    [[ $k =~ ^[a-z]{1,10}(-[a-z]{1,10}){0,5}$ ]] || { echo "bad key: $k" >&2; exit 1; }
    [ "$(wc -l < "$f")" = 26 ] || { echo "wrong field count: $f" >&2; exit 1; }
done
echo "$(ls ./*.theme | wc -l) themes written"
