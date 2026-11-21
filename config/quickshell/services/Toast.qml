pragma Singleton

import QtQuick

// One message at a time, the rest queued, so a retry loop cannot flood the screen.
QtObject {
    id: root

    property string message: ""
    property string level: "info"
    property bool showing: false

    property var _queue: []
    property var _recent: ({})

    readonly property var _dwell: ({ "info": 2200, "warning": 3600, "error": 5000 })
    readonly property int _maxQueued: 3
    readonly property int _repeatWindow: 1000

    function warning(text) {
        show(text, "warning");
    }
    function error(text) {
        show(text, "error");
    }

    function failure(stderr, fallback) {
        error(stderr.trim().split("\n").filter(line => line.trim() !== "").pop() || fallback);
    }

    function show(text, kind) {
        if (!text)
            return;
        if (kind !== "warning" && kind !== "error")
            kind = "info";

        const now = Date.now();
        const key = kind + "\u0000" + text;
        const pruned = {};
        for (const seen in _recent) {
            if (now - _recent[seen] < _repeatWindow)
                pruned[seen] = _recent[seen];
        }
        if (pruned[key] !== undefined) {
            _recent = pruned;
            return;
        }
        pruned[key] = now;
        _recent = pruned;

        if (showing && message === text && level === kind)
            return;
        for (let i = 0; i < _queue.length; i++) {
            if (_queue[i].text === text && _queue[i].kind === kind)
                return;
        }

        if (!showing) {
            _present(text, kind);
            return;
        }

        const queued = _queue.slice(_queue.length >= _maxQueued ? 1 : 0);
        queued.push({ text: text, kind: kind });
        _queue = queued;
    }

    function dismiss() {
        showing = false;
        _dwellTimer.stop();
        _gapTimer.restart();
    }

    function _present(text, kind) {
        message = text;
        level = kind;
        showing = true;
        _dwellTimer.interval = _dwell[kind];
        _dwellTimer.restart();
    }

    readonly property Timer _dwellTimer: Timer {
        onTriggered: root.dismiss()
    }

    // Let the outgoing toast finish leaving before the next one arrives.
    readonly property Timer _gapTimer: Timer {
        interval: Motion.quick + 20
        onTriggered: {
            if (root._queue.length === 0)
                return;
            const next = root._queue[0];
            root._queue = root._queue.slice(1);
            root._present(next.text, next.kind);
        }
    }
}
