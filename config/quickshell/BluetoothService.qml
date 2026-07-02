pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property bool powered: false
    property bool scanning: false
    property string connectedName: ""
    property string connectedMac: ""
    property int connectedBattery: -1
    property bool connecting: false
    property string connectingName: ""
    property string connectError: ""
    property bool powerStateKnown: false
    readonly property bool powerBusy: powerProc.running || _powerActionPending
    readonly property bool disconnectBusy: disconnectProc.running || _disconnectPending

    readonly property bool refreshing: showProc.running || connInfoProc.running || pairedProc.running || allDevicesProc.running

    property ListModel pairedModel: ListModel { id: pairedModel }
    property ListModel discoveredModel: ListModel { id: discoveredModel }

    Component.onCompleted: refreshSummary()

    function refresh(preservePowerState, withScan) {
        // Discovery scans cost battery and degrade co-located 2.4GHz Wi-Fi,
        // so only chain into one when the caller shows the device list
        // (settings pane / popup open); completion refreshes opt out.
        _scanAfterRefresh = withScan === undefined ? true : withScan;
        scanning = false;
        pairedModel.clear();
        discoveredModel.clear();
        if (!preservePowerState)
            powerStateKnown = false;
        if (showProc.running) {
            _refreshPending = true;
        } else {
            showProc.buf = "";
            showProc.running = true;
        }
    }

    function refreshSummary() {
        if (refreshing || scanProc.running || connectProc.running || disconnectProc.running || powerProc.running)
            return;
        _summaryShowDone = false;
        _summaryConnDone = false;
        if (!summaryShowProc.running)
            summaryShowProc.running = true;
        if (!summaryConnInfoProc.running)
            summaryConnInfoProc.running = true;
    }

    function startScan() {
        scanning = true;
        scanProc.running = true;
    }

    function connectDevice(mac, name) {
        connecting = true;
        connectingName = name;
        connectError = "";
        connectProc.command = ["bluetoothctl", "--timeout", "15", "connect", mac];
        connectProc.running = true;
    }

    function disconnectDevice() {
        if (disconnectProc.running || connectedMac === "")
            return;
        _disconnectRollbackState = snapshotSummaryState();
        _disconnectPending = true;
        connectedName = "";
        connectedMac = "";
        connectedBattery = -1;
        disconnectProc.running = true;
    }

    function togglePower() {
        if (powerProc.running)
            return;
        _powerRollbackState = snapshotSummaryState();
        _powerActionPending = true;
        let nextPowered = !powered;
        powerStateKnown = true;
        powered = nextPowered;
        scanning = false;
        if (!nextPowered) {
            connecting = false;
            connectingName = "";
            connectedName = "";
            connectedMac = "";
            connectedBattery = -1;
            pairedModel.clear();
            discoveredModel.clear();
        }
        powerProc.command = ["bluetoothctl", "--timeout", "5", "power", nextPowered ? "on" : "off"];
        powerProc.running = true;
    }

    function clearConnectError() {
        connectError = "";
    }

    function isMacAddress(name) {
        return /^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$/.test(name);
    }

    function _applyConnInfoLine(proc, line) {
        if (line.startsWith("CONN|")) {
            let parts = line.substring(5).split("|");
            if (parts.length >= 2) {
                proc.pendingMac = parts[0];
                proc.pendingName = parts.slice(1).join("|");
            }
        } else if (line.startsWith("BATT|")) {
            let batt = parseInt(line.substring(5), 10);
            proc.pendingBattery = isNaN(batt) ? -1 : batt;
        }
    }

    function _deviceFromLine(line) {
        let m = line.match(/^Device\s+(\S+)\s+(.+)$/);
        if (!m)
            return null;
        let mac = m[1], name = m[2];
        if (isMacAddress(name))
            return null;
        if (mac === connectedMac)
            return null;
        return { mac: mac, name: name };
    }

    function snapshotSummaryState() {
        return {
            powered: powered,
            powerStateKnown: powerStateKnown,
            connectedName: connectedName,
            connectedMac: connectedMac,
            connectedBattery: connectedBattery,
            connecting: connecting,
            connectingName: connectingName,
            scanning: scanning
        };
    }

    function restoreSummaryState(snapshot) {
        let state = snapshot || ({});
        powered = state.powered === true;
        powerStateKnown = state.powerStateKnown === true;
        connectedName = state.connectedName || "";
        connectedMac = state.connectedMac || "";
        connectedBattery = state.connectedBattery === undefined ? -1 : state.connectedBattery;
        connecting = state.connecting === true;
        connectingName = state.connectingName || "";
        scanning = state.scanning === true;
    }

    function _commitSummaryRefresh() {
        if (!_summaryShowDone || !_summaryConnDone)
            return;

        powered = _summaryPendingPowered;
        powerStateKnown = true;
        if (powered) {
            connectedMac = summaryConnInfoProc.pendingMac;
            connectedName = summaryConnInfoProc.pendingName;
            connectedBattery = summaryConnInfoProc.pendingBattery;
        } else {
            connectedMac = "";
            connectedName = "";
            connectedBattery = -1;
        }

        _summaryShowDone = false;
        _summaryConnDone = false;
    }

    property bool _refreshPending: false
    property bool _scanAfterRefresh: false

    // Shared by connInfoProc and summaryConnInfoProc; the Process objects stay
    // separate so full refreshes and summary polls can run concurrently
    // without sharing parse buffers.
    readonly property string _connInfoScript:
        "dev=$(bluetoothctl --timeout 2 devices Connected 2>/dev/null | head -1); " +
        "[ -z \"$dev\" ] && exit 0; " +
        "mac=$(echo \"$dev\" | awk '{print $2}'); " +
        "name=$(echo \"$dev\" | sed 's/^Device [^ ]* //'); " +
        "echo \"CONN|$mac|$name\"; " +
        "batt=$(bluetoothctl --timeout 2 info \"$mac\" 2>/dev/null | awk -F'[()]' '/Battery Percentage/{print $2}'); " +
        "[ -n \"$batt\" ] && echo \"BATT|$batt\""
    property bool _powerActionPending: false
    property bool _disconnectPending: false
    property bool _summaryPendingPowered: false
    property bool _summaryShowDone: false
    property bool _summaryConnDone: false
    property var _powerRollbackState: ({})
    property var _disconnectRollbackState: ({})

    // Processes

    property Process showProc: Process {
        id: showProc
        command: ["bluetoothctl", "--timeout", "2", "show"]
        running: false
        property string buf: ""
        stdout: SplitParser { onRead: (line) => { showProc.buf += line + "\n"; } }
        onExited: {
            root.powered = showProc.buf.indexOf("Powered: yes") >= 0;
            root.powerStateKnown = true;
            showProc.buf = "";
            if (root._refreshPending) {
                root._refreshPending = false;
                showProc.running = true;
                return;
            }
            if (root.powered) {
                connInfoProc.running = true;
            } else {
                root.connectedMac = "";
                root.connectedName = "";
                root.connectedBattery = -1;
            }
        }
    }

    property Process connInfoProc: Process {
        id: connInfoProc
        command: ["bash", "-c", root._connInfoScript]
        running: false
        property string pendingMac: ""
        property string pendingName: ""
        property int pendingBattery: -1
        onRunningChanged: {
            if (running) {
                pendingMac = "";
                pendingName = "";
                pendingBattery = -1;
            }
        }
        stdout: SplitParser { onRead: (line) => root._applyConnInfoLine(connInfoProc, line) }
        onExited: {
            root.connectedMac = connInfoProc.pendingMac;
            root.connectedName = connInfoProc.pendingName;
            root.connectedBattery = connInfoProc.pendingBattery;
            pairedProc.running = true;
        }
    }

    property Process pairedProc: Process {
        id: pairedProc
        command: ["bluetoothctl", "--timeout", "2", "devices", "Paired"]
        running: false
        stdout: SplitParser { onRead: (line) => {
            let dev = root._deviceFromLine(line);
            if (dev)
                pairedModel.append(dev);
        } }
        onExited: { allDevicesProc.running = true; }
    }

    property Process allDevicesProc: Process {
        id: allDevicesProc
        command: ["bluetoothctl", "--timeout", "2", "devices"]
        running: false
        stdout: SplitParser { onRead: (line) => {
            let dev = root._deviceFromLine(line);
            if (!dev) return;
            for (let i = 0; i < pairedModel.count; i++)
                if (pairedModel.get(i).mac === dev.mac) return;
            discoveredModel.append(dev);
        } }
        onExited: { if (root._scanAfterRefresh) root.startScan(); }
    }

    property Process scanProc: Process {
        id: scanProc
        command: ["bluetoothctl", "--timeout", "8", "scan", "on"]
        running: false
        onExited: { root.scanning = false; }
    }

    property Process connectProc: Process {
        id: connectProc
        running: false
        onExited: (code) => {
            if (code === 0) {
                root.connectingName = "";
                root.connecting = false;
                root.refresh(true, false);
            } else {
                root.connectError = "Connection failed";
                root.connecting = false;
            }
        }
    }

    property Process disconnectProc: Process {
        id: disconnectProc
        command: ["bluetoothctl", "--timeout", "5", "disconnect"]
        running: false
        onExited: (code) => {
            if (code === 0) {
                root._disconnectPending = false;
                root.refresh(true, false);
            } else {
                root.restoreSummaryState(root._disconnectRollbackState);
                root._disconnectPending = false;
            }
        }
    }

    property Process powerProc: Process {
        id: powerProc
        running: false
        onExited: (code) => {
            if (code === 0) {
                root._powerActionPending = false;
                root.refresh(true, false);
            } else {
                root.restoreSummaryState(root._powerRollbackState);
                root._powerActionPending = false;
            }
        }
    }

    property Process summaryShowProc: Process {
        id: summaryShowProc
        command: ["bluetoothctl", "--timeout", "2", "show"]
        running: false
        property string buf: ""
        stdout: SplitParser { onRead: (line) => { summaryShowProc.buf += line + "\n"; } }
        onExited: {
            root._summaryPendingPowered = summaryShowProc.buf.indexOf("Powered: yes") >= 0;
            summaryShowProc.buf = "";
            root._summaryShowDone = true;
            root._commitSummaryRefresh();
        }
    }

    property Process summaryConnInfoProc: Process {
        id: summaryConnInfoProc
        command: ["bash", "-c", root._connInfoScript]
        running: false
        property string pendingMac: ""
        property string pendingName: ""
        property int pendingBattery: -1
        onRunningChanged: {
            if (running) {
                pendingMac = "";
                pendingName = "";
                pendingBattery = -1;
            }
        }
        stdout: SplitParser { onRead: (line) => root._applyConnInfoLine(summaryConnInfoProc, line) }
        onExited: {
            root._summaryConnDone = true;
            root._commitSummaryRefresh();
        }
    }

    property Timer summaryTimer: Timer {
        interval: 10000
        repeat: true
        running: true
        onTriggered: root.refreshSummary()
    }
}
