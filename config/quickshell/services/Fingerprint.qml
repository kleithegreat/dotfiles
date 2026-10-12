pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property var enrolled: []

    // An enrolment stays on show until dismissed: `finger` is the one being
    // added and `phase` is "scanning", "done" or "failed" ("" when idle).
    property string finger: ""
    property string phase: ""
    property int captured: 0
    property int stages: 0
    // fprintd's last word on the scan in progress, e.g. "enroll-retry-scan".
    property string result: ""

    readonly property bool busy: enroll.running || remove.running
    readonly property real fraction: stages > 0 ? Math.min(1, captured / stages) : 0

    readonly property var fingers: [
        { id: "right-index-finger", label: "Right index" },
        { id: "right-middle-finger", label: "Right middle" },
        { id: "right-thumb", label: "Right thumb" },
        { id: "left-index-finger", label: "Left index" },
        { id: "left-middle-finger", label: "Left middle" },
        { id: "left-thumb", label: "Left thumb" }
    ]

    function refresh() {
        if (!list.running)
            list.running = true;
    }

    function has(id) {
        return enrolled.indexOf(id) >= 0;
    }

    function start(id) {
        if (busy)
            return;
        finger = id;
        phase = "scanning";
        captured = 0;
        result = "";
        enroll.command = ["fprintd-enroll", "--finger", id];
        enroll.running = true;
    }

    function cancel() {
        dismiss();
        enroll.running = false;
    }

    function dismiss() {
        finger = "";
        phase = "";
    }

    function forget(id) {
        if (busy)
            return;
        remove.command = ["fprintd-delete", Quickshell.env("USER") || "", "--finger", id];
        remove.running = true;
    }

    Component.onCompleted: {
        refresh();
        count.running = true;
    }

    readonly property Process _list: Process {
        id: list
        command: ["fprintd-list", Quickshell.env("USER") || ""]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = [];
                const matches = this.text.match(/#\d+:\s*(\S+)/g) || [];
                for (let i = 0; i < matches.length; i++)
                    found.push(matches[i].replace(/#\d+:\s*/, ""));
                root.enrolled = found;
            }
        }
    }

    readonly property Process _count: Process {
        id: count
        command: ["sh", "-c", "busctl --system get-property net.reactivated.Fprint \"$(busctl --system call net.reactivated.Fprint /net/reactivated/Fprint/Manager net.reactivated.Fprint.Manager GetDefaultDevice | cut -d'\"' -f2)\" net.reactivated.Fprint.Device num-enroll-stages"]
        stdout: StdioCollector {
            onStreamFinished: root.stages = Math.max(0, parseInt(this.text.replace(/^i\s+/, "")) || 0)
        }
    }

    readonly property Process _enroll: Process {
        id: enroll
        stdout: SplitParser {
            onRead: line => {
                const found = line.match(/Enroll result:\s*(\S+)/);
                if (!found)
                    return;
                root.result = found[1];
                if (found[1] === "enroll-stage-passed")
                    root.captured += 1;
                else if (found[1] === "enroll-completed")
                    root.captured = Math.max(root.captured + 1, root.stages);
            }
        }
        onExited: {
            if (root.phase !== "scanning")
                return;
            root.phase = root.result === "enroll-completed" ? "done" : "failed";
            root.refresh();
        }
    }

    readonly property Process _remove: Process {
        id: remove
        stderr: StdioCollector {
            onStreamFinished: Toast.failure(this.text)
        }
        onExited: root.refresh()
    }
}
