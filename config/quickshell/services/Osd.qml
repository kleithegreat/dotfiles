pragma Singleton

import QtQuick

// The on-screen level indicator. It is one shared surface, so it is one service:
// the old shell hung it off the audio service and then had brightness reach in
// sideways to drive it, which is why the two could fight over it.
QtObject {
    id: root

    property bool showing: false
    property string icon: ""
    property string label: ""
    property real value: 0

    // Held while a gesture drives the underlying value itself — dragging the
    // volume slider must not summon the OSD on top of the slider.
    property bool suppressed: false

    function show(iconName, fraction, text) {
        if (suppressed)
            return;

        icon = iconName;
        value = Math.max(0, Math.min(1, fraction));
        label = text;
        showing = true;
        _hide.restart();
    }

    // Suppress for the duration of `fn` plus the change callbacks it triggers.
    function without(fn) {
        suppressed = true;
        fn();
        Qt.callLater(() => root.suppressed = false);
    }

    readonly property Timer _hide: Timer {
        interval: 1500
        onTriggered: root.showing = false
    }
}
