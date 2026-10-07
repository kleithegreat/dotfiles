pragma Singleton

import QtQuick
import Quickshell.Io

// Heater mode is the `heater` user unit being active, nothing more.
QtObject {
    id: root

    property bool active: false

    readonly property bool busy: command.running

    function refresh() {
        status.running = true;
    }

    function set(enabled) {
        if (busy)
            return;
        active = enabled;
        command.command = ["systemctl", "--user", enabled ? "start" : "stop", "heater.service"];
        command.running = true;
    }

    readonly property Process _status: Process {
        id: status
        command: ["systemctl", "--user", "is-active", "--quiet", "heater.service"]
        onExited: code => root.active = code === 0
    }

    readonly property Process _command: Process {
        id: command
        stderr: StdioCollector {
            id: failure
        }
        onExited: code => {
            if (code !== 0)
                Toast.error(failure.text.trim().split("\n").filter(line => line !== "").pop() || "Could not switch the heater");
            root.refresh();
        }
    }
}
