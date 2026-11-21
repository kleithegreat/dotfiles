pragma Singleton

import QtQuick
import Quickshell.Io
import Quickshell.Hyprland

// Monitor topology and the layout writes that change it ([[quickshell]]).
QtObject {
    id: root

    property var monitors: []
    readonly property bool applying: applyGate.running

    // Resolved by the daemon, never re-derived here ([[desktopctl]]).
    property string primaryOutput: ""
    // The stored selector; empty means the choice is automatic.
    property string primary: ""

    function refresh() {
        if (!enumerate.running)
            enumerate.running = true;
    }

    // Must agree with `selector_for` in desktopctl's displays.rs.
    function selectorFor(monitor) {
        const description = String(monitor.description || "").trim();
        return description === "" ? monitor.name : "desc:" + description;
    }

    function isPrimary(monitor) {
        return monitor.name === primaryOutput;
    }

    function setPrimary(monitor) {
        _writes.run(["desktopctl", "hypr", "monitors", "primary", monitor === null ? "" : selectorFor(monitor)]);
    }

    // Every field of every output: a partial spec resets on reload ([[hyprland]]).
    function saveLayout(states) {
        const payload = {};
        for (let i = 0; i < states.length; i++) {
            const state = states[i];
            const monitor = monitorFor(state.name);
            if (!monitor)
                continue;
            payload[selectorFor(monitor)] = {
                mode: state.width + "x" + state.height + "@" + Number(state.refreshRate).toFixed(2),
                position: state.x + "x" + state.y,
                scale: state.scale,
                vrr: state.vrr ? 1 : 0,
                transform: state.transform || 0,
                disabled: state.disabled ? true : false
            };
        }
        _writes.run(["desktopctl", "hypr", "monitors", "layout", JSON.stringify(payload)]);
    }

    function monitorFor(name) {
        for (let i = 0; i < monitors.length; i++) {
            if (monitors[i].name === name)
                return monitors[i];
        }
        return null;
    }

    readonly property bool internalPanelActive: {
        for (let i = 0; i < monitors.length; i++) {
            const monitor = monitors[i];
            if (!monitor.disabled && /^(eDP|LVDS|DSI)(-|$)/.test(monitor.name || ""))
                return true;
        }
        return false;
    }

    function _quote(value) {
        return '"' + String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
    }

    // `disabled = false` must be explicit to re-enable an output ([[hyprland]]).
    function expressionFor(state) {
        const vrrValue = state.vrr ? (typeof state.vrr === "number" ? state.vrr : 1) : 0;
        const fields = [
            "output = " + _quote(state.name),
            "mode = " + _quote(state.width + "x" + state.height + "@" + Number(state.refreshRate).toFixed(2)),
            "position = " + _quote(state.x + "x" + state.y),
            "scale = " + state.scale,
            "transform = " + (state.transform || 0),
            "vrr = " + vrrValue,
            "disabled = false"
        ];

        return "hl.monitor({ " + fields.join(", ") + " })";
    }

    function disableExpression(name) {
        return "hl.monitor({ output = " + _quote(name) + ", disabled = true })";
    }

    function apply(states) {
        if (applyGate.running || !states || states.length === 0)
            return false;

        const expressions = [];
        for (let i = 0; i < states.length; i++)
            expressions.push(states[i].disabled ? disableExpression(states[i].name) : expressionFor(states[i]));

        applyGate.running = true;
        Compositor.runAll(expressions, ok => {
            applyGate.running = false;
            if (!ok)
                Toast.error("Display change failed");
            root.refresh();
        });
        return true;
    }

    function _ingest(status) {
        primary = status.primary || "";
        primaryOutput = status.primary_output || "";
    }

    Component.onCompleted: {
        refresh();
        topology.running = true;
    }

    readonly property Connections _daemonEvents: Connections {
        target: Desktopctl
        function onMonitorsChanged(status) {
            root._ingest(status);
            root.refresh();
        }
    }

    readonly property Process _topology: Process {
        id: topology
        command: ["desktopctl", "hypr", "monitors", "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root._ingest(JSON.parse(this.text));
                } catch (e) {
                }
            }
        }
    }

    readonly property WriteQueue _writes: WriteQueue {
        failureText: "Display change failed"
    }

    // Only one layout change may be outstanding.
    readonly property QtObject _gate: QtObject {
        id: applyGate
        property bool running: false
    }

    readonly property Process _enumerate: Process {
        id: enumerate
        // `all`, or disabled outputs vanish from the settings pane.
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.monitors = JSON.parse(this.text);
                } catch (e) {
                }
            }
        }
    }

    readonly property Connections _events: Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "monitoradded" || event.name === "monitorremoved") {
                Hyprland.refreshMonitors();
                root.refresh();
                Brightness.refresh();
            }
        }
    }
}
