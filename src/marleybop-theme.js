/* Marleybop theme engine for Proxmox VE: browser helper.
 *
 * 1. Applies the per-browser options (accent, corners, density, font) as CSS variables.
 * 2. Recolours the RRD charts, whose series colours are hard-coded in pvemanagerlib.js.
 * 3. Replaces the one-dropdown "Color Theme" dialog with a picker: theme cards with a live
 *    preview, plus the options. If anything in it fails, the stock dialog opens instead.
 *
 * Parts 1 and 2 do nothing unless one of this engine's themes is active (it sets --mb-theme).
 * install.sh prepends "window.MarleybopThemes = {version, themes}" to this file.
 */
(function () {
    // no 'use strict' here: ExtJS's callParent() finds its caller through function.caller
    if (!window.Ext || !window.getComputedStyle) {
        return;
    }
    var MB = window.MarleybopThemes || { version: '0', themes: [] };
    var STORE_KEY = 'marleybop-theme-options';
    var root = document.documentElement;

    var css = function (name) {
        return getComputedStyle(root).getPropertyValue(name).trim();
    };
    var active = function () {
        return css('--mb-theme') !== '';
    };
    var themeByKey = function (key) {
        for (var i = 0; i < MB.themes.length; i++) {
            if (MB.themes[i].key === key) {
                return MB.themes[i];
            }
        }
        return null;
    };

    /* ---------- options ---------------------------------------------------- */

    var FONTS = {
        inter: null, // the theme's own
        system: 'system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
        mono: '"Marleybop Mono", "JetBrains Mono", ui-monospace, "Cascadia Mono", Consolas, monospace',
    };
    var RADII = { sharp: ['0px', '0px'], soft: ['4px', '8px'], round: ['8px', '12px'] };

    var loadOptions = function () {
        try {
            var o = JSON.parse(window.localStorage.getItem(STORE_KEY) || '{}');
            return o && typeof o === 'object' ? o : {};
        } catch (e) {
            return {};
        }
    };
    var saveOptions = function (o) {
        try {
            window.localStorage.setItem(STORE_KEY, JSON.stringify(o));
        } catch (e) {
            /* private mode: options last for this page only */
        }
    };
    var validHex = function (v) {
        return typeof v === 'string' && /^#([0-9a-f]{3}|[0-9a-f]{6})$/i.test(v);
    };
    // black or white, whichever reads better on the colour
    var onColour = function (hex) {
        var h = hex.replace('#', '');
        if (h.length === 3) {
            h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
        }
        var lin = function (i) {
            var c = parseInt(h.substr(i, 2), 16) / 255;
            return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
        };
        var L = 0.2126 * lin(0) + 0.7152 * lin(2) + 0.0722 * lin(4);
        return L > 0.4 ? '#16181b' : '#ffffff';
    };
    var setVar = function (name, value) {
        if (value === null || value === undefined || value === '') {
            root.style.removeProperty(name);
        } else {
            root.style.setProperty(name, value);
        }
    };
    // themeKey: the theme the options are shown on (for whether "selected" follows the accent)
    var applyOptions = function (o, themeKey) {
        o = o || {};
        var accent = validHex(o.accent) ? o.accent : null;
        setVar('--mb-accent', accent);
        setVar('--mb-on-accent', accent ? onColour(accent) : null);
        var t = themeByKey(themeKey === '__default__' || !themeKey ? MB.def : themeKey);
        if (t && t.mode === 'auto') {
            t = themeByKey(window.matchMedia('(prefers-color-scheme: dark)').matches ? t.dark : t.light);
        }
        // themes whose selected tab uses the accent keep doing so with a custom accent
        var follows = accent && t && t.sel && t.accent && t.sel.toLowerCase() === t.accent.toLowerCase();
        setVar('--mb-sel', follows ? accent : null);
        setVar('--mb-on-sel', follows ? onColour(accent) : null);
        var r = RADII[o.radius];
        setVar('--mb-radius', r ? r[0] : null);
        setVar('--mb-radius-lg', r ? r[1] : null);
        var font = null;
        if (o.font === 'custom' && typeof o.fontName === 'string' && /^[\w .-]{1,60}$/.test(o.fontName)) {
            font = '"' + o.fontName + '", ' + FONTS.system;
        } else if (FONTS[o.font]) {
            font = FONTS[o.font];
        }
        setVar('--mb-font', font);
        if (o.density === 'compact') {
            root.setAttribute('data-mb-density', 'compact');
        } else {
            root.removeAttribute('data-mb-density');
        }
    };

    var currentKey = function () {
        var m = document.cookie.match(/(?:^|;\s*)PVEThemeCookie=([^;]*)/);
        return m ? decodeURIComponent(m[1]) : '';
    };
    applyOptions(loadOptions(), currentKey() || css('--mb-theme'));

    /* ---------- charts ----------------------------------------------------- */

    // stock series colour -> slot in the theme's chart palette (--mb-chart-N)
    var slots = {
        '#94ae0a': 1, '#115fa6': 2, '#c4c0c0': 3, '#24ad9a': 4, '#bbde0d': 5,
        '#ffd13e': 1, '#a61120': 2, '#cfcfcf': 6, '#3892d4': 3, '#21bf4b': 4, '#ffcc00': 5, '#ff6c59': 2,
    };
    var remap = function (colors) {
        var pal = [];
        for (var i = 1; i <= 6; i++) {
            pal.push(css('--mb-chart-' + i));
        }
        return colors.map(function (c, n) {
            var slot = slots[String(c).toLowerCase()];
            return (slot && pal[slot - 1]) || pal[n % pal.length] || c;
        });
    };

    /* ---------- the Color Theme dialog ------------------------------------- */

    var STOCK_CARDS = {
        __default__: { title: 'Proxmox default (auto)', mode: 'auto', lightT: { bg: '#f5f5f5', surface: '#ffffff', border: '#cfcfcf', text: '#000000', muted: '#666666', accent: '#3892d4' }, darkT: { bg: '#1a1a1a', surface: '#262626', border: '#404040', text: '#f2f2f2', muted: '#8c8c8c', accent: '#0060a4' } },
        crisp: { bg: '#f5f5f5', surface: '#ffffff', border: '#cfcfcf', text: '#000000', muted: '#666666', accent: '#3892d4' },
        'proxmox-dark': { bg: '#1a1a1a', surface: '#262626', border: '#404040', text: '#f2f2f2', muted: '#8c8c8c', accent: '#0060a4' },
    };
    var ACCENTS = ['#c8452a', '#e2683f', '#d79921', '#6db04a', '#2aa198', '#3b82f6', '#5e81ac', '#8b5cf6', '#d6589f', '#8c9198'];

    var esc = function (s) {
        return Ext.String.htmlEncode(String(s));
    };
    var half = function (t) {
        return (
            '<div class="mb-card-page" style="background:' + t.bg + '">' +
            '<div class="mb-card-panel" style="background:' + t.surface + ';border-color:' + t.border + '">' +
            '<i style="background:' + t.text + ';width:58%"></i>' +
            '<i style="background:' + t.muted + ';width:80%"></i>' +
            '<i style="background:' + t.muted + ';width:44%"></i>' +
            '<b style="background:' + t.accent + '"></b>' +
            '</div></div>'
        );
    };
    var cardHtml = function (rec) {
        var inner;
        if (rec.lightT && rec.darkT) {
            inner = '<div class="mb-card-split">' + half(rec.lightT) + half(rec.darkT) + '</div>';
        } else if (rec.bg) {
            inner = half(rec);
        } else {
            inner = '<div class="mb-card-page mb-card-unknown"></div>';
        }
        return inner + '<div class="mb-card-name">' + esc(rec.title) + '</div>';
    };

    var buildCards = function () {
        var cards = [];
        var seen = {};
        var push = function (key, data) {
            if (!seen[key]) {
                seen[key] = true;
                data.key = key;
                data.html = cardHtml(data);
                cards.push(data);
            }
        };
        var own = function (t) {
            var d = Ext.apply({}, t);
            if (t.mode === 'auto') {
                d.lightT = themeByKey(t.light);
                d.darkT = themeByKey(t.dark);
            }
            d.group = 1;
            return d;
        };
        // "Default" first: what a browser gets when it has not picked anything. The node's admin
        // may have pointed that at one of these themes (marleybop-pve-theme default <name>).
        var def = themeByKey(MB.def);
        if (def) {
            push('__default__', Ext.apply(own(def), { title: 'Default: ' + def.title }));
        } else {
            push('__default__', Ext.apply({ group: 2 }, STOCK_CARDS.__default__));
        }
        // then Marleybop, the rest of the engine's themes, and whatever else is installed
        MB.themes.forEach(function (t) {
            if (t.key.indexOf('marleybop') === 0) {
                push(t.key, own(t));
            }
        });
        MB.themes.forEach(function (t) {
            push(t.key, own(t));
        });
        Ext.Object.each(Proxmox.Utils.theme_map, function (key, title) {
            push(key, Ext.apply({ title: title, group: 2 }, STOCK_CARDS[key] || {}));
        });
        return cards;
    };

    var injectDialogCss = function () {
        if (document.getElementById('mb-dialog-css')) {
            return;
        }
        var s = document.createElement('style');
        s.id = 'mb-dialog-css';
        s.textContent = [
            '.mb-cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(132px,1fr));gap:10px;padding:12px}',
            '.mb-card{cursor:pointer;border-radius:8px;padding:5px;border:2px solid transparent;outline:none}',
            '.mb-card:hover{background:rgba(128,128,128,.14)}',
            '.mb-card.mb-card-on{border-color:currentColor}',
            '.mb-card-page{height:72px;border-radius:5px;padding:9px 9px 0;box-sizing:border-box;overflow:hidden;border:1px solid rgba(128,128,128,.35)}',
            '.mb-card-split{display:flex;border-radius:5px;overflow:hidden;border:1px solid rgba(128,128,128,.35)}',
            '.mb-card-split .mb-card-page{flex:1;border:0;border-radius:0;padding:9px 6px 0}',
            '.mb-card-panel{height:100%;border:1px solid;border-bottom:0;border-radius:4px 4px 0 0;padding:8px 8px 0;box-sizing:border-box;position:relative}',
            '.mb-card-panel i{display:block;height:4px;border-radius:2px;margin-bottom:5px;opacity:.9}',
            '.mb-card-panel i+i{opacity:.55}',
            '.mb-card-panel b{position:absolute;right:7px;bottom:7px;width:22px;height:9px;border-radius:2px}',
            '.mb-card-unknown{background:repeating-linear-gradient(45deg,rgba(128,128,128,.25) 0 6px,transparent 6px 12px)}',
            '.mb-card-name{font-size:12px;font-weight:600;padding:6px 2px 1px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
            '.mb-swatches{display:flex;gap:6px;align-items:center;flex-wrap:wrap}',
            '.mb-swatch{width:20px;height:20px;border-radius:50%;cursor:pointer;border:2px solid transparent;box-shadow:0 0 0 1px rgba(128,128,128,.5);box-sizing:border-box}',
            '.mb-swatch.mb-swatch-on{border-color:currentColor;box-shadow:0 0 0 2px rgba(128,128,128,.25)}',
            '.mb-swatch-auto{background:conic-gradient(#c8452a,#e0a93b,#6db04a,#3b82f6,#8b5cf6,#c8452a)}',
            '.mb-note{opacity:.7;font-size:12px}',
        ].join('\n');
        document.head.appendChild(s);
    };

    // Swaps the theme stylesheet without a reload, for the preview. Returns a function that undoes it.
    var previewLink = null;
    var parked = [];
    var preview = function (key) {
        if (!previewLink) {
            Ext.Array.each(document.querySelectorAll('link[rel="stylesheet"][href*="/pwt/themes/theme-"]'), function (l) {
                parked.push(l);
                l.disabled = true;
            });
            previewLink = document.createElement('link');
            previewLink.rel = 'stylesheet';
            previewLink.id = 'mb-preview';
            document.head.appendChild(previewLink);
        }
        if (key === 'crisp') {
            previewLink.disabled = true;
        } else {
            var file = key;
            if (key === '__default__') {
                file = themeByKey(MB.def) ? MB.def : (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'proxmox-dark' : null);
            }
            if (file === null) {
                previewLink.disabled = true;
            } else {
                previewLink.disabled = false;
                previewLink.href = '/pwt/themes/theme-' + file + '.css?ver=mb' + MB.version;
            }
        }
    };
    var endPreview = function () {
        if (previewLink) {
            previewLink.parentNode.removeChild(previewLink);
            previewLink = null;
        }
        parked.forEach(function (l) {
            l.disabled = false;
        });
        parked = [];
    };

    var defineDialog = function () {
        Ext.define('Marleybop.window.Appearance', {
            extend: 'Ext.window.Window',
            alias: 'widget.marleybopAppearance',

            cookieName: 'PVEThemeCookie',
            title: gettext('Color Theme'),
            modal: true,
            width: 800,
            height: 620,
            minWidth: 520,
            minHeight: 420,
            layout: { type: 'vbox', align: 'stretch' },
            bodyPadding: 0,

            initComponent: function () {
                var me = this;
                injectDialogCss();
                // options0 is set when Reset reopens the dialog: start clean, Cancel still returns to what was saved
                me.saved = me.options0 || loadOptions();
                me.options = me.options0 ? {} : Ext.apply({}, me.saved);
                var cookie = Ext.util.Cookies.get(me.cookieName);
                me.cards = buildCards();
                me.themeKey = '__default__';
                me.cards.forEach(function (c) {
                    if (c.key === cookie) {
                        me.themeKey = cookie;
                    }
                });
                me.startKey = me.themeKey;

                var store = Ext.create('Ext.data.Store', {
                    fields: ['key', 'title', 'html', 'group'],
                    data: me.cards,
                });
                me.view = Ext.create('Ext.view.View', {
                    flex: 1,
                    scrollable: 'y',
                    store: store,
                    cls: 'mb-cards-wrap',
                    tpl: '<div class="mb-cards"><tpl for="."><div class="mb-card" tabindex="0" data-qtip="{title:htmlEncode}">{html}</div></tpl></div>',
                    itemSelector: 'div.mb-card',
                    selectedItemCls: 'mb-card-on',
                    overItemCls: '',
                    singleSelect: true,
                    listeners: {
                        selectionchange: function (v, sel) {
                            if (sel.length) {
                                me.themeKey = sel[0].get('key');
                                preview(me.themeKey);
                                applyOptions(me.options, me.themeKey);
                            }
                        },
                        viewready: function (v) {
                            var rec = store.findRecord('key', me.themeKey, 0, false, true, true);
                            if (rec) {
                                v.getSelectionModel().select(rec, false, true);
                                var node = v.getNode(rec);
                                if (node && node.scrollIntoView) {
                                    node.scrollIntoView({ block: 'nearest' });
                                }
                            }
                        },
                    },
                });

                var swatches = ['<span class="mb-swatch mb-swatch-auto" data-accent="" data-qtip="' + esc(gettext('Theme default')) + '"></span>']
                    .concat(ACCENTS.map(function (a) {
                        return '<span class="mb-swatch" data-accent="' + a + '" style="background:' + a + '" data-qtip="' + a + '"></span>';
                    })).join('');
                var seg = function (name, items) {
                    return {
                        xtype: 'segmentedbutton',
                        allowMultiple: false,
                        value: me.options[name] || items[0][0],
                        items: items.map(function (i) {
                            return { text: i[1], value: i[0], minWidth: 80 };
                        }),
                        listeners: {
                            change: function (b, value) {
                                me.setOption(name, Ext.isArray(value) ? value[0] : value);
                            },
                        },
                    };
                };

                me.items = [
                    me.view,
                    {
                        xtype: 'form',
                        border: false,
                        bodyPadding: '10 14 4 14',
                        cls: 'mb-options',
                        fieldDefaults: { labelWidth: 90 },
                        items: [
                            {
                                xtype: 'fieldcontainer',
                                fieldLabel: gettext('Accent'),
                                layout: { type: 'hbox', align: 'middle' },
                                items: [
                                    {
                                        xtype: 'component',
                                        itemId: 'swatches',
                                        cls: 'mb-swatches',
                                        html: swatches,
                                        listeners: {
                                            afterrender: function (c) {
                                                c.el.on('click', function (ev, t) {
                                                    me.down('#accentHex').setValue(t.getAttribute('data-accent'));
                                                }, null, { delegate: '.mb-swatch' });
                                                me.markSwatch();
                                            },
                                        },
                                    },
                                    {
                                        xtype: 'textfield',
                                        itemId: 'accentHex',
                                        width: 96,
                                        margin: '0 0 0 12',
                                        emptyText: '#c8452a',
                                        value: me.options.accent || '',
                                        maxLength: 7,
                                        validator: function (v) {
                                            return v === '' || validHex(v) ? true : '#rrggbb';
                                        },
                                        listeners: {
                                            change: function (f, v) {
                                                if (v === '' || validHex(v)) {
                                                    me.setOption('accent', v);
                                                    me.markSwatch();
                                                }
                                            },
                                        },
                                    },
                                ],
                            },
                            {
                                xtype: 'fieldcontainer',
                                fieldLabel: gettext('Corners'),
                                items: [seg('radius', [['soft', 'Soft'], ['sharp', 'Sharp'], ['round', 'Round']])],
                            },
                            {
                                xtype: 'fieldcontainer',
                                fieldLabel: gettext('Density'),
                                items: [seg('density', [['comfortable', 'Comfortable'], ['compact', 'Compact']])],
                            },
                            {
                                xtype: 'fieldcontainer',
                                fieldLabel: gettext('Font'),
                                layout: { type: 'hbox', align: 'middle' },
                                items: [
                                    seg('font', [['inter', 'Inter'], ['system', 'System'], ['mono', 'Mono'], ['custom', 'Other']]),
                                    {
                                        xtype: 'textfield',
                                        itemId: 'fontName',
                                        width: 170,
                                        margin: '0 0 0 12',
                                        emptyText: gettext('a font on this computer'),
                                        value: me.options.fontName || '',
                                        hidden: me.options.font !== 'custom',
                                        listeners: {
                                            change: function (f, v) {
                                                me.setOption('fontName', v);
                                            },
                                        },
                                    },
                                ],
                            },
                            {
                                xtype: 'component',
                                cls: 'mb-note',
                                margin: '2 0 6 0',
                                html: gettext('Accent, corners, density and font are saved in this browser and apply to the themes with a preview card.'),
                            },
                        ],
                    },
                ];
                me.buttons = [
                    {
                        text: gettext('Reset'),
                        ui: 'default-toolbar',
                        handler: function () {
                            var saved = me.saved;
                            me.applied = true; // keep this close from restoring the old options
                            me.close();
                            endPreview();
                            applyOptions({}, me.startKey);
                            Ext.create('Marleybop.window.Appearance', { cookieName: me.cookieName, options0: saved }).show();
                        },
                    },
                    '->',
                    {
                        text: gettext('Cancel'),
                        ui: 'default-toolbar',
                        handler: function () {
                            me.close();
                        },
                    },
                    {
                        text: gettext('Apply'),
                        handler: function () {
                            me.applied = true;
                            saveOptions(me.options);
                            var expire = Ext.Date.add(new Date(), Ext.Date.YEAR, 10);
                            Ext.util.Cookies.set(me.cookieName, me.themeKey, expire);
                            me.mask(gettext('Please wait...'), 'x-mask-loading');
                            window.location.reload();
                        },
                    },
                ];
                me.callParent();
                me.on('close', function () {
                    if (!me.applied) {
                        endPreview();
                        applyOptions(me.saved, me.startKey);
                    }
                });
            },

            setOption: function (name, value) {
                var me = this;
                if (value === '' || value === undefined || value === null) {
                    delete me.options[name];
                } else {
                    me.options[name] = value;
                }
                if (name === 'font') {
                    me.down('#fontName').setHidden(value !== 'custom');
                }
                applyOptions(me.options, me.themeKey);
            },

            markSwatch: function () {
                var me = this;
                var c = me.down('#swatches');
                if (!c || !c.el) {
                    return;
                }
                var cur = (me.options.accent || '').toLowerCase();
                Ext.Array.each(c.el.dom.querySelectorAll('.mb-swatch'), function (n) {
                    n.classList.toggle('mb-swatch-on', n.getAttribute('data-accent') === cur);
                });
            },
        });

        // "Color Theme" in the user menu creates this stock window; show ours in its place
        Ext.define('Marleybop.override.ThemeEditWindow', {
            override: 'Proxmox.window.ThemeEditWindow',
            show: function () {
                var me = this;
                if (!me.mbFallback) {
                    try {
                        Ext.create('Marleybop.window.Appearance', { cookieName: me.cookieName }).show();
                        me.destroy();
                        return me;
                    } catch (e) {
                        me.mbFallback = true;
                        endPreview();
                        if (window.console) {
                            console.warn('Marleybop themes: picker failed, using the stock dialog', e);
                        }
                    }
                }
                return me.callParent(arguments);
            },
        });
    };

    Ext.onReady(function () {
        try {
            if (Ext.ClassManager.get('Proxmox.widget.RRDChart')) {
                Ext.define('Marleybop.override.RRDChart', {
                    override: 'Proxmox.widget.RRDChart',
                    // the series are added in initComponent and take their colours from the chart
                    initComponent: function () {
                        if (active() && this.config) {
                            // ExtJS reads a chart's colours from config.colors; charts without
                            // their own list fall back to the olive/blue chart theme
                            var own = this.config.colors;
                            this.config.colors = remap(own && own.length ? own : ['#94ae0a', '#115fa6', '#c4c0c0', '#24ad9a', '#bbde0d', '#3892d4']);
                            // a solid line over a light fill instead of a 60% slab of colour
                            var fill = parseFloat(css('--mb-chart-fill-opacity'));
                            if (!this.seriesConfig && fill > 0) {
                                this.seriesConfig = { style: { lineWidth: 1.5, opacity: 1, fillOpacity: fill } };
                            }
                        }
                        this.callParent(arguments);
                    },
                });
            }
        } catch (e) {
            if (window.console) {
                console.warn('Marleybop themes: chart colours not applied', e);
            }
        }

        try {
            if (Ext.ClassManager.get('Proxmox.window.ThemeEditWindow') && MB.themes.length) {
                defineDialog();
            }
        } catch (e) {
            if (window.console) {
                console.warn('Marleybop themes: picker not available', e);
            }
        }

        if (active() && document.fonts && document.fonts.ready) {
            document.fonts.ready.then(function () {
                try {
                    Ext.ComponentQuery.query('viewport').forEach(function (v) {
                        v.updateLayout();
                    });
                } catch (e) {
                    /* layout refresh is cosmetic */
                }
            });
        }
    });
})();
