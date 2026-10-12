pragma Singleton

import QtQuick
import Quickshell.Io

// Theme state, and the only path that changes it ([[quickshell]]).
QtObject {
    id: root

    property var state: ({})
    readonly property var staged: writes.staged

    property var schemes: []
    property var presets: []
    // { name, path, preview_path } per entry; preview_path may be null when
    // preview generation failed for that file.
    property var wallpapers: []

    function value(key, fallback) {
        return writes.value(key, state[key] !== undefined ? state[key] : fallback);
    }

    function set(key, next) {
        if (state[key] === next && staged[key] === undefined)
            return;
        writes.set(key, next, ["desktopctl", "theme", "set", key, String(next)]);
    }

    function applyPreset(name) {
        writes.run(["desktopctl", "theme", "preset", name]);
    }

    readonly property WriteQueue _writes: WriteQueue {
        id: writes
        failureText: "Theme change failed"
    }

    // What each aspect of a preset covers. A preset is a partial patch, so
    // saving one is choosing which aspects to capture — dumping the whole state
    // would make every preset overwrite everything the next one meant to leave
    // alone.
    readonly property var aspects: [
        { id: "scheme", label: "Colour scheme", keys: ["color_scheme"] },
        { id: "wallpaper", label: "Wallpaper", keys: ["wallpaper", "filter_wallpaper"] },
        { id: "icons", label: "Icons", keys: ["icon_theme"] },
        { id: "pointer", label: "Pointer", keys: ["cursor_theme", "cursor_size"] },
        { id: "fonts", label: "Fonts", keys: ["system_font", "mono_font", "font_size", "mono_font_size"] },
        { id: "windows", label: "Window look", keys: ["hypr_gaps_in", "hypr_gaps_out", "hypr_border_size", "hypr_rounding", "hypr_blur_enabled", "hypr_blur_size", "hypr_blur_passes", "hypr_animations_enabled"] }
    ]

    function savePreset(name, aspectIds) {
        const patch = {};
        for (let i = 0; i < aspects.length; i++) {
            if (aspectIds.indexOf(aspects[i].id) < 0)
                continue;
            const keys = aspects[i].keys;
            for (let k = 0; k < keys.length; k++) {
                const current = value(keys[k], undefined);
                if (current !== undefined)
                    patch[keys[k]] = current;
            }
        }

        if (Object.keys(patch).length === 0) {
            Toast.warning("Choose at least one thing to save");
            return false;
        }

        writes.run(["desktopctl", "theme", "save-preset", name, JSON.stringify(patch)]);
        return true;
    }

    function deletePreset(name) {
        writes.run(["desktopctl", "theme", "delete-preset", name]);
    }

    function refresh() {
        if (!status.running)
            status.running = true;
    }

    function reloadCatalogs() {
        schemeList.running = true;
        presetList.running = true;
        wallpaperList.running = true;
    }

    function _ingestState(next) {
        state = next;
        writes.settle(next);
    }

    Component.onCompleted: {
        refresh();
        reloadCatalogs();
    }

    readonly property Connections _events: Connections {
        target: Desktopctl
        function onThemeChanged(state, changedKeys) {
            root._ingestState(state);
            // The scheme and wallpaper catalogs only shift when these keys
            // move (or the repo changes, which a session restart covers).
            const catalogKeys = ["wallpaper", "filter_wallpaper", "color_scheme"];
            for (let i = 0; i < changedKeys.length; i++) {
                if (catalogKeys.indexOf(changedKeys[i]) >= 0) {
                    Qt.callLater(root.reloadCatalogs);
                    break;
                }
            }
        }
        function onPresetsChanged(presets) {
            root.presets = presets;
        }
    }

    readonly property Process _status: Process {
        id: status
        command: ["desktopctl", "theme", "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root._ingestState(JSON.parse(this.text));
                } catch (e) {
                }
            }
        }
    }

    readonly property Process _schemeList: Process {
        id: schemeList
        command: ["desktopctl", "theme", "list-schemes"]
        stdout: StdioCollector {
            onStreamFinished: root.schemes = this.text.split("\n").map(line => line.trim()).filter(line => line !== "").map(path => ({ name: path.replace(/^.*\//, "").replace(/\.json$/, ""), path: path }))
        }
    }

    readonly property Process _presetList: Process {
        id: presetList
        command: ["desktopctl", "theme", "list-presets"]
        stdout: StdioCollector {
            onStreamFinished: root.presets = this.text.split("\n").map(line => line.trim()).filter(line => line !== "")
        }
    }

    // The JSON form carries the cached preview; the plain-text form only has names,
    // which would leave the picker decoding the full-size originals.
    readonly property Process _wallpaperList: Process {
        id: wallpaperList
        command: ["desktopctl", "theme", "list-wallpapers", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.wallpapers = JSON.parse(this.text);
                } catch (error) {
                    root.wallpapers = [];
                }
            }
        }
    }
}
