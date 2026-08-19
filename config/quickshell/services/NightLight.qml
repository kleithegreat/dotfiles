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

    property string pending: ""
    readonly property bool busy: pending !== "" || command.running

    readonly property real fraction: (target - minTemperature) / (maxTemperature - minTemperature)

    property var _rollback: ({})

    function clamp(value) {
        return Math.max(minTemperature, Math.min(maxTemperature, Math.round(value / 100) * 100));
    }

    function setFraction(value) {
        target = clamp(minTemperature + Math.max(0, Math.min(1, value)) * (maxTemperature - minTemperature));
    }

    function refresh() {
        if (status.running || command.running)
            return;
        status.running = true;
    }

    function setMode(next, temperatureK) {
        if (command.running)
            return false;

        _rollback = { mode: mode, running: running, temperature: temperature, target: target };
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

        command.command = next === "on" && temperatureK !== undefined ? ["desktopctl", "night-light", next, "--temp", String(target)] : ["desktopctl", "night-light", next];
        command.running = true;
        return true;
    }

    function toggle(enabled) {
        setMode(enabled ? "on" : "off", enabled ? target : undefined);
    }

    // Commit a temperature the user has finished dragging, without changing mode.
    function commitTemperature() {
        if (command.running)
            return false;

        _rollback = { mode: mode, running: running, temperature: temperature, target: target };
        command.command = ["desktopctl", "night-light", mode || "auto", "--temp", String(target)];
        command.running = true;
        return true;
    }

    function _ingest(state) {
        mode = state.mode || "auto";
        running = !!state.running;
        temperature = state.temperature || 0;
        target = clamp(state.target_temperature || defaultTemperature);

        const settled = (pending === "on" && mode === "on") || (pending === "auto" && mode === "auto") || (pending === "off" && !running);
        if (settled)
            pending = "";
    }

    Component.onCompleted: refresh()

    property int _burst: 0

    readonly property Timer _poll: Timer {
        // 5s keeps changes made by the hotkeys (which call desktopctl directly)
        // reasonably fresh; the 2s burst after a command exists because
        // hyprsunset reports a brief false negative while restarting.
        interval: root._burst > 0 ? 2000 : 5000
        running: true
        repeat: true
        onTriggered: {
            if (root._burst > 0)
                root._burst--;
            root.refresh();
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
                    // Keep the last known state.
                }
            }
        }
    }

    readonly property Process _command: Process {
        id: command
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() !== "")
                    Toast.error(this.text.trim().split("\n")[0]);
            }
        }
        onExited: code => {
            if (code !== 0) {
                root.mode = root._rollback.mode || "auto";
                root.running = root._rollback.running === true;
                root.temperature = root._rollback.temperature || 0;
                root.target = root.clamp(root._rollback.target || root.defaultTemperature);
                root.pending = "";
                root.refresh();
                return;
            }

            root.pending = "";
            root._burst = 3;
            root._poll.restart();
        }
    }
}
