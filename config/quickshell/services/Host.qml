pragma Singleton

import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower

// What this machine can actually do. Surfaces are hidden rather than shown
// disabled: a laptop control on a desktop is noise, not information.
QtObject {
    id: root

    property bool laptop: false
    property bool wifi: false
    property bool fingerprint: false
    property bool powerProfiles: false

    readonly property bool battery: UPower.displayDevice.isPresent

    // The desktop host is pinned to performance in NixOS, so profile switching
    // is only ever offered on laptop-like chassis.
    readonly property bool profileSwitching: laptop && powerProfiles

    readonly property Process _chassis: Process {
        running: true
        command: ["hostnamectl", "chassis"]
        stdout: StdioCollector {
            onStreamFinished: {
                const kind = this.text.trim().toLowerCase();
                root.laptop = kind === "laptop" || kind === "notebook" || kind === "convertible";
            }
        }
    }

    readonly property Process _wifi: Process {
        running: true
        command: ["nmcli", "-t", "-f", "TYPE", "device", "status"]
        stdout: StdioCollector {
            onStreamFinished: root.wifi = this.text.split("\n").some(line => line.trim() === "wifi")
        }
    }

    readonly property Process _profiles: Process {
        running: true
        command: ["powerprofilesctl", "get"]
        onExited: code => root.powerProfiles = code === 0
    }

    readonly property Process _fingerprint: Process {
        running: true
        command: ["busctl", "tree", "net.reactivated.Fprint"]
        stdout: StdioCollector {
            onStreamFinished: root.fingerprint = this.text.indexOf("/net/reactivated/Fprint/Device/") !== -1
        }
    }
}
