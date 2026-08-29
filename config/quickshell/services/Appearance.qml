pragma Singleton

import QtQuick
import Quickshell.Io

// Theme state, and the only path that changes it ([[quickshell]]).
QtObject {
    id: root

    property var state: ({})
    property var staged: ({})

    property var schemes: []
    property var presets: []
    // { name, path, preview_path } per entry; preview_path may be null when
    // preview generation failed for that file.
    property var wallpapers: []

    readonly property bool busy: writer.running || _queue.length > 0

    property var _queue: []
    property var _rollback: ({})

    function value(key, fallback) {
        if (staged[key] !== undefined)
            return staged[key];
        if (state[key] !== undefined)
            return state[key];
        return fallback;
    }

    function set(key, next) {
        const previous = state[key];
        if (previous === next && staged[key] === undefined)
            return;

        const pending = Object.assign({}, staged);
        pending[key] = next;
        staged = pending;

        const remembered = Object.assign({}, _rollback);
        if (remembered[key] === undefined)
            remembered[key] = previous;
        _rollback = remembered;

        _queue = _queue.concat([{ key: key, value: String(next) }]);
        _pump();
    }

    function applyPreset(name) {
        _queue = _queue.concat([{ preset: name }]);
        _pump();
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

        _queue = _queue.concat([{ savePreset: name, payload: JSON.stringify(patch) }]);
        _pump();
        return true;
    }

    function deletePreset(name) {
        _queue = _queue.concat([{ deletePreset: name }]);
        _pump();
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

    function _pump() {
        if (writer.running || _queue.length === 0)
            return;

        const job = _queue[0];
        if (job.preset !== undefined)
            writer.command = ["desktopctl", "theme", "preset", job.preset];
        else if (job.savePreset !== undefined)
            writer.command = ["desktopctl", "theme", "save-preset", job.savePreset, job.payload];
        else if (job.deletePreset !== undefined)
            writer.command = ["desktopctl", "theme", "delete-preset", job.deletePreset];
        else
            writer.command = ["desktopctl", "theme", "set", job.key, job.value];
        writer.running = true;
    }

    function _settle(ok) {
        const job = _queue[0];
        _queue = _queue.slice(1);

        if (!ok && job && job.key !== undefined) {
            const reverted = Object.assign({}, staged);
            delete reverted[job.key];
            staged = reverted;
        }

        // No refresh here: the daemon's theme.changed event carries the
        // committed state for every successful write.
        Qt.callLater(root._pump);
    }

    function _ingestState(next) {
        state = next;
        // Anything the backend now agrees with is no longer staged.
        const remaining = {};
        for (const key in staged) {
            if (state[key] !== staged[key])
                remaining[key] = staged[key];
        }
        staged = remaining;
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
            const catalogKeys = ["wallpaper", "wallpaper_dir", "filter_wallpaper", "color_scheme"];
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
                    // Keep the last good state.
                }
            }
        }
    }

    readonly property Process _writer: Process {
        id: writer
        stderr: StdioCollector {
            id: failure
        }
        onExited: code => {
            if (code !== 0)
                Toast.error(failure.text.trim().split("\n").filter(line => line !== "").pop() || "Theme change failed");
            root._settle(code === 0);
        }
    }

    readonly property Process _schemeList: Process {
        id: schemeList
        command: ["desktopctl", "theme", "list-schemes"]
        stdout: StdioCollector {
            onStreamFinished: root.schemes = this.text.split("\n").map(line => line.trim()).filter(line => line !== "")
        }
    }

    readonly property Process _presetList: Process {
        id: presetList
        command: ["desktopctl", "theme", "list-presets"]
        stdout: StdioCollector {
            onStreamFinished: root.presets = this.text.split("\n").map(line => line.trim()).filter(line => line !== "")
        }
    }

    // The JSON form carries the cached 640x400 preview desktopctl already
    // renders for each wallpaper. The plain-text form only carries names, which
    // left the picker decoding the originals -- ten JPEGs averaging 24 MB each.
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
