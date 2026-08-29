pragma Singleton

import QtQuick
import QtCore
import Quickshell.Io

// The design system's colour and type layer. Everything here is *derived* from
// the generated scheme; nothing is hand-tuned per surface. Adding a constant
// that only one widget uses belongs in Metrics or, more likely, nowhere.
QtObject {
    id: root

    readonly property string sourcePath: {
        const configHome = StandardPaths.writableLocation(StandardPaths.ConfigLocation);
        if (configHome !== "")
            return configHome + "/quickshell/GeneratedTheme.json";
        return StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/.config/quickshell/GeneratedTheme.json";
    }

    readonly property FileView _file: FileView {
        path: root.sourcePath
        watchChanges: true
        blockLoading: true
        onFileChanged: reload()
        onLoaded: root._parse()
    }

    property var _scheme: ({})
    property var _typeface: ({})

    function _parse() {
        try {
            const parsed = JSON.parse(_file.text());
            _scheme = parsed.colors || {};
            _typeface = parsed.fonts || {};
        } catch (e) {
            // Keep the last good scheme; a half-written file must not blank the shell.
        }
    }

    Component.onCompleted: _parse()

    // ── Colour arithmetic ──────────────────────────────────────────────────

    function _channel(value) {
        return value <= 0.03928 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
    }

    function luminance(c) {
        return 0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);
    }

    function contrast(a, b) {
        const la = luminance(a);
        const lb = luminance(b);
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
    }

    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t);
    }

    function withAlpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    function _read(key, fallback) {
        const raw = _scheme[key];
        return raw ? Qt.color(raw) : Qt.color(fallback);
    }

    // ── Scheme inputs ──────────────────────────────────────────────────────

    readonly property color _bg: _read("bg", "#282828")
    readonly property color _bgDeep: _read("bg0_h", "#1d2021")
    readonly property color _fg: _read("fg", "#ebdbb2")

    // Polarity is measured, never declared. A scheme file that says "dark" while
    // shipping a paper background would otherwise invert every derived role.
    readonly property bool dark: luminance(_bg) < 0.28

    // ── Grounds ────────────────────────────────────────────────────────────

    readonly property color base: _bg
    readonly property color baseDeep: _bgDeep
    readonly property color raised: _read("bg1", "#3c3836")
    readonly property color raisedHigh: _read("bg2", "#504945")

    // ── Interaction fills ──────────────────────────────────────────────────
    // Alpha over whatever they sit on, so one ladder works on glass, on solid
    // cards, and in both polarities. This replaces per-widget bg1/bg2/bg3 picks.

    readonly property color fillHover: withAlpha(_fg, dark ? 0.07 : 0.06)
    readonly property color fillPress: withAlpha(_fg, dark ? 0.12 : 0.10)
    readonly property color fillActive: withAlpha(_fg, dark ? 0.16 : 0.11)
    readonly property color fillTrack: withAlpha(_fg, dark ? 0.14 : 0.13)
    readonly property color separator: withAlpha(_fg, dark ? 0.11 : 0.14)

    // ── Content ────────────────────────────────────────────────────────────
    // The scheme's own colours, unmodified. The dimmed ramp is derived by the
    // theming pipeline, which already guarantees its ordering and a contrast
    // floor ([[theming]]); re-deriving it here would be a second opinion about
    // colours the scheme has already decided.

    readonly property color text: _fg
    readonly property color textSecondary: _read("fg2", "#d5c4a1")
    readonly property color textTertiary: _read("fg3", "#bdae93")
    readonly property color textQuaternary: _read("fg4", "#a89984")

    // ── Accent and status ──────────────────────────────────────────────────

    readonly property color accent: _read("accent", "#458588")
    readonly property color accentSoft: withAlpha(accent, dark ? 0.22 : 0.18)
    // Accent over the opaque card it sits on. Cards are never translucent, so
    // this composites to a flat colour rather than to mud.
    readonly property color accentSurface: mix(raised, accent, dark ? 0.28 : 0.20)
    readonly property color onAccent: luminance(accent) > 0.45 ? Qt.rgba(0, 0, 0, 0.92) : Qt.rgba(1, 1, 1, 0.96)

    readonly property color positive: _read("greenBright", "#b8bb26")
    readonly property color caution: _read("yellowBright", "#fabd2f")
    readonly property color critical: _read("redBright", "#fb4934")

    // ── Materials ──────────────────────────────────────────────────────────
    // Panels are opaque, like the compositor's own windows; only the bar keeps
    // a hair of translucency. Hyprland blurs anything above `ignore_alpha` in
    // config/hypr/rules.lua — keep the bar and the scrim above it.

    readonly property color glassBar: withAlpha(_bg, 0.97)

    // One hairline that reads as light catching the top edge, and a shadow wide
    // enough to be felt rather than seen. A bright inner stroke around the whole
    // perimeter plus a hard dark outer stroke is the Aero look: it draws the
    // panel's outline instead of its depth.
    readonly property color specularFade: Qt.rgba(1, 1, 1, dark ? 0.06 : 0.14)
    readonly property color rim: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.10)
    readonly property color shadow: Qt.rgba(0, 0, 0, dark ? 0.34 : 0.16)
    // Above `ignore_alpha`, so the compositor blurs the desktop it dims. Below
    // it the scrim is skipped by the blur pass entirely and the modal backdrop
    // becomes a flat tint over a sharp desktop.
    readonly property color scrim: Qt.rgba(0, 0, 0, dark ? 0.42 : 0.30)

    // ── Type ───────────────────────────────────────────────────────────────

    readonly property string family: _typeface.systemFamily || "Geist"
    readonly property string familyMono: _typeface.family || "JetBrainsMono Nerd Font"

    readonly property int _base: _typeface.size || 13

    readonly property int sizeDisplay: _base + 11
    readonly property int sizeTitle: _base + 4
    readonly property int sizeHeadline: _base + 1
    readonly property int sizeBody: _base
    readonly property int sizeCallout: _base - 1
    readonly property int sizeCaption: _base - 2
    readonly property int sizeMicro: _base - 3

    readonly property int weightRegular: Font.Normal
    readonly property int weightMedium: Font.Medium
    readonly property int weightSemi: Font.DemiBold

    // Numerals that change in place — clocks, percentages, bitrates — must not
    // reflow their neighbours as digits swap.
    readonly property var tabular: ({ "tnum": 1 })
}
