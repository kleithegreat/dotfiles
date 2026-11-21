pragma Singleton

import QtQuick

// Pushed by the daemon over the focus topic.
QtObject {
    id: root

    property var data: ({})

    readonly property int today: data.total || 0
    readonly property int average: data.average || 0
    readonly property int yesterday: data.yesterday || 0
    readonly property string weekRange: data.week_range || ""
    readonly property var apps: data.apps || []
    readonly property var week: data.week || []

    readonly property bool stale: !Desktopctl.ready || (data.last_updated || 0) === 0

    function format(seconds) {
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        if (hours === 0)
            return minutes + "m";
        return hours + "h " + minutes + "m";
    }

    readonly property Connections _events: Connections {
        target: Desktopctl
        function onFocusChanged(summary) {
            root.data = summary;
        }
    }
}
