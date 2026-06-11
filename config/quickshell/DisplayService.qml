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
        if (nightLightStatusProc.running || nightLightCommandProc.running)
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
    }

    function setNightLightTemperatureFromFraction(value) {
        let clamped = Math.max(0, Math.min(1, value));
        let temp = nightLightMinTemperature + clamped * (nightLightMaxTemperature - nightLightMinTemperature);
        applyNightLightTemperature(temp);
    }

    function commitNightLightTemperature() {
        return requestNightLightTemperature(nightLightTargetTemperature);
    }

    function toggleNightLight(enabled) {
        if (nightLightCommandProc.running)
            return;

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
            return false;

        monitorApplyStatus = "applying";
        monitorApplyStatusTimer.stop();
        monitorApplyProc.command = ["hyprctl", "keyword", "monitor", monitorSpec(name, width, height, rate, "auto", 0, scale, 0, null)];
        monitorApplyProc.running = true;
        return true;
    }

    function monitorSpec(name, width, height, rate, x, y, scale, transform, extras) {
        if (x === "auto")
            return name + "," + width + "x" + height + "@" + rate.toFixed(2) + ",auto," + scale;

        let cmd = name + "," + width + "x" + height + "@" + rate.toFixed(2)
                + "," + x + "x" + y + "," + scale;
        if (transform !== undefined && transform !== null && transform !== 0)
            cmd += ",transform," + transform;
        if (extras) {
            let keys = Object.keys(extras);
            for (let i = 0; i < keys.length; i++) {
                let k = keys[i];
                let v = extras[k];
                if (v !== undefined && v !== null && v !== "")
                    cmd += "," + k + "," + v;
            }
        }
        return cmd;
    }

    // Full monitor config: position, transform, and inline extras (vrr, bitdepth, mirror).
    // extras is an object, e.g. { vrr: 1, bitdepth: 10, mirror: "DP-1" }
    function applyMonitorConfig(name, width, height, rate, x, y, scale, transform, extras) {
        if (monitorApplyProc.running)
            return false;

        monitorApplyStatus = "applying";
        monitorApplyStatusTimer.stop();
        monitorApplyProc.command = ["hyprctl", "keyword", "monitor", monitorSpec(name, width, height, rate, x, y, scale, transform, extras)];
        monitorApplyProc.running = true;
        return true;
    }

    function applyMonitorBatch(states) {
        if (monitorApplyProc.running || !states || states.length === 0)
            return false;

        let commands = [];
        for (let i = 0; i < states.length; i++) {
            let state = states[i];
            let extras = {};
            if (state.vrr !== undefined && state.vrr !== false && state.vrr !== 0)
                extras.vrr = typeof state.vrr === "boolean" ? (state.vrr ? 1 : 0) : state.vrr;
            if (state.mirrorOf && state.mirrorOf !== "none")
                extras.mirror = state.mirrorOf;
            commands.push("keyword monitor " + monitorSpec(state.name, state.width, state.height, state.refreshRate, state.x, state.y, state.scale, state.transform, extras));
        }

        monitorApplyStatus = "applying";
        monitorApplyStatusTimer.stop();
        monitorApplyProc.command = ["hyprctl", "--batch", commands.join(" ; ")];
        monitorApplyProc.running = true;
        return true;
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

    // Remaining 2s fast polls after a night-light command; 0 = baseline cadence.
    property int _nightLightBurstTicks: 0

    property Timer nightLightPollTimer: Timer {
        // 5s baseline keeps external changes (e.g. the $mainMod+F8/F9
        // hotkeys, which call desktopctl directly) reasonably fresh; the
        // short 2s burst after a command preserves prompt confirmation and
        // hyprsunset-restart false-negative self-healing.
        interval: display._nightLightBurstTicks > 0 ? 2000 : 5000
        running: true
        repeat: true
        onTriggered: {
            if (display._nightLightBurstTicks > 0)
                display._nightLightBurstTicks--;
            display.refreshNightLight();
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
                display.refreshNightLight();
            } else {
                display.clearPendingNightLightAction();
                // Hyprsunset restarts can report a brief false negative, so let
                // a short burst of 2s polls confirm the settled state instead
                // of forcing an immediate status read here.
                display._nightLightBurstTicks = 3;
                display.nightLightPollTimer.restart();
            }
        }
    }
}
