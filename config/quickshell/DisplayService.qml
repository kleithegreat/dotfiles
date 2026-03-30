pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: display

    property string backlightDevice: ""
    property int brightnessRaw: 0
    property int brightnessMax: 0
    property real pendingBrightnessFraction: -1
    readonly property int nightLightMinTemperature: 3000
    readonly property int nightLightMaxTemperature: 6500
    readonly property int nightLightDefaultTemperature: 4500

    property bool nightLightEnabled: false
    property string nightLightArgs: ""
    property int nightLightTemperature: 0
    property int nightLightTargetTemperature: nightLightDefaultTemperature
    property string pendingNightLightAction: ""
    property bool nightLightRestartPending: false

    readonly property bool hasBacklight: backlightDevice !== ""
    readonly property bool brightnessAvailable: hasBacklight && brightnessMax > 0
    readonly property real brightnessRawFraction: brightnessAvailable ? Math.max(0, Math.min(1, brightnessRaw / brightnessMax)) : 0
    readonly property real brightnessFraction: brightnessAvailable ? Math.pow(brightnessRawFraction, 1.0 / 2.2) : 0
    readonly property int brightnessPercent: Math.round(brightnessFraction * 100)
    readonly property bool brightnessBusy: brightnessSetProc.running
    readonly property string backlightLabel: backlightDevice.replace(/_/g, " ")
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

    function clamp01(value) {
        return Math.max(0, Math.min(1, value));
    }

    function refresh() {
        refreshBacklightDevice();
        refreshBrightness();
        refreshNightLight();
    }

    function refreshBacklightDevice() {
        if (!detectBacklightProc.running)
            detectBacklightProc.running = true;
    }

    function refreshBrightness() {
        if (!hasBacklight)
            return;

        maxBrightnessFile.reload();
        brightnessFile.reload();
    }

    function refreshNightLight() {
        if (!nightLightStatusProc.running)
            nightLightStatusProc.running = true;
    }

    function syncBrightnessFromFiles() {
        let maxValue = parseInt(maxBrightnessFile.text().trim(), 10);
        let rawValue = parseInt(brightnessFile.text().trim(), 10);

        if (isNaN(maxValue) || maxValue <= 0 || isNaN(rawValue))
            return;

        brightnessMax = maxValue;
        brightnessRaw = Math.max(0, Math.min(maxValue, rawValue));
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
        let clamped = clamp01(value);
        let temp = nightLightMinTemperature + clamped * (nightLightMaxTemperature - nightLightMinTemperature);
        applyNightLightTemperature(temp);
    }

    function setBrightnessFraction(value) {
        if (!brightnessAvailable)
            return;

        let clamped = clamp01(value);
        pendingBrightnessFraction = clamped;
        if (!brightnessSetProc.running)
            applyPendingBrightness();
    }

    function applyPendingBrightness() {
        if (!brightnessAvailable || pendingBrightnessFraction < 0)
            return;

        let clamped = pendingBrightnessFraction;
        pendingBrightnessFraction = -1;
        let rawTarget = Math.round(Math.pow(clamped, 2.2) * brightnessMax);
        rawTarget = Math.max(1, Math.min(brightnessMax, rawTarget));

        if (rawTarget === brightnessRaw)
            return;

        brightnessRaw = rawTarget;
        brightnessSetProc.command = ["brightnessctl", "-d", backlightDevice, "s", rawTarget.toString()];
        brightnessSetProc.running = true;
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

    onBacklightDeviceChanged: {
        if (!hasBacklight) {
            brightnessRaw = 0;
            brightnessMax = 0;
            pendingBrightnessFraction = -1;
            return;
        }

        refreshBrightness();
    }

    Component.onCompleted: refresh()

    property Timer backlightRetryTimer: Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            if (!display.hasBacklight)
                display.refreshBacklightDevice();
        }
    }

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

    property FileView brightnessFile: FileView {
        path: display.hasBacklight ? "/sys/class/backlight/" + display.backlightDevice + "/brightness" : "/dev/null"
        watchChanges: display.hasBacklight
        blockLoading: true
        onFileChanged: reload()
        onLoaded: display.syncBrightnessFromFiles()
    }

    property FileView maxBrightnessFile: FileView {
        path: display.hasBacklight ? "/sys/class/backlight/" + display.backlightDevice + "/max_brightness" : "/dev/null"
        watchChanges: display.hasBacklight
        blockLoading: true
        onFileChanged: reload()
        onLoaded: display.syncBrightnessFromFiles()
    }

    property Process detectBacklightProc: Process {
        command: [
            "sh",
            "-lc",
            "for dev in /sys/class/backlight/*; do [ -d \"$dev\" ] || continue; basename \"$dev\"; exit 0; done; exit 1"
        ]
        running: false
        property string detectedDevice: ""
        onRunningChanged: if (running) detectedDevice = ""
        stdout: SplitParser {
            onRead: (line) => {
                let device = line.trim();
                if (device !== "")
                    detectBacklightProc.detectedDevice = device;
            }
        }
        onExited: (code) => {
            if (code === 0 && detectBacklightProc.detectedDevice !== "")
                display.backlightDevice = detectBacklightProc.detectedDevice;
            else
                display.backlightDevice = "";
        }
    }

    property Process brightnessSetProc: Process {
        running: false
        onExited: (code) => {
            if (code !== 0) {
                display.pendingBrightnessFraction = -1;
                display.refreshBrightness();
                return;
            }

            if (display.pendingBrightnessFraction >= 0)
                display.applyPendingBrightness();
            else
                display.refreshBrightness();
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
