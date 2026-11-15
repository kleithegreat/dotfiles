pragma Singleton

import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property real sensitivity: 0
    // The laptop top row sends media keys without Fn; absent elsewhere.
    property bool mediaKeys: false
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

    readonly property Connections _events: Connections {
        target: Desktopctl
        function onInputChanged(state) {
            root._ingest(state);
        }
        // Fn+Esc ([[desktopctl]]); the subscribe snapshot carries no `osd`, so a restart is silent.
        function onFnLockChanged(data) {
            root.mediaKeys = data.media_keys;
            if (data.osd)
                Osd.show("keyboard", null, data.media_keys ? "Media keys" : "Function keys");
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
