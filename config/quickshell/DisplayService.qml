pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: display

    readonly property int nightLightMinTemperature: 3000
    readonly property int nightLightMaxTemperature: 6500
    readonly property int nightLightDefaultTemperature: 4500

    property bool nightLightEnabled: false
    property string nightLightArgs: ""
    property int nightLightTemperature: 0
    property int nightLightTargetTemperature: nightLightDefaultTemperature
    property string pendingNightLightAction: ""
    property bool nightLightRestartPending: false

    readonly property bool nightLightBusy: pendingNightLightAction !== "" || nightLightToggleProc.running
    readonly property real nightLightTemperatureFraction: (nightLightTargetTemperature - nightLightMinTemperature) / (nightLightMaxTemperature - nightLightMinTemperature)
    readonly property string nightLightTemperatureLabel: nightLightTargetTemperature + "K"
    readonly property string nightLightSubtitle: {
        if (pendingNightLightAction === "enable")
            return "Starting…";
        if (pendingNightLightAction === "disable")
            return "Stopping…";
        if (!nightLightEnabled)
            return "Off";
        if (nightLightTemperature > 0)
            return nightLightTemperature + "K";
        return "Auto";
    }

    function refresh() {
        refreshNightLight();
        refreshMonitors();
    }

    function refreshNightLight() {
        if (!nightLightStatusProc.running)
            nightLightStatusProc.running = true;
    }

    function updateNightLightState(args) {
        let normalizedArgs = (args || "").trim();
        nightLightEnabled = normalizedArgs !== "";
        nightLightArgs = normalizedArgs;
        nightLightTemperature = 0;

        if (nightLightEnabled) {
            let match = normalizedArgs.match(/(?:^|\s)(?:-t|--temperature)\s+(\d+)/);
            if (match) {
                nightLightTemperature = parseInt(match[1], 10) || 0;
                if (nightLightTemperature > 0)
                    nightLightTargetTemperature = clampNightLightTemperature(nightLightTemperature);
            }
        }

        if ((pendingNightLightAction === "enable" && nightLightEnabled)
                || (pendingNightLightAction === "disable" && !nightLightEnabled)) {
            clearPendingNightLightAction();
        }
    }

    function clearPendingNightLightAction() {
        pendingNightLightAction = "";
        nightLightPendingTimer.stop();
    }

    function clampNightLightTemperature(value) {
        let rounded = Math.round(value / 100) * 100;
        return Math.max(nightLightMinTemperature, Math.min(nightLightMaxTemperature, rounded));
    }

    function queueNightLightApply() {
        if (!nightLightEnabled)
            return;

        pendingNightLightAction = "enable";
        nightLightPendingTimer.interval = 12000;
        nightLightPendingTimer.restart();
        nightLightApplyTimer.restart();
    }

    function startNightLightProcess() {
        nightLightRunProc.command = [
            "hyprsunset",
            "-t",
            nightLightTargetTemperature.toString()
        ];
        nightLightRunProc.running = true;
        nightLightRefreshTimer.restart();
    }

    function applyNightLightTemperature(value) {
        let clamped = clampNightLightTemperature(value);
        if (clamped === nightLightTargetTemperature)
            return;

        nightLightTargetTemperature = clamped;
        queueNightLightApply();
    }

    function setNightLightTemperatureFromFraction(value) {
        let clamped = Math.max(0, Math.min(1, value));
        let temp = nightLightMinTemperature + clamped * (nightLightMaxTemperature - nightLightMinTemperature);
        applyNightLightTemperature(temp);
    }

    function toggleNightLight(enabled) {
        if (nightLightToggleProc.running)
            return;

        if (enabled === nightLightEnabled && pendingNightLightAction === "")
            return;

        pendingNightLightAction = enabled ? "enable" : "disable";
        nightLightPendingTimer.interval = enabled ? 12000 : 3000;
        nightLightPendingTimer.restart();

        if (enabled) {
            if (nightLightRunProc.running)
                return;

            startNightLightProcess();
            return;
        }

        nightLightRestartPending = false;
        nightLightApplyTimer.stop();
        if (nightLightRunProc.running)
            nightLightRunProc.running = false;

        nightLightToggleProc.command = ["pkill", "-x", "hyprsunset"];
        nightLightToggleProc.running = true;
        nightLightRefreshTimer.restart();
    }

    // Monitor configuration
    property var monitors: []
    property string _monitorsBuf: ""
    property string monitorApplyStatus: ""
    readonly property bool monitorApplyBusy: monitorApplyProc.running

    function refreshMonitors() {
        if (!monitorsFetchProc.running)
            monitorsFetchProc.running = true;
    }

    function applyMonitorMode(name, width, height, rate, scale) {
        if (monitorApplyProc.running)
            return;

        monitorApplyStatus = "applying";
        monitorApplyStatusTimer.stop();
        monitorApplyProc.command = [
            "hyprctl", "keyword", "monitor",
            name + "," + width + "x" + height + "@" + rate.toFixed(2) + ",auto," + scale
        ];
        monitorApplyProc.running = true;
    }

    property Process monitorsFetchProc: Process {
        command: ["hyprctl", "monitors", "-j"]
        running: false
        onRunningChanged: if (running) display._monitorsBuf = ""
        stdout: SplitParser {
            onRead: (line) => { display._monitorsBuf += line + "\n"; }
        }
        onExited: (code) => {
            if (code === 0 && display._monitorsBuf.trim() !== "") {
                try {
                    display.monitors = JSON.parse(display._monitorsBuf);
                } catch (e) {
                    console.log("[DisplayService] monitors parse error:", e);
                }
            }
        }
    }

    property Process monitorApplyProc: Process {
        running: false
        onExited: (code) => {
            display.monitorApplyStatus = code === 0 ? "applied" : "error";
            display.monitorApplyStatusTimer.restart();
            display.refreshMonitors();
        }
    }

    property Timer monitorApplyStatusTimer: Timer {
        interval: 2000
        onTriggered: display.monitorApplyStatus = ""
    }

    Component.onCompleted: refresh()

    property Timer nightLightPollTimer: Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: display.refreshNightLight()
    }

    property Timer nightLightRefreshTimer: Timer {
        interval: 300
        onTriggered: display.refreshNightLight()
    }

    property Timer nightLightPendingTimer: Timer {
        interval: 12000
        onTriggered: {
            display.clearPendingNightLightAction();
            display.refreshNightLight();
        }
    }

    property Timer nightLightApplyTimer: Timer {
        interval: 120
        onTriggered: {
            if (!display.nightLightEnabled)
                return;

            if (display.nightLightRunProc.running) {
                display.nightLightRestartPending = true;
                display.nightLightRunProc.running = false;
            } else {
                display.startNightLightProcess();
            }
        }
    }

    property Process nightLightStatusProc: Process {
        command: [
            "sh",
            "-lc",
            "if pgrep -x hyprsunset >/dev/null 2>&1; then " +
            "args=$(ps -C hyprsunset -o args= 2>/dev/null | head -n 1); " +
            "printf 'ON|%s\\n' \"$args\"; " +
            "else printf 'OFF\\n'; fi"
        ]
        running: false
        stdout: SplitParser {
            onRead: (line) => {
                if (line.startsWith("ON|"))
                    display.updateNightLightState(line.substring(3) || "hyprsunset");
                else
                    display.updateNightLightState("");
            }
        }
        onExited: (code) => {
            if (code !== 0)
                display.updateNightLightState("");
        }
    }

    property Process nightLightToggleProc: Process {
        running: false
        onExited: (code) => {
            if (code !== 0)
                display.clearPendingNightLightAction();
            display.nightLightRefreshTimer.restart();
        }
    }

    property Process nightLightRunProc: Process {
        running: false
        stdout: SplitParser {
            onRead: (line) => { console.log("[hyprsunset stdout]", line); }
        }
        stderr: SplitParser {
            onRead: (line) => { console.log("[hyprsunset stderr]", line); }
        }
        onExited: (code, status) => {
            console.log("[hyprsunset exited]", code, status);
            if (display.nightLightRestartPending) {
                display.nightLightRestartPending = false;
                display.startNightLightProcess();
                return;
            }

            display.clearPendingNightLightAction();
            display.nightLightRefreshTimer.restart();
            if (code !== 0)
                display.updateNightLightState("");
        }
    }
}
