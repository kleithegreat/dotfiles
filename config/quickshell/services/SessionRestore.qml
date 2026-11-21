pragma Singleton

import QtQuick

// Pushed by the daemon, which owns this state; no direct read ([[session-restore]]).
QtObject {
    id: root

    property bool automatic: true
    property int restorable: 0
    readonly property bool busy: writes.busy

    function setAutomatic(on) {
        writes.run(["desktopctl", "session", "automatic", String(on)], "automatic");
    }

    function restore() {
        writes.run(["desktopctl", "session", "restore"], "restore");
    }

    readonly property WriteQueue _writes: WriteQueue {
        id: writes
        failureText: "Session restore failed"
    }

    readonly property Connections _events: Connections {
        target: Desktopctl
        function onSessionChanged(status) {
            root.automatic = status.automatic;
            root.restorable = status.restorable;
        }
    }
}
