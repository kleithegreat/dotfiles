pragma Singleton

import QtQuick
import Quickshell.Io

QtObject {
    id: root

    readonly property int minTemperature: 3000
    readonly property int maxTemperature: 6500
    readonly property int defaultTemperature: 4500

    // auto · on · off
    property string mode: "auto"
    property bool running: false
    property int temperature: 0
    property int target: defaultTemperature
    property int _serverTarget: defaultTemperature

    property string pending: ""
    readonly property bool busy: pending !== "" || writes.busy

    readonly property real fraction: (target - minTemperature) / (maxTemperature - minTemperature)

    property var _rollback: ({})

    function clamp(value) {
        return Math.max(minTemperature, Math.min(maxTemperature, Math.round(value / 100) * 100));
    }

    function setFraction(value) {
        target = clamp(minTemperature + Math.max(0, Math.min(1, value)) * (maxTemperature - minTemperature));
    }

    function refresh() {
        if (status.running || writes.busy)
            return;
        status.running = true;
    }

    function setMode(next, temperatureK) {
        if (writes.busy)
            return false;

        _rollback = { mode: mode, running: running, temperature: temperature, target: _serverTarget };
        pending = next;

        if (next === "off") {
            mode = "off";
            running = false;
        } else {
            mode = next;
            if (temperatureK !== undefined) {
                target = clamp(temperatureK);
                temperature = target;
            }
            if (next === "on")
                running = true;
        }

        const argv = next === "on" && temperatureK !== undefined
            ? ["desktopctl", "night-light", next, "--temp", String(target)]
            : ["desktopctl", "night-light", next];
        writes.run(argv, "mode");
        return true;
    }

    function toggle(enabled) {
        setMode(enabled ? "on" : "off", enabled ? target : undefined);
    }

    // Commit a temperature the user has finished dragging, without changing mode.
    function commitTemperature() {
        if (writes.busy)
            return false;

        _rollback = { mode: mode, running: running, temperature: temperature, target: _serverTarget };
        writes.run(["desktopctl", "night-light", mode || "auto", "--temp", String(target)], "temp");
        return true;
    }

    function _ingest(state) {
        mode = state.mode || "auto";
        running = !!state.running;
        temperature = state.temperature || 0;
        _serverTarget = clamp(state.target_temperature || defaultTemperature);
        target = _serverTarget;

        const settled = (pending === "on" && mode === "on") || (pending === "auto" && mode === "auto") || (pending === "off" && !running);
        if (settled)
            pending = "";
    }

    Component.onCompleted: refresh()

    readonly property WriteQueue _writes: WriteQueue {
        id: writes
        failureText: "Night Light change failed"
        onSettled: (key, ok) => {
            if (!ok) {
                root.mode = root._rollback.mode || "auto";
                root.running = root._rollback.running === true;
                root.temperature = root._rollback.temperature || 0;
                root.target = root.clamp(root._rollback.target || root.defaultTemperature);
                root.pending = "";
                root.refresh();
                return;
            }
            root.pending = "";
        }
    }

    readonly property Connections _events: Connections {
        target: Desktopctl
        function onNightLightChanged(status) {
            root._ingest(status);
        }
    }

    readonly property Process _status: Process {
        id: status
        command: ["desktopctl", "night-light", "status", "--json"]
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
