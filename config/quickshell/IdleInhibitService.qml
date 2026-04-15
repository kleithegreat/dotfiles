pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root

    readonly property bool inhibited: inhibitorProc.running

    property bool _stopRequested: false
    property bool _shuttingDown: false

    function toggle() {
        setInhibited(!inhibited);
    }

    function setInhibited(enabled) {
        if (enabled === inhibited)
            return;

        if (enabled) {
            _stopRequested = false;
            inhibitorProc.errBuf = "";
            inhibitorProc.running = true;
            return;
        }

        if (!inhibitorProc.running)
            return;

        _stopRequested = true;
        inhibitorProc.running = false;
    }

    function inhibitErrorMessage(errBuf) {
        let text = (errBuf || "").trim();
        if (text === "")
            return "Unable to toggle idle inhibit";

        let lines = text.split(/\r?\n/);
        for (let i = lines.length - 1; i >= 0; --i) {
            let line = lines[i].trim();
            if (line !== "")
                return line;
        }

        return "Unable to toggle idle inhibit";
    }

    Component.onDestruction: {
        _shuttingDown = true;
        if (inhibitorProc.running) {
            _stopRequested = true;
            inhibitorProc.running = false;
        }
    }

    property Process inhibitorProc: Process {
        id: inhibitorProc
        command: [
            "systemd-inhibit",
            "--what=idle",
            "--who=quickshell",
            "--why=Quick Settings idle inhibit",
            "sleep",
            "infinity"
        ]
        running: false
        property string errBuf: ""

        onRunningChanged: {
            if (running)
                errBuf = "";
        }

        stderr: SplitParser {
            onRead: (line) => {
                inhibitorProc.errBuf += line + "\n";
            }
        }

        onExited: (code) => {
            let requestedStop = root._stopRequested;
            root._stopRequested = false;

            if (root._shuttingDown || requestedStop) {
                inhibitorProc.errBuf = "";
                return;
            }

            ToastService.showError(root.inhibitErrorMessage(inhibitorProc.errBuf));

            inhibitorProc.errBuf = "";
        }
    }
}
