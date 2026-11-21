pragma Singleton

import QtQuick
import Quickshell.Io

// Every call is `pkexec howdy` in a form the laptop's polkit rule grants.
QtObject {
    id: root

    // [{ id, time, label }], `time` as howdy prints it.
    property var models: []

    // "scanning", "done" or "failed" until dismissed, "" when idle; root-run, so uncancellable.
    property string phase: ""
    // howdy's last line on a failed scan, e.g. "No face detected, aborting".
    property string result: ""

    readonly property bool busy: add.running || remove.running

    function refresh() {
        if (!list.running)
            list.running = true;
    }

    function start() {
        if (busy)
            return;
        phase = "scanning";
        result = "";
        add.running = true;
    }

    function dismiss() {
        phase = "";
    }

    function forget(id) {
        if (busy)
            return;
        remove.command = ["pkexec", "howdy", "-y", "--plain", "remove", String(id)];
        remove.running = true;
    }

    readonly property Process _list: Process {
        id: list
        command: ["pkexec", "howdy", "--plain", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = [];
                const lines = this.text.split("\n");
                for (let i = 0; i < lines.length; i++) {
                    const row = lines[i].match(/^(\d+),([^,]+),(.*)$/);
                    if (row)
                        found.push({ id: row[1], time: row[2], label: row[3] });
                }
                root.models = found;
            }
        }
    }

    readonly property Process _add: Process {
        id: add
        command: ["pkexec", "howdy", "-y", "--plain", "add"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n");
                root.result = lines[lines.length - 1];
            }
        }
        onExited: code => {
            root.phase = code === 0 ? "done" : "failed";
            root.refresh();
        }
    }

    readonly property Process _remove: Process {
        id: remove
        stderr: StdioCollector {
            id: removed
        }
        onExited: code => {
            if (code !== 0)
                Toast.failure(removed.text.trim(), "Could not remove face model");
            root.refresh();
        }
    }
}
