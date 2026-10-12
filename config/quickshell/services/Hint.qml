pragma Singleton

import QtQuick

// The bar's hover hint. One shared surface, so one service: the text and the
// point it belongs to, with the dwell that decides whether the pointer was
// asking a question or just passing through.
QtObject {
    id: root

    property string text: ""
    property real anchor: 0
    property bool showing: false

    function request(message, at) {
        if (message === "") {
            clear();
            return;
        }

        // Raising `showing` before the new target is what makes the bubble travel rather than jump.
        if (showing || grace.running) {
            grace.stop();
            showing = true;
        } else {
            dwell.restart();
        }

        text = message;
        anchor = at;
    }

    function clear() {
        dwell.stop();
        if (showing)
            grace.restart();
        showing = false;
    }

    readonly property Timer _dwell: Timer {
        id: dwell
        interval: 450
        onTriggered: root.showing = true
    }

    // How long after a hint leaves the next item still counts as the same
    // question rather than a new one.
    readonly property Timer _grace: Timer {
        id: grace
        interval: 350
    }
}
