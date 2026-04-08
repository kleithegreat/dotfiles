pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: display

    readonly property int nightLightMinTemperature: 3000
    readonly property int nightLightMaxTemperature: 6500
    readonly property int nightLightDefaultTemperature: 4500

    property string nightLightMode: "auto"
    property bool nightLightEnabled: false
    property int nightLightTemperature: 0
    property int nightLightTargetTemperature: nightLightDefaultTemperature
    property string pendingNightLightAction: ""
    property var _nightLightRollbackState: ({})

    readonly property bool nightLightBusy: pendingNightLightAction !== "" || nightLightCommandProc.running
    readonly property real nightLightTemperatureFraction: (nightLightTargetTemperature - nightLightMinTemperature) / (nightLightMaxTemperature - nightLightMinTemperature)
    readonly property string nightLightTemperatureLabel: nightLightTargetTemperature + "K"
    readonly property string nightLightSubtitle: {
        if (pendingNightLightAction === "on")
            return "Applying...";
        if (pendingNightLightAction === "off")
            return "Turning off...";
        if (pendingNightLightAction === "auto")
            return "Returning to schedule...";
        if (nightLightMode === "auto") {
            if (nightLightEnabled && nightLightTemperature > 0)
                return "Auto " + nightLightTemperature + "K";
            return "Auto";
        }
        if (!nightLightEnabled)
            return "Off";
        if (nightLightTemperature > 0)
            return nightLightTemperature + "K";
        return "On";
    }

    function refresh() {
        refreshNightLight();
        refreshMonitors();
    }

    function refreshNightLight() {
        if (nightLightStatusProc.running)
            return;

        nightLightStatusProc.buf = "";
        nightLightStatusProc.running = true;
    }

    function updateNightLightState(data) {
        let next = data || ({});
        nightLightMode = next.mode || "auto";
        nightLightEnabled = !!next.running;
        nightLightTemperature = next.temperature || 0;
        nightLightTargetTemperature = clampNightLightTemperature(next.target_temperature || nightLightDefaultTemperature);

        if ((pendingNightLightAction === "on" && nightLightMode === "on")
                || (pendingNightLightAction === "auto" && nightLightMode === "auto")
                || (pendingNightLightAction === "off" && !nightLightEnabled)) {
            clearPendingNightLightAction();
        }
    }

    function clearPendingNightLightAction() {
        pendingNightLightAction = "";
    }

    function snapshotNightLightState() {
        return {
            mode: nightLightMode,
            enabled: nightLightEnabled,
            temperature: nightLightTemperature,
            targetTemperature: nightLightTargetTemperature
        };
    }

    function restoreNightLightState(snapshot) {
        let state = snapshot || ({});
        nightLightMode = state.mode || "auto";
        nightLightEnabled = state.enabled === true;
        nightLightTemperature = state.temperature || 0;
        nightLightTargetTemperature = clampNightLightTemperature(state.targetTemperature || nightLightDefaultTemperature);
    }

    function clampNightLightTemperature(value) {
        let rounded = Math.round(value / 100) * 100;
        return Math.max(nightLightMinTemperature, Math.min(nightLightMaxTemperature, rounded));
    }

    function applyNightLightTemperature(value) {
        let clamped = clampNightLightTemperature(value);
        if (clamped === nightLightTargetTemperature)
            return;

        nightLightTargetTemperature = clamped;
        nightLightApplyTimer.restart();
    }

    function setNightLightTemperatureFromFraction(value) {
        let clamped = Math.max(0, Math.min(1, value));
        let temp = nightLightMinTemperature + clamped * (nightLightMaxTemperature - nightLightMinTemperature);
        applyNightLightTemperature(temp);
    }

    function toggleNightLight(enabled) {
        if (nightLightCommandProc.running)
            return;

        nightLightApplyTimer.stop();
        requestNightLightMode(enabled ? "on" : "off", enabled ? nightLightTargetTemperature : undefined);
    }

    function requestNightLightMode(mode, temperature) {
        if (nightLightCommandProc.running)
            return false;

        _nightLightRollbackState = snapshotNightLightState();
        pendingNightLightAction = mode;
        if (mode === "off") {
            nightLightMode = "off";
            nightLightEnabled = false;
        } else {
            nightLightMode = mode;
            if (temperature !== undefined && temperature !== null) {
                let clamped = clampNightLightTemperature(temperature);
                nightLightTargetTemperature = clamped;
                nightLightTemperature = clamped;
            }
            if (mode === "on")
                nightLightEnabled = true;
        }

        let command = ["desktopctl", "night-light", mode];
        if (mode === "on" && temperature !== undefined && temperature !== null)
            command = command.concat(["--temp", temperature.toString()]);

        nightLightCommandProc.command = command;
        nightLightCommandProc.running = true;
        return true;
    }

    function requestNightLightTemperature(temperature) {
        if (nightLightCommandProc.running)
            return false;

        _nightLightRollbackState = snapshotNightLightState();
        nightLightTargetTemperature = clampNightLightTemperature(temperature);
        nightLightCommandProc.command = ["desktopctl", "night-light", nightLightMode || "auto", "--temp", temperature.toString()];
        nightLightCommandProc.running = true;
        return true;
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

    property Timer nightLightApplyTimer: Timer {
        interval: 120
        onTriggered: {
            if (!display.requestNightLightTemperature(display.nightLightTargetTemperature))
                display.nightLightApplyTimer.restart();
        }
    }

    property Process nightLightStatusProc: Process {
        command: ["desktopctl", "night-light", "status", "--json"]
        running: false
        property string buf: ""
        stdout: SplitParser {
            onRead: (line) => { nightLightStatusProc.buf += line; }
        }
        stderr: SplitParser {
            onRead: (line) => { console.log("[desktopctl night-light status stderr]", line); }
        }
        onExited: (code) => {
            if (code === 0 && buf.trim() !== "") {
                try {
                    display.updateNightLightState(JSON.parse(buf));
                } catch (e) {
                    console.log("[DisplayService] night-light parse error:", e);
                }
            }
            buf = "";
        }
    }

    property Process nightLightCommandProc: Process {
        running: false
        stderr: SplitParser {
            onRead: (line) => { console.log("[desktopctl night-light stderr]", line); }
        }
        onExited: (code) => {
            if (code !== 0) {
                display.restoreNightLightState(display._nightLightRollbackState);
                display.clearPendingNightLightAction();
            } else {
                display.clearPendingNightLightAction();
            }
            display.refreshNightLight();
        }
    }
}
