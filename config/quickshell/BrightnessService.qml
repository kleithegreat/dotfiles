pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property var brightnessDevices: []
    property var _pendingBrightnessFractions: ({})
    property string _activeSetDevice: ""

    function clamp01(value) {
        return Math.max(0, Math.min(1, value));
    }

    function refresh() {
        if (!statusProc.running)
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

        let pending = pendingFractionForDevice(deviceId);
        let fraction = pending >= 0 ? pending : clamp01(Number(payload.fraction || 0));
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
        _activeSetDevice = "";
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

    function pendingFractionForDevice(deviceId) {
        let pending = _pendingBrightnessFractions[deviceId];
        return pending === undefined ? -1 : pending;
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
        setPendingFraction(deviceId, clamped);
        updateDeviceFraction(deviceId, clamped);
        if (!brightnessSetProc.running)
            applyPendingBrightness();
    }

    function applyPendingBrightness() {
        let pending = takeNextPendingDevice();
        if (!pending)
            return;

        _activeSetDevice = pending.device;
        let percent = Math.round(clamp01(pending.fraction) * 100);
        brightnessSetProc.command = ["desktopctl", "brightness", "set", percent.toString(), "--device", pending.device];
        brightnessSetProc.running = true;
    }

    Component.onCompleted: refresh()

    property Timer statusTimer: Timer {
        // Cheap safety net only: each status call probes the DDC/I2C bus
        // (~0.7s). Event-driven refreshes (monitor hotplug, set completions,
        // brightness OSD IPC) already cover everything but external changes
        // such as monitor OSD buttons.
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
            root._activeSetDevice = "";
            if (code !== 0) {
                root.refresh();
                return;
            }

            if (Object.keys(root._pendingBrightnessFractions).length > 0)
                root.applyPendingBrightness();
            else
                root.refresh();
        }
    }
}
