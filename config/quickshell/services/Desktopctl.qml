pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Read side of the daemon link: subscribed socket in, `desktopctl` commands
// out ([[quickshell]]).
QtObject {
    id: root

    readonly property bool ready: socket.connected

    signal themeChanged(var state, var changedKeys)
    signal presetsChanged(var presets)
    signal nightLightChanged(var status)
    signal brightnessChanged(var payload)
    signal inputChanged(var state)
    signal monitorsChanged(var status)

    property int _retryMs: 500

    function _dispatch(line) {
        const text = String(line).trim();
        if (text === "")
            return;

        let message;
        try {
            message = JSON.parse(text);
        } catch (e) {
            return;
        }

        // Replies carry `ok`; only pushed events carry `event`.
        if (message.event === undefined)
            return;

        const data = message.data || {};
        switch (message.event) {
        case "theme.changed":
            themeChanged(data.state || {}, data.changed_keys || []);
            break;
        case "theme.presets_changed":
            presetsChanged(data.presets || []);
            break;
        case "night_light.changed":
            nightLightChanged(data);
            break;
        case "brightness.changed":
            brightnessChanged(data);
            break;
        case "hypr_input.changed":
            inputChanged(data);
            break;
        case "hypr_monitors.changed":
            monitorsChanged(data);
            break;
        }
    }

    readonly property Socket _socket: Socket {
        id: socket
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/desktopctl.sock"
        connected: true
        parser: SplitParser {
            onRead: data => root._dispatch(data)
        }
        onConnectionStateChanged: {
            if (connected) {
                root._retryMs = 500;
                write(JSON.stringify({ method: "subscribe" }) + "\n");
                flush();
            } else {
                retry.interval = root._retryMs;
                root._retryMs = Math.min(root._retryMs * 2, 5000);
                retry.restart();
            }
        }
    }

    readonly property Timer _retry: Timer {
        id: retry
        interval: 500
        onTriggered: {
            if (!socket.connected)
                socket.connected = true;
        }
    }
}
