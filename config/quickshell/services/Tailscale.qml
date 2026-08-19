pragma Singleton

import QtQuick
import Quickshell.Io

QtObject {
    id: root

    // Running · Stopped · NeedsLogin · NoState
    property string state: "Stopped"
    property string ip: ""
    property string tailnet: ""
    property bool exitNode: false
    property string pending: ""

    readonly property bool up: state === "Running"
    readonly property bool busy: pending !== "" || command.running

    function refresh() {
        if (!status.running)
            status.running = true;
    }

    function set(enabled) {
        if (busy)
            return;
        pending = enabled ? "up" : "down";
        state = enabled ? "Running" : "Stopped";
        command.command = ["tailscale", enabled ? "up" : "down"];
        command.running = true;
    }

    function toggle() {
        set(!up);
    }

    Component.onCompleted: refresh()

    readonly property Process _status: Process {
        id: status
        command: ["tailscale", "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(this.text);
                    root.state = data.BackendState || "NoState";
                    root.ip = (data.TailscaleIPs || [])[0] || "";
                    root.tailnet = data.MagicDNSSuffix || "";
                    root.exitNode = !!(data.ExitNodeStatus && data.ExitNodeStatus.Online);
                    root.pending = "";
                } catch (e) {
                    root.state = "NoState";
                }
            }
        }
    }

    readonly property Process _command: Process {
        id: command
        stderr: StdioCollector {
            id: failure
        }
        onExited: code => {
            root.pending = "";
            if (code !== 0)
                Toast.error(failure.text.trim().split("\n").filter(line => line !== "").pop() || "Tailscale command failed");
            root.refresh();
        }
    }

    readonly property Timer _poll: Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}
