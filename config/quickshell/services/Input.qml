pragma Singleton

import QtQuick
import Quickshell.Io

// Managed Hyprland input settings. QML never edits the config: every change is
// a `desktopctl hypr input set`, staged optimistically and rolled back if the
// backend refuses it.
QtObject {
    id: root

    property real sensitivity: 0
    property string accelProfile: "flat"
    property real scrollFactor: 1

    property var staged: ({})
    readonly property bool busy: writer.running || _queue.length > 0

    property var _queue: []

    function value(key, fallback) {
        if (staged[key] !== undefined)
            return staged[key];
        if (key === "sensitivity")
            return sensitivity;
        if (key === "accel_profile")
            return accelProfile;
        if (key === "scroll_factor")
            return scrollFactor;
        return fallback;
    }

    function set(key, next) {
        const pending = Object.assign({}, staged);
        pending[key] = next;
        staged = pending;

        _queue = _queue.concat([{ key: key, value: String(next) }]);
        _pump();
    }

    function refresh() {
        if (!status.running)
            status.running = true;
    }

    function _pump() {
        if (writer.running || _queue.length === 0)
            return;
        writer.command = ["desktopctl", "hypr", "input", "set", _queue[0].key, _queue[0].value];
        writer.running = true;
    }

    function _ingest(data) {
        sensitivity = data.sensitivity;
        accelProfile = data.accel_profile;
        scrollFactor = data.scroll_factor;
        // Only drop staged values the backend now agrees with; a wholesale
        // clear would discard optimism for writes still in the queue.
        const remaining = {};
        for (const key in staged) {
            if (data[key] !== staged[key])
                remaining[key] = staged[key];
        }
        staged = remaining;
    }

    Component.onCompleted: refresh()

    // State is pushed over the Desktopctl socket (snapshot on subscribe,
    // hypr_input.changed per write); the startup refresh is the degraded
    // path for a daemon that is not up yet.
    readonly property Connections _events: Connections {
        target: Desktopctl
        function onInputChanged(state) {
            root._ingest(state);
        }
    }

    readonly property Process _status: Process {
        id: status
        command: ["desktopctl", "hypr", "input", "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root._ingest(JSON.parse(this.text));
                } catch (e) {
                    // Keep the last known values.
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
            const job = root._queue[0];
            root._queue = root._queue.slice(1);

            if (code !== 0) {
                const reverted = Object.assign({}, root.staged);
                delete reverted[job.key];
                root.staged = reverted;
                Toast.error(failure.text.trim().split("\n").filter(line => line !== "").pop() || "Input change failed");
            }

            // No refresh: the daemon's hypr_input.changed event carries the
            // committed state for every successful write.
            Qt.callLater(root._pump);
        }
    }
}
