pragma Singleton
import Quickshell
import QtQuick
import Quickshell.Io

QtObject {
    id: root

    readonly property bool inhibited: inhibitorProc.running
    readonly property bool lidInhibited: lidInhibitorProc.running
    readonly property bool bootEnabled: {
        let value = Quickshell.env("DESKTOPCTL_IDLE_INHIBIT_DEFAULT");
        if (value === null || value === undefined)
            return false;

        let text = String(value).trim().toLowerCase();
        return text === "1" || text === "true" || text === "yes" || text === "on";
    }

    property bool _idleStopRequested: false
    property bool _lidStopRequested: false
    property bool _shuttingDown: false

    function applyBootDefault() {
        if (bootEnabled)
            setInhibited(true);
    }

    function toggle() {
        setInhibited(!inhibited);
    }

    function toggleLid() {
        setLidInhibited(!lidInhibited);
    }

    function setInhibited(enabled) {
        if (enabled === inhibited)
            return;

        if (enabled) {
            _idleStopRequested = false;
            inhibitorProc.errBuf = "";
            inhibitorProc.running = true;
            return;
        }

        if (!inhibitorProc.running)
            return;

        _idleStopRequested = true;
        inhibitorProc.running = false;
    }

    function setLidInhibited(enabled) {
        if (enabled === lidInhibited)
            return;

        if (enabled) {
            _lidStopRequested = false;
            lidInhibitorProc.errBuf = "";
            lidInhibitorProc.running = true;
            return;
        }

        if (!lidInhibitorProc.running)
            return;

        _lidStopRequested = true;
        lidInhibitorProc.running = false;
    }

    function inhibitErrorMessage(errBuf) {
        let text = (errBuf || "").trim();
        if (text === "")
            return "Unable to toggle inhibit";

        let lines = text.split(/\r?\n/);
        for (let i = lines.length - 1; i >= 0; --i) {
            let line = lines[i].trim();
            if (line !== "")
                return line;
        }

        return "Unable to toggle inhibit";
    }

    Component.onDestruction: {
        _shuttingDown = true;
        if (inhibitorProc.running) {
            _idleStopRequested = true;
            inhibitorProc.running = false;
        }
        if (lidInhibitorProc.running) {
            _lidStopRequested = true;
            lidInhibitorProc.running = false;
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
            let requestedStop = root._idleStopRequested;
            root._idleStopRequested = false;

            if (root._shuttingDown || requestedStop) {
                inhibitorProc.errBuf = "";
                return;
            }

            ToastService.showError(root.inhibitErrorMessage(inhibitorProc.errBuf));

            inhibitorProc.errBuf = "";
        }
    }

    property Process lidInhibitorProc: Process {
        id: lidInhibitorProc
        command: [
            "systemd-inhibit",
            "--what=handle-lid-switch",
            "--mode=block",
            "--who=quickshell",
            "--why=Quick Settings lid-switch inhibit",
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
                lidInhibitorProc.errBuf += line + "\n";
            }
        }

        onExited: (code) => {
            let requestedStop = root._lidStopRequested;
            root._lidStopRequested = false;

            if (root._shuttingDown || requestedStop) {
                lidInhibitorProc.errBuf = "";
                return;
            }

            ToastService.showError(root.inhibitErrorMessage(lidInhibitorProc.errBuf));

            lidInhibitorProc.errBuf = "";
        }
    }
}
