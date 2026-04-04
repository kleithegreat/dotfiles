pragma Singleton
import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower

QtObject {
    id: root

    readonly property bool hasWifi: _hasWifi
    readonly property bool hasBattery: UPower.displayDevice.isPresent

    property bool _hasWifi: false

    Component.onCompleted: wifiCheckProc.running = true

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
}
