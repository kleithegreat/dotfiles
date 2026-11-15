pragma Singleton

import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower

QtObject {
    id: root

    property bool laptop: false
    property bool fingerprint: false
    property bool face: false
    property bool touchpad: false
    property bool powerProfiles: false
    property bool heater: false

    readonly property bool battery: UPower.displayDevice.isPresent

    // The desktop is pinned to performance in NixOS.
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

    readonly property Process _profiles: Process {
        running: true
        command: ["powerprofilesctl", "get"]
        onExited: code => root.powerProfiles = code === 0
    }

    readonly property Process _heater: Process {
        running: true
        command: ["systemctl", "--user", "cat", "heater.target"]
        onExited: code => root.heater = code === 0
    }

    readonly property Process _touchpad: Process {
        running: true
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.touchpad = JSON.parse(this.text).mice.some(device => /touchpad|trackpad/i.test(device.name));
                } catch (e) {
                }
            }
        }
    }

    readonly property Process _fingerprint: Process {
        running: true
        command: ["busctl", "tree", "net.reactivated.Fprint"]
        stdout: StdioCollector {
            onStreamFinished: root.fingerprint = this.text.indexOf("/net/reactivated/Fprint/Device/") !== -1
        }
    }

    readonly property Process _face: Process {
        running: true
        command: ["test", "-e", "/etc/howdy/config.ini"]
        onExited: code => root.face = code === 0
    }
}
