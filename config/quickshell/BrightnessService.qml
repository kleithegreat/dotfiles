pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property var brightnessDevices: []
    property var _pendingBrightnessFractions: ({})

    // A status read samples the hardware over ~1s. Any brightness the user sets
    // while one is in flight makes its payload describe a pre-write world, so
    // `_writeEpoch` bumps on intent (not on dispatch, which a queued write
    // defers) and a status finishing on a stale epoch is discarded rather than
    // allowed to overwrite what the user just set.
    property int _writeEpoch: 0
    property int _statusEpoch: 0

    function clamp01(value) {
        return Math.max(0, Math.min(1, value));
    }

    function refresh() {
        if (statusProc.running)
            return;

        _statusEpoch = _writeEpoch;
        statusProc.running = true;
    }

    function syncFromStatus(payload) {
        if (!payload) {
            clearState();
            return;
        }

        let payloadDevices = payload.devices || [];
        if (payloadDevices.length === 0 && payload.available)
            payloadDevices = [payload];

        let nextDevices = [];
        for (let i = 0; i < payloadDevices.length; i++) {
            let device = normalizeDevice(payloadDevices[i]);
            if (device && device.available)
                nextDevices.push(device);
        }

        brightnessDevices = nextDevices;
    }

    function normalizeDevice(payload) {
        if (!payload || !payload.available)
            return null;

        let deviceId = payload.device || "";
        let max = Math.max(0, parseInt(payload.max || 0, 10));
        if (deviceId === "" || max <= 0)
            return null;

        let fraction = clamp01(Number(payload.fraction || 0));
        return {
            available: true,
            kind: payload.kind || "",
            device: deviceId,
            label: payload.label || deviceId.replace(/_/g, " "),
            raw: Math.max(0, parseInt(payload.raw || 0, 10)),
            max: max,
            fraction: fraction,
            percent: Math.round(fraction * 100),
            connector: payload.connector || ""
        };
    }

    function clearState() {
        brightnessDevices = [];
        _pendingBrightnessFractions = ({});
    }

    function isInternalMonitorName(name) {
        return /^(eDP|LVDS|DSI)(-|$)/.test(name || "");
    }

    function internalDisplayEnabled(monitors) {
        if (!monitors || monitors.length === 0)
            return true;

        for (let i = 0; i < monitors.length; i++) {
            let monitor = monitors[i];
            if (!monitor.disabled && isInternalMonitorName(monitor.name || ""))
                return true;
        }

        return false;
    }

    function deviceVisibleForMonitors(device, monitors) {
        if (!device || !device.available)
            return false;
        if (device.kind === "backlight")
            return internalDisplayEnabled(monitors);
        return true;
    }

    function devicesForMonitors(monitors, devices) {
        let source = devices || brightnessDevices;
        let result = [];
        for (let i = 0; i < source.length; i++) {
            if (deviceVisibleForMonitors(source[i], monitors))
                result.push(source[i]);
        }
        return result;
    }

    function primaryDeviceForMonitors(monitors, devices) {
        let visible = devicesForMonitors(monitors, devices || brightnessDevices);
        return visible.length > 0 ? visible[0] : null;
    }

    function setPendingFraction(deviceId, value) {
        let next = Object.assign({}, _pendingBrightnessFractions);
        next[deviceId] = value;
        _pendingBrightnessFractions = next;
    }

    function takeNextPendingDevice() {
        let keys = Object.keys(_pendingBrightnessFractions);
        if (keys.length === 0)
            return null;

        let deviceId = keys[0];
        let fraction = _pendingBrightnessFractions[deviceId];
        let next = Object.assign({}, _pendingBrightnessFractions);
        delete next[deviceId];
        _pendingBrightnessFractions = next;
        return { device: deviceId, fraction: fraction };
    }

    function updateDeviceFraction(deviceId, value) {
        let clamped = clamp01(value);
        let next = [];
        for (let i = 0; i < brightnessDevices.length; i++) {
            let device = Object.assign({}, brightnessDevices[i]);
            if (device.device === deviceId) {
                device.fraction = clamped;
                device.percent = Math.round(clamped * 100);
                device.raw = Math.round(clamped * device.max);
            }
            next.push(device);
        }
        brightnessDevices = next;
    }

    function setBrightnessFractionForDevice(deviceId, value) {
        if (!deviceId)
            return;

        let clamped = clamp01(value);
        _writeEpoch += 1;
        setPendingFraction(deviceId, clamped);
        updateDeviceFraction(deviceId, clamped);
        if (!brightnessSetProc.running)
            applyPendingBrightness();
    }

    function applyPendingBrightness() {
        let pending = takeNextPendingDevice();
        if (!pending)
            return;

        let percent = Math.round(clamp01(pending.fraction) * 100);
        brightnessSetProc.command = ["desktopctl", "brightness", "set", percent.toString(), "--device", pending.device];
        brightnessSetProc.running = true;
    }

    Component.onCompleted: refresh()

    property Timer statusTimer: Timer {
        // Safety net only: a status call enumerates the DDC/I2C buses and takes
        // ~1.2s. Popup opens, monitor hotplug, and the brightness OSD IPC
        // already refresh on demand, so this exists purely to notice changes
        // made from the monitor's own OSD buttons.
        interval: 30000
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
            if (root._statusEpoch !== root._writeEpoch)
                return;

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
            // A successful write needs no read-back: the value we sent is the
            // truth, and the status timer still catches changes made from the
            // monitor's own OSD buttons.
            if (code !== 0) {
                root.refresh();
                return;
            }

            root.applyPendingBrightness();
        }
    }
}
