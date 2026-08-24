pragma Singleton

import QtQuick
import Quickshell.Io
import Quickshell.Hyprland

// Monitor topology and the layout writes that change it.
//
// Every risky change is staged and applied as one chunk: a half-applied layout,
// or one applied per pointer-move during a drag, can strand the session on a
// mode the display cannot show. Confirmation is the caller's job; this service
// only guarantees the write is indivisible and that failure is reported.
//
// Applying and persisting are deliberately separate. `apply` puts a layout on
// screen through the compositor gateway so the confirm countdown can take it
// straight back off again; `savePositions` records the one the user kept, and
// only that one survives a reload. The primary output is not risky in the same
// way -- nothing about it can leave you unable to see the screen -- so it is
// written straight through.
QtObject {
    id: root

    property var monitors: []
    readonly property bool applying: applyGate.running

    // The daemon's answer to "which output is primary", already resolved: the
    // stored choice when it is connected, the largest external otherwise. The
    // shell never re-derives it -- one rule, in one place.
    property string primaryOutput: ""
    // The stored selector; empty means the choice is automatic.
    property string primary: ""
    property var positions: ({})

    signal applied(bool ok)

    function refresh() {
        if (!enumerate.running)
            enumerate.running = true;
    }

    // Must agree with `selector_for` in desktopctl's displays module: a
    // description survives being replugged into a different port, a connector
    // name does not.
    function selectorFor(monitor) {
        const description = String(monitor.description || "").trim();
        return description === "" ? monitor.name : "desc:" + description;
    }

    function isPrimary(monitor) {
        return monitor.name === primaryOutput;
    }

    function setPrimary(monitor) {
        writer.command = ["desktopctl", "hypr", "monitors", "primary", monitor === null ? "" : selectorFor(monitor)];
        writer.running = true;
    }

    function savePositions(states) {
        const payload = {};
        for (let i = 0; i < states.length; i++) {
            const monitor = monitorFor(states[i].name);
            if (monitor)
                payload[selectorFor(monitor)] = states[i].x + "x" + states[i].y;
        }
        writer.command = ["desktopctl", "hypr", "monitors", "layout", JSON.stringify(payload)];
        writer.running = true;
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

    // `disabled = false` has to be spelled out: re-declaring mode, position and
    // scale on a disabled output leaves it disabled.
    function expressionFor(state) {
        const fields = ["output = " + _quote(state.name), "mode = " + _quote(state.width + "x" + state.height + "@" + Number(state.refreshRate).toFixed(2)), "position = " + _quote(state.x + "x" + state.y), "scale = " + state.scale, "disabled = false"];

        if (state.transform)
            fields.push("transform = " + state.transform);
        if (state.vrr !== undefined && state.vrr !== false && state.vrr !== 0)
            fields.push("vrr = " + (typeof state.vrr === "boolean" ? 1 : state.vrr));
        if (state.bitdepth)
            fields.push("bitdepth = " + state.bitdepth);
        if (state.mirrorOf && state.mirrorOf !== "none")
            fields.push("mirror = " + _quote(state.mirrorOf));

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
            root.applied(ok);
        });
        return true;
    }

    function _ingest(status) {
        primary = status.primary || "";
        primaryOutput = status.primary_output || "";
        positions = status.positions || ({});
    }

    Component.onCompleted: {
        refresh();
        topology.running = true;
    }

    // Pushed over the Desktopctl socket; the startup read is the degraded path
    // for a daemon that is not up yet.
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
                    // Keep the last known topology.
                }
            }
        }
    }

    readonly property Process _writer: Process {
        id: writer
        stderr: StdioCollector {
            id: failure
        }
        onExited: code => {
            if (code !== 0)
                Toast.error(failure.text.trim().split("\n").filter(line => line !== "").pop() || "Display change failed");
        }
    }

    // A plain flag rather than a Process: the write itself runs on the shared
    // compositor queue, but only one layout change may be outstanding.
    readonly property QtObject _gate: QtObject {
        id: applyGate
        property bool running: false
    }

    readonly property Process _enumerate: Process {
        id: enumerate
        // `all` so disabled outputs stay visible to the settings pane; the
        // default listing silently omits them, which reads as a lost monitor.
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.monitors = JSON.parse(this.text);
                } catch (e) {
                    // A torn read is retried by the next refresh.
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
