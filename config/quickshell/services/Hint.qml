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

        text = message;
        anchor = at;
        // Once one hint has been earned, moving along the bar shows the rest
        // immediately; making every neighbour re-earn the dwell is what makes a
        // bar feel unresponsive.
        if (showing)
            return;
        dwell.restart();
    }

    function clear() {
        dwell.stop();
        showing = false;
        linger.restart();
    }

    readonly property Timer _dwell: Timer {
        id: dwell
        interval: 450
        onTriggered: root.showing = true
    }

    readonly property Timer _linger: Timer {
        id: linger
        interval: 350
    }
}
