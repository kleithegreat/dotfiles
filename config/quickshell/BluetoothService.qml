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

    readonly property bool refreshing: showProc.running || connInfoProc.running || pairedProc.running || allDevicesProc.running

    property ListModel pairedModel: ListModel { id: pairedModel }
    property ListModel discoveredModel: ListModel { id: discoveredModel }

    function refresh(preservePowerState) {
        if (preservePowerState === undefined)
            preservePowerState = false;
        connectedName = "";
        connectedMac = "";
        connectedBattery = -1;
        scanning = false;
        pairedModel.clear();
        discoveredModel.clear();
        if (!preservePowerState)
            powerStateKnown = false;
        showProc.running = true;
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
        disconnectProc.running = true;
    }

    function togglePower() {
        powerProc.command = ["bluetoothctl", "--timeout", "5", "power", powered ? "off" : "on"];
        powerProc.running = true;
    }

    function clearConnectError() {
        connectError = "";
    }

    function isMacAddress(name) {
        return /^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$/.test(name);
    }

    // ── Processes ─────────────────────────────────────────────

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
            if (root.powered) connInfoProc.running = true;
        }
    }

    property Process connInfoProc: Process {
        id: connInfoProc
        command: ["bash", "-c",
            "dev=$(bluetoothctl --timeout 2 devices Connected 2>/dev/null | head -1); " +
            "[ -z \"$dev\" ] && exit 0; " +
            "mac=$(echo \"$dev\" | awk '{print $2}'); " +
            "name=$(echo \"$dev\" | sed 's/^Device [^ ]* //'); " +
            "echo \"CONN|$mac|$name\"; " +
            "batt=$(bluetoothctl --timeout 2 info \"$mac\" 2>/dev/null | awk -F'[()]' '/Battery Percentage/{print $2}'); " +
            "[ -n \"$batt\" ] && echo \"BATT|$batt\""
        ]
        running: false
        stdout: SplitParser { onRead: (line) => {
            if (line.startsWith("CONN|")) {
                let parts = line.substring(5).split("|");
                if (parts.length >= 2) {
                    root.connectedMac = parts[0];
                    root.connectedName = parts.slice(1).join("|");
                }
            } else if (line.startsWith("BATT|")) {
                root.connectedBattery = parseInt(line.substring(5)) || -1;
            }
        } }
        onExited: { pairedProc.running = true; }
    }

    property Process pairedProc: Process {
        id: pairedProc
        command: ["bluetoothctl", "--timeout", "2", "devices", "Paired"]
        running: false
        stdout: SplitParser { onRead: (line) => {
            let m = line.match(/^Device\s+(\S+)\s+(.+)$/);
            if (!m) return;
            let mac = m[1], name = m[2];
            if (root.isMacAddress(name)) return;
            if (mac === root.connectedMac) return;
            pairedModel.append({ mac: mac, name: name });
        } }
        onExited: { allDevicesProc.running = true; }
    }

    property Process allDevicesProc: Process {
        id: allDevicesProc
        command: ["bluetoothctl", "--timeout", "2", "devices"]
        running: false
        stdout: SplitParser { onRead: (line) => {
            let m = line.match(/^Device\s+(\S+)\s+(.+)$/);
            if (!m) return;
            let mac = m[1], name = m[2];
            if (root.isMacAddress(name)) return;
            if (mac === root.connectedMac) return;
            for (let i = 0; i < pairedModel.count; i++)
                if (pairedModel.get(i).mac === mac) return;
            discoveredModel.append({ mac: mac, name: name });
        } }
        onExited: { root.startScan(); }
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
        onExited: (code, status) => {
            if (code === 0) {
                root.connectingName = "";
                root.connecting = false;
                root.refresh(true);
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
        onExited: { root.refresh(true); }
    }

    property Process powerProc: Process {
        id: powerProc
        running: false
        onExited: { root.refresh(); }
    }
}
