pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property string brightnessDevice: ""
    property string brightnessKind: ""
    property string brightnessLabel: ""
    property int brightnessRaw: 0
    property int brightnessMax: 0
    property real pendingBrightnessFraction: -1

    readonly property bool hasBacklight: brightnessDevice !== ""
    readonly property bool brightnessAvailable: hasBacklight && brightnessMax > 0
    readonly property real brightnessRawFraction: brightnessAvailable ? Math.max(0, Math.min(1, brightnessRaw / brightnessMax)) : 0
    readonly property real brightnessFraction: brightnessAvailable ? Math.max(0, Math.min(1, brightnessStatusFraction)) : 0
    readonly property int brightnessPercent: Math.round(brightnessFraction * 100)
    readonly property bool brightnessBusy: brightnessSetProc.running || statusProc.running
    readonly property string backlightDevice: brightnessDevice
    readonly property string backlightLabel: brightnessLabel !== "" ? brightnessLabel : brightnessDevice.replace(/_/g, " ")
    property real brightnessStatusFraction: 0

    function clamp01(value) {
        return Math.max(0, Math.min(1, value));
    }

    function refresh() {
        if (!statusProc.running)
            statusProc.running = true;
    }

    function syncFromStatus(payload) {
        if (!payload || !payload.available) {
            clearState();
            return;
        }

        brightnessDevice = payload.device || "";
        brightnessKind = payload.kind || "";
        brightnessLabel = payload.label || brightnessDevice.replace(/_/g, " ");
        brightnessRaw = Math.max(0, parseInt(payload.raw || 0, 10));
        brightnessMax = Math.max(0, parseInt(payload.max || 0, 10));
        brightnessStatusFraction = clamp01(Number(payload.fraction || 0));
    }

    function clearState() {
        brightnessDevice = "";
        brightnessKind = "";
        brightnessLabel = "";
        brightnessRaw = 0;
        brightnessMax = 0;
        brightnessStatusFraction = 0;
        pendingBrightnessFraction = -1;
    }

    function setBrightnessFraction(value) {
        if (!brightnessAvailable)
            return;

        let clamped = clamp01(value);
        pendingBrightnessFraction = clamped;
        brightnessStatusFraction = clamped;
        brightnessRaw = Math.round(clamped * brightnessMax);
        if (!brightnessSetProc.running)
            applyPendingBrightness();
    }

    function applyPendingBrightness() {
        if (!brightnessAvailable || pendingBrightnessFraction < 0)
            return;

        let clamped = pendingBrightnessFraction;
        pendingBrightnessFraction = -1;
        let percent = Math.round(clamped * 100);
        brightnessSetProc.command = ["desktopctl", "brightness", "set", percent.toString()];
        brightnessSetProc.running = true;
    }

    Component.onCompleted: refresh()

    property Timer statusTimer: Timer {
        interval: root.hasBacklight ? 5000 : 30000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    property Process statusProc: Process {
        command: ["desktopctl", "brightness", "status", "--json"]
        running: false
        property string output: ""
        onRunningChanged: if (running) output = ""
        stdout: SplitParser {
            onRead: (line) => {
                if (line.trim() !== "")
                    statusProc.output += line.trim();
            }
        }
        onExited: (code) => {
            if (code !== 0) {
                root.clearState();
                return;
            }

            try {
                root.syncFromStatus(JSON.parse(statusProc.output));
            } catch (error) {
                root.clearState();
            }
        }
    }

    property Process brightnessSetProc: Process {
        running: false
        onExited: (code) => {
            if (code !== 0) {
                root.pendingBrightnessFraction = -1;
                root.refresh();
                return;
            }

            if (root.pendingBrightnessFraction >= 0)
                root.applyPendingBrightness();
            else
                root.refresh();
        }
    }
}
