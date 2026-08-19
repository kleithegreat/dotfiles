pragma Singleton

import QtQuick
import Quickshell.Io

// Theme state, and the only path that changes it.
//
// QML never edits theme or Hyprland config files; every mutation is a
// `desktopctl theme` call, and they are serialised because the backend rewrites
// generated fragments per apply. The old shell ran a theme queue and a Hyprland
// queue that had to cross-gate each other to avoid interleaving — but the
// Hyprland values *are* theme-state keys, so there was only ever one queue to
// have. A value is staged optimistically and rolled back if the write fails,
// and changes propagate on real command completion, never on a timer.
QtObject {
    id: root

    property var state: ({})
    property var staged: ({})

    property var schemes: []
    property var presets: []
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
        writer.command = job.preset !== undefined ? ["desktopctl", "theme", "preset", job.preset] : ["desktopctl", "theme", "set", job.key, job.value];
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

        if (_queue.length === 0) {
            refresh();
            Qt.callLater(root.reloadCatalogs);
        }

        Qt.callLater(root._pump);
    }

    Component.onCompleted: {
        refresh();
        reloadCatalogs();
    }

    readonly property Process _status: Process {
        id: status
        command: ["desktopctl", "theme", "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.state = JSON.parse(this.text);
                    // Anything the backend now agrees with is no longer staged.
                    const remaining = {};
                    for (const key in root.staged) {
                        if (root.state[key] !== root.staged[key])
                            remaining[key] = root.staged[key];
                    }
                    root.staged = remaining;
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

    readonly property Process _wallpaperList: Process {
        id: wallpaperList
        command: ["desktopctl", "theme", "list-wallpapers"]
        stdout: StdioCollector {
            onStreamFinished: root.wallpapers = this.text.split("\n").map(line => line.trim()).filter(line => line !== "")
        }
    }
}
