import QtQuick
import Quickshell.Io

// `active` is the process state itself, so it cannot disagree with the lock.
Process {
    id: root

    property string what: "idle"
    property string why: ""
    // Only an unrequested exit is reported.
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

    command: ["systemd-inhibit", "--what=" + what, "--mode=block", "--who=quickshell", "--why=" + why, "sleep", "infinity"]

    stderr: StdioCollector {
        id: errors
    }

    onExited: {
        const stopped = root._requestedStop;
        root._requestedStop = false;
        if (root._shuttingDown || stopped)
            return;

        Toast.failure(errors.text, "Inhibitor stopped unexpectedly");
    }

    Component.onDestruction: {
        _shuttingDown = true;
        if (running) {
            _requestedStop = true;
            running = false;
        }
    }
}
