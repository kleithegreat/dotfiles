pragma Singleton

import QtQuick
import Quickshell.Bluetooth as Bluez

// bluez's live DBus objects: nothing to poll or parse.
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
    readonly property var discovered: devices.filter(device => !device.paired && device.name !== "" && device.name.replace(/-/g, ":") !== device.address)

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

    // A one-shot discovery write while the adapter is off is refused and never retried.
    property var _seekers: []
    property var _pairingDevice: null
    readonly property string pairingAddress: _pairingDevice ? _pairingDevice.address : ""

    function seek(who, wanted) {
        const others = _seekers.filter(name => name !== who);
        _seekers = wanted ? others.concat([who]) : others;
    }

    readonly property Binding _discovery: Binding {
        target: root.adapter
        property: "discovering"
        value: root._seekers.length > 0 && root.powered
        when: root.adapter !== null
    }

    function connect(device) {
        if (device)
            device.connect();
    }

    function disconnect(device) {
        if (device)
            device.disconnect();
    }

    function _finishPairing() {
        seek("pairing", false);
        _pairingDevice = null;
        pairTimeout.stop();
    }

    function pair(device) {
        if (!device || _pairingDevice)
            return;
        _pairingDevice = device;
        seek("pairing", true);
        pairTimeout.restart();
        device.pair();
    }

    readonly property Connections _pairingEvents: Connections {
        target: root._pairingDevice
        function onPairedChanged() {
            const dev = root._pairingDevice;
            if (!dev || !dev.paired)
                return;
            dev.trusted = true;
            dev.connect();
            root._finishPairing();
        }
        function onPairingChanged() {
            const dev = root._pairingDevice;
            if (!dev || dev.pairing || dev.paired)
                return;
            Toast.error("Could not pair with " + (dev.name || dev.address));
            root._finishPairing();
        }
    }

    readonly property Timer _pairTimeout: Timer {
        id: pairTimeout
        interval: 30000
        onTriggered: {
            const dev = root._pairingDevice;
            if (!dev)
                return;
            if (dev.pairing)
                dev.cancelPair();
            Toast.error("Pairing timed out");
            root._finishPairing();
        }
    }

    function forget(device) {
        if (device)
            device.forget();
    }

    function batteryFor(device) {
        return device && device.batteryAvailable ? Math.round(device.battery * 100) : -1;
    }
}
