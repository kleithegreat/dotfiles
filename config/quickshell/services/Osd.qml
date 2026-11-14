pragma Singleton

import QtQuick

// The on-screen level indicator. One shared surface, so one service.
QtObject {
    id: root

    property bool showing: false
    property string icon: ""
    property string label: ""
    // null for a message with no level, such as a keyboard mode.
    property var value: 0

    function show(iconName, fraction, text) {
        icon = iconName;
        value = fraction === null ? null : Math.max(0, Math.min(1, fraction));
        label = text;
        showing = true;
        _hide.restart();
    }

    readonly property Timer _hide: Timer {
        interval: 1500
        onTriggered: root.showing = false
    }
}
