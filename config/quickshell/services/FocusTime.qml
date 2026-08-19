pragma Singleton

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io

// The daemon's focus tracker is the only writer. This reads its JSON heartbeat
// and nothing else — never the SQLite database behind it, and never a repair.
QtObject {
    id: root

    property var data: ({})

    readonly property int today: data.total || 0
    readonly property int average: data.average || 0
    readonly property int yesterday: data.yesterday || 0
    readonly property string weekRange: data.week_range || ""
    readonly property string current: data.current || ""
    readonly property var apps: data.apps || []
    readonly property var week: data.week || []

    // The file is a once-per-second heartbeat, so its age is the only liveness
    // signal there is.
    readonly property bool stale: {
        void tick.triggeredOnStart;
        const stamp = data.last_updated || 0;
        return stamp === 0 || Date.now() / 1000 - stamp > 5;
    }

    function format(seconds) {
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        if (hours === 0)
            return minutes + "m";
        return hours + "h " + minutes + "m";
    }

    readonly property FileView _file: FileView {
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000") + "/focustime_state.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.data = JSON.parse(this.text());
            } catch (e) {
                // A torn read is replaced by the next heartbeat.
            }
        }
    }

    readonly property Timer _tick: Timer {
        id: tick
        interval: 2000
        running: true
        repeat: true
    }
}
