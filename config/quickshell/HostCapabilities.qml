pragma Singleton
import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower

QtObject {
    id: root

    readonly property bool isLaptop: _isLaptop
    readonly property bool hasWifi: _hasWifi
    readonly property bool hasBattery: UPower.displayDevice.isPresent
    // The desktop host is pinned to performance in NixOS, so only laptop-like
    // hosts expose interactive power-profile controls in the shell.
    readonly property bool hasPowerProfiles: _isLaptop && _hasPowerProfiles
    readonly property bool hasFingerprintReader: _hasFingerprintReader

    property bool _isLaptop: false
    property bool _hasWifi: false
    property bool _hasPowerProfiles: false
    property bool _hasFingerprintReader: false

    Component.onCompleted: {
        chassisCheckProc.running = true;
        wifiCheckProc.running = true;
        ppCheckProc.running = true;
        fingerprintCheckProc.running = true;
    }

    property Process chassisCheckProc: Process {
        command: ["hostnamectl", "chassis"]
        running: false
        property string chassis: ""
        stdout: SplitParser { onRead: (line) => { root.chassisCheckProc.chassis += line.trim().toLowerCase(); } }
        onExited: {
            let kind = chassis.trim();
            root._isLaptop = kind === "laptop" || kind === "notebook" || kind === "convertible";
            chassis = "";
        }
    }

    property Process wifiCheckProc: Process {
        id: wifiCheckProc
        command: ["nmcli", "-t", "-f", "TYPE", "device", "status"]
        running: false
        property bool found: false
        stdout: SplitParser { onRead: (line) => {
            if (line.trim() === "wifi")
                wifiCheckProc.found = true;
        } }
        onExited: {
            root._hasWifi = wifiCheckProc.found;
            wifiCheckProc.found = false;
        }
    }

    property Process ppCheckProc: Process {
        command: ["powerprofilesctl", "get"]
        running: false
        onExited: (code) => { root._hasPowerProfiles = (code === 0); }
    }

    property Process fingerprintCheckProc: Process {
        id: fingerprintCheckProc
        command: ["busctl", "tree", "net.reactivated.Fprint"]
        running: false
        property bool found: false
        stdout: SplitParser { onRead: (line) => {
            if (line.indexOf("/net/reactivated/Fprint/Device/") !== -1)
                root.fingerprintCheckProc.found = true;
        } }
        onExited: {
            root._hasFingerprintReader = root.fingerprintCheckProc.found;
            root.fingerprintCheckProc.found = false;
        }
    }
}
