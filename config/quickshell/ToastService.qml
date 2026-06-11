pragma Singleton
import QtQuick
import "." as Root

QtObject {
    id: root

    // ── Public properties for UI binding ──
    property string currentMessage: ""
    property string currentLevel: ""
    property bool toastVisible: false

    // ── Internal state ──
    property var _queue: []
    property var _lastErrorTimes: ({})

    readonly property int _maxQueueDepth: 3
    readonly property var _durations: ({
        "info": 2000,
        "warning": 3500,
        "error": 5000
    })

    // ── Public API ──
    function showToast(message, level) {
        if (!message)
            return;

        if (level !== "info" && level !== "warning" && level !== "error")
            level = "info";

        // Error throttling: same error cannot reappear within 1 s
        if (level === "error") {
            let now = Date.now();
            let lastTime = _lastErrorTimes[message];
            if (lastTime !== undefined && now - lastTime < 1000)
                return;
            // Prune entries past the throttle window so the map stays bounded.
            let next = {};
            for (let key in _lastErrorTimes) {
                if (now - _lastErrorTimes[key] < 1000)
                    next[key] = _lastErrorTimes[key];
            }
            next[message] = now;
            _lastErrorTimes = next;
        }

        // Duplicate suppression: skip if already displayed or queued
        if (toastVisible && currentMessage === message && currentLevel === level)
            return;
        for (let i = 0; i < _queue.length; i++) {
            if (_queue[i].message === message && _queue[i].level === level)
                return;
        }

        if (toastVisible) {
            if (_queue.length >= _maxQueueDepth)
                _queue.shift();
            _queue.push({ message: message, level: level, timestamp: Date.now() });
            _queue = _queue;
        } else {
            _showImmediate(message, level);
        }
    }

    function showInfo(msg)    { showToast(msg, "info"); }
    function showWarning(msg) { showToast(msg, "warning"); }
    function showError(msg)   { showToast(msg, "error"); }

    function hideToast() {
        toastVisible = false;
        _dismissTimer.stop();
        _advanceTimer.restart();
    }

    // ── Internal helpers ──
    function _showImmediate(message, level) {
        currentMessage = message;
        currentLevel = level;
        toastVisible = true;
        _dismissTimer.interval = _durations[level] || 2000;
        _dismissTimer.restart();
    }

    function _advance() {
        if (_queue.length === 0)
            return;

        let next = _queue.shift();
        _queue = _queue;
        _showImmediate(next.message, next.level);
    }

    property Timer _dismissTimer: Timer {
        repeat: false
        onTriggered: root.hideToast()
    }

    // Brief pause between toasts so the exit animation can finish
    property Timer _advanceTimer: Timer {
        interval: Root.Theme.animOsdOut + 50
        repeat: false
        onTriggered: root._advance()
    }
}
