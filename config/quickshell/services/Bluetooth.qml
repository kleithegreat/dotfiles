pragma Singleton

import QtQuick
import Quickshell.Bluetooth as Bluez

// Bluetooth over bluez's own DBus objects. The old service shelled out to
// `bluetoothctl --timeout 2` on a poll and reassembled the answer from four
// text scrapes — on this desktop bluetoothctl is not even installed, so it had
// been quietly failing. Adapter and device state are live objects; there is
// nothing here to poll and nothing to parse.
QtObject {
    id: root

    readonly property var adapter: Bluez.Bluetooth.defaultAdapter
    readonly property bool available: adapter !== null
    readonly property bool powered: adapter?.enabled ?? false
    readonly property bool discovering: adapter?.discovering ?? false

    readonly property var devices: Bluez.Bluetooth.devices.values

    readonly property var connected: devices.filter(device => device.connected)
    readonly property var paired: devices.filter(device => device.paired && !device.connected)
    // Anything unpaired and named. Address-only entries are beacons and clutter.
    readonly property var discovered: devices.filter(device => !device.paired && device.name !== "" && device.name !== device.address)

    readonly property var primary: connected.length > 0 ? connected[0] : null

    readonly property string label: {
        if (!available)
            return "Unavailable";
        if (!powered)
            return "Off";
        if (connected.length === 0)
            return "On";
        return connected.length === 1 ? connected[0].name : connected.length + " devices";
    }

    readonly property string icon: !powered || !available ? "bluetooth-off" : connected.length > 0 ? "bluetooth-connected" : "bluetooth-on"

    function setPowered(enabled) {
        if (adapter)
            adapter.enabled = enabled;
    }

    function togglePower() {
        setPowered(!powered);
    }

    function setDiscovering(enabled) {
        if (adapter)
            adapter.discovering = enabled;
    }

    function connect(device) {
        if (device)
            device.connect();
    }

    function disconnect(device) {
        if (device)
            device.disconnect();
    }

    function pair(device) {
        if (device)
            device.pair();
    }

    function forget(device) {
        if (device)
            device.forget();
    }

    function batteryFor(device) {
        return device && device.batteryAvailable ? Math.round(device.battery * 100) : -1;
    }
}
