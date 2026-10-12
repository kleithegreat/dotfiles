pragma Singleton

import QtQuick
import Quickshell.Io

// Window session restore. The daemon owns the state and pushes it over the
// Desktopctl socket; there is no direct read ([[session-restore]]).
QtObject {
    id: root

    property bool automatic: true
    property int restorable: 0
    readonly property bool busy: command.running

    function setAutomatic(on) {
        _run(["desktopctl", "session", "automatic", String(on)]);
    }

    function restore() {
        _run(["desktopctl", "session", "restore"]);
    }

    function _run(argv) {
        if (command.running)
            return;
        command.command = argv;
        command.running = true;
    }

    readonly property Connections _events: Connections {
        target: Desktopctl
        function onSessionChanged(status) {
            root.automatic = status.automatic;
            root.restorable = status.restorable;
        }
    }

    readonly property Process _command: Process {
        id: command
        stderr: StdioCollector {
            onStreamFinished: Toast.failure(this.text)
        }
    }
}
