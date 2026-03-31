pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property string backlightDevice: ""
    property int brightnessRaw: 0
    property int brightnessMax: 0
    property real pendingBrightnessFraction: -1

    readonly property bool hasBacklight: backlightDevice !== ""
    readonly property bool brightnessAvailable: hasBacklight && brightnessMax > 0
    readonly property real brightnessRawFraction: brightnessAvailable ? Math.max(0, Math.min(1, brightnessRaw / brightnessMax)) : 0
    readonly property real brightnessFraction: brightnessAvailable ? Math.pow(brightnessRawFraction, 1.0 / 2.2) : 0
    readonly property int brightnessPercent: Math.round(brightnessFraction * 100)
    readonly property bool brightnessBusy: brightnessSetProc.running
    readonly property string backlightLabel: backlightDevice.replace(/_/g, " ")

    function clamp01(value) {
        return Math.max(0, Math.min(1, value));
    }

    function refresh() {
        refreshBacklightDevice();
        refreshBrightness();
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

    function syncBrightnessFromFiles() {
        let maxValue = parseInt(maxBrightnessFile.text().trim(), 10);
        let rawValue = parseInt(brightnessFile.text().trim(), 10);

        if (isNaN(maxValue) || maxValue <= 0 || isNaN(rawValue))
            return;

        brightnessMax = maxValue;
        brightnessRaw = Math.max(0, Math.min(maxValue, rawValue));
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
            if (!root.hasBacklight)
                root.refreshBacklightDevice();
        }
    }

    property FileView brightnessFile: FileView {
        path: root.hasBacklight ? "/sys/class/backlight/" + root.backlightDevice + "/brightness" : "/dev/null"
        watchChanges: root.hasBacklight
        blockLoading: true
        onFileChanged: reload()
        onLoaded: root.syncBrightnessFromFiles()
    }

    property FileView maxBrightnessFile: FileView {
        path: root.hasBacklight ? "/sys/class/backlight/" + root.backlightDevice + "/max_brightness" : "/dev/null"
        watchChanges: root.hasBacklight
        blockLoading: true
        onFileChanged: reload()
        onLoaded: root.syncBrightnessFromFiles()
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
                root.backlightDevice = detectBacklightProc.detectedDevice;
            else
                root.backlightDevice = "";
        }
    }

    property Process brightnessSetProc: Process {
        running: false
        onExited: (code) => {
            if (code !== 0) {
                root.pendingBrightnessFraction = -1;
                root.refreshBrightness();
                return;
            }

            if (root.pendingBrightnessFraction >= 0)
                root.applyPendingBrightness();
            else
                root.refreshBrightness();
        }
    }
}
