pragma Singleton

import QtQuick
import Quickshell.Io

QtObject {
    id: root

    // Devices the user should currently be offered. The internal backlight is
    // dropped when the internal panel is off — a slider for a dark display is
    // worse than no slider.
    readonly property var devices: {
        const usable = [];
        for (let i = 0; i < _all.length; i++) {
            const device = _all[i];
            if (device.kind === "backlight" && !Displays.internalPanelActive)
                continue;
            usable.push(device);
        }
        return usable;
    }

    readonly property var primary: devices.length > 0 ? devices[0] : null
    readonly property bool available: devices.length > 0

    readonly property string icon: {
        if (!primary)
            return "brightness-medium";
        const percent = primary.percent;
        if (percent >= 80)
            return "brightness-max";
        if (percent >= 45)
            return "brightness-high";
        if (percent >= 15)
            return "brightness-medium";
        return "brightness-low";
    }

    property var _all: []
    property var _queued: ({})

    // A status read samples DDC/I2C over roughly a second. Any brightness set
    // while one is in flight makes its payload describe a pre-write world, so
    // the epoch bumps on *intent* — not on dispatch, which a queued write defers
    // — and a status landing on a stale epoch is discarded rather than allowed
    // to overwrite what the user just set.
    property int _writes: 0
    property int _reading: 0

    function refresh() {
        if (status.running)
            return;
        _reading = _writes;
        status.running = true;
    }

    function set(deviceId, fraction) {
        if (!deviceId)
            return;

        const value = Math.max(0, Math.min(1, fraction));
        _writes += 1;

        const queued = Object.assign({}, _queued);
        queued[deviceId] = value;
        _queued = queued;

        const updated = [];
        for (let i = 0; i < _all.length; i++) {
            const device = Object.assign({}, _all[i]);
            if (device.device === deviceId) {
                device.fraction = value;
                device.percent = Math.round(value * 100);
                device.raw = Math.round(value * device.max);
            }
            updated.push(device);
        }
        _all = updated;

        if (!writer.running)
            _drain();
    }

    function announce() {
        if (primary)
            Osd.show(icon, primary.fraction, primary.percent + "%");
    }

    function _drain() {
        const ids = Object.keys(_queued);
        if (ids.length === 0)
            return;

        const id = ids[0];
        const value = _queued[id];
        const remaining = Object.assign({}, _queued);
        delete remaining[id];
        _queued = remaining;

        writer.command = ["desktopctl", "brightness", "set", String(Math.round(value * 100)), "--device", id];
        writer.running = true;
    }

    function _ingest(payload) {
        let listed = payload.devices || [];
        if (listed.length === 0 && payload.available)
            listed = [payload];

        const usable = [];
        for (let i = 0; i < listed.length; i++) {
            const device = listed[i];
            const max = Math.max(0, parseInt(device.max || 0, 10));
            if (!device.available || !device.device || max <= 0)
                continue;

            const fraction = Math.max(0, Math.min(1, Number(device.fraction || 0)));
            usable.push({
                kind: device.kind || "",
                device: device.device,
                label: device.label || String(device.device).replace(/_/g, " "),
                connector: device.connector || "",
                raw: Math.max(0, parseInt(device.raw || 0, 10)),
                max: max,
                fraction: fraction,
                percent: Math.round(fraction * 100)
            });
        }
        _all = usable;
    }

    Component.onCompleted: refresh()

    readonly property Process _status: Process {
        id: status
        command: ["desktopctl", "brightness", "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root._reading !== root._writes)
                    return;
                try {
                    root._ingest(JSON.parse(this.text));
                } catch (e) {
                    root._all = [];
                }
            }
        }
    }

    readonly property Process _writer: Process {
        id: writer
        onExited: code => {
            // A successful write needs no read-back: the value sent is the
            // truth. The poll below still catches the monitor's own buttons.
            if (code !== 0)
                root.refresh();
            else
                root._drain();
        }
    }

    readonly property Timer _poll: Timer {
        // Safety net only. Enumerating DDC buses costs over a second, and every
        // in-shell path already refreshes on demand; this exists to notice
        // changes made from the monitor's physical buttons.
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}
