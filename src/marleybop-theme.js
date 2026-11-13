/* Marleybop theme helper for Proxmox VE.
 * Does nothing unless the Marleybop stylesheet is the active theme (it sets --mb-theme).
 * 1. Recolours the RRD charts, whose series colours are hard-coded in pvemanagerlib.js.
 * 2. Re-runs the layout once the web fonts have loaded, so nothing is measured with the fallback font.
 */
(function () {
    // no 'use strict' here: ExtJS's callParent() finds its caller through function.caller
    if (!window.Ext || !window.getComputedStyle) {
        return;
    }
    var css = function (name) {
        return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
    };
    var active = function () {
        return css('--mb-theme').indexOf('marleybop') === 0;
    };

    // stock series colour -> slot in the Marleybop chart palette (--mb-chart-N)
    var slots = {
        '#94ae0a': 1, '#115fa6': 2, '#c4c0c0': 3, '#24ad9a': 4, '#bbde0d': 5,
        '#ffd13e': 1, '#a61120': 2, '#cfcfcf': 6, '#3892d4': 3, '#21bf4b': 4, '#ffcc00': 5, '#ff6c59': 2,
    };
    var palette = function () {
        var out = [];
        for (var i = 1; i <= 6; i++) {
            out.push(css('--mb-chart-' + i));
        }
        return out;
    };
    var remap = function (colors) {
        var pal = palette();
        return colors.map(function (c, i) {
            var slot = slots[String(c).toLowerCase()];
            return (slot && pal[slot - 1]) || pal[i % pal.length] || c;
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
                console.warn('Marleybop theme: chart colours not applied', e);
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
