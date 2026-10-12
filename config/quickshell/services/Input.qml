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
    property real touchpadScrollFactor: 0.25

    readonly property var staged: writes.staged

    function value(key, fallback) {
        if (staged[key] !== undefined)
            return staged[key];
        if (key === "sensitivity")
            return sensitivity;
        if (key === "accel_profile")
            return accelProfile;
        if (key === "scroll_factor")
            return scrollFactor;
        if (key === "touchpad_scroll_factor")
            return touchpadScrollFactor;
        return fallback;
    }

    function set(key, next) {
        writes.set(key, next, ["desktopctl", "hypr", "input", "set", key, String(next)]);
    }

    function refresh() {
        if (!status.running)
            status.running = true;
    }

    function _ingest(data) {
        sensitivity = data.sensitivity;
        accelProfile = data.accel_profile;
        scrollFactor = data.scroll_factor;
        if (data.touchpad_scroll_factor !== undefined)
            touchpadScrollFactor = data.touchpad_scroll_factor;
        writes.settle(data);
    }

    readonly property WriteQueue _writes: WriteQueue {
        id: writes
        failureText: "Input change failed"
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
                }
            }
        }
    }
}
