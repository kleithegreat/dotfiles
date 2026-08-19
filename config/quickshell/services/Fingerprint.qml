pragma Singleton

import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property var enrolled: []
    property string enrolling: ""
    property string status: ""

    readonly property bool busy: enroll.running || remove.running

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

    function has(finger) {
        return enrolled.indexOf(finger) >= 0;
    }

    function start(finger) {
        if (busy)
            return;
        enrolling = finger;
        status = "Touch the reader repeatedly";
        enroll.command = ["fprintd-enroll", "-f", finger];
        enroll.running = true;
    }

    function forget(finger) {
        if (busy)
            return;
        remove.command = ["fprintd-delete", Quickshell.env("USER") || ""];
        remove.running = true;
    }

    Component.onCompleted: refresh()

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

    readonly property Process _enroll: Process {
        id: enroll
        stdout: StdioCollector {
            id: enrollOutput
        }
        onExited: code => {
            root.enrolling = "";
            root.status = code === 0 ? "Enrolled" : enrollOutput.text.trim().split("\n").pop() || "Enrolment failed";
            root.refresh();
        }
    }

    readonly property Process _remove: Process {
        id: remove
        onExited: {
            root.status = "";
            root.refresh();
        }
    }
}
