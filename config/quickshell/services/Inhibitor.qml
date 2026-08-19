import QtQuick
import Quickshell.Io

// A held systemd inhibition. The lock exists for exactly as long as the process
// runs, so `active` is the process state itself rather than a flag that could
// disagree with it.
Process {
    id: root

    property string what: "idle"
    property string mode: "block"
    property string why: ""
    // Distinguishes "we asked it to stop" from "it died", so only the latter is
    // reported to the user.
    property bool _requestedStop: false
    property bool _shuttingDown: false

    readonly property bool active: running

    function set(enabled) {
        if (enabled === running)
            return;

        if (enabled) {
            _requestedStop = false;
            running = true;
            return;
        }

        _requestedStop = true;
        running = false;
    }

    function toggle() {
        set(!running);
    }

    command: ["systemd-inhibit", "--what=" + what, "--mode=" + mode, "--who=quickshell", "--why=" + why, "sleep", "infinity"]

    stderr: StdioCollector {
        id: errors
    }

    onExited: {
        const stopped = root._requestedStop;
        root._requestedStop = false;
        if (root._shuttingDown || stopped)
            return;

        const text = errors.text.trim().split("\n").filter(line => line.trim() !== "").pop();
        Toast.error(text || "Inhibitor stopped unexpectedly");
    }

    Component.onDestruction: {
        _shuttingDown = true;
        if (running) {
            _requestedStop = true;
            running = false;
        }
    }
}
