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
QtObject {
    id: root

    property var monitors: []
    readonly property bool applying: applyGate.running

    signal applied(bool ok)

    function refresh() {
        if (!enumerate.running)
            enumerate.running = true;
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

    Component.onCompleted: refresh()

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
