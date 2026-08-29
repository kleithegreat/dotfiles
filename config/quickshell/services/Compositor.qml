pragma Singleton

import QtQuick
import Quickshell.Io
import Quickshell.Hyprland

// The single gateway to hyprctl: it exits 0 on failure and `keyword` is inert
// under the Lua parser, so both rules live here once ([[hyprland]]).
QtObject {
    id: root

    // Whether the compositor is actually blurring. Reported in settings; no
    // surface's material depends on it.
    property bool blurEnabled: false

    property var _queue: []

    // Run a Lua expression. `done(ok, output)` fires on real completion.
    function run(expression, done) {
        _queue = _queue.concat([{ expression: expression, done: done || null }]);
        _pump();
    }

    // Apply several statements as one indivisible chunk, so a half-applied
    // layout can never be observed.
    function runAll(expressions, done) {
        if (expressions.length === 0)
            return;
        run("do " + expressions.join(" ") + " end", done);
    }

    function _pump() {
        if (evaluator.running || _queue.length === 0)
            return;

        evaluator.command = ["hyprctl", "eval", _queue[0].expression];
        evaluator.running = true;
    }

    function _settle(output) {
        const job = _queue[0];
        _queue = _queue.slice(1);

        const failed = /(^|\n)\s*error:/i.test(output);
        if (job && job.done)
            job.done(!failed, output);
        else if (failed)
            Toast.error(output.trim().split("\n")[0]);

        Qt.callLater(root._pump);
    }

    function refresh() {
        if (!blurProbe.running)
            blurProbe.running = true;
    }

    Component.onCompleted: refresh()

    readonly property Process _evaluator: Process {
        id: evaluator
        stdout: StdioCollector {
            onStreamFinished: root._settle(this.text)
        }
    }

    readonly property Process _blurProbe: Process {
        id: blurProbe
        command: ["hyprctl", "getoption", "decoration:blur:enabled"]
        stdout: StdioCollector {
            onStreamFinished: root.blurEnabled = /bool:\s*true/.test(this.text)
        }
    }

    readonly property Connections _events: Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "configreloaded")
                root.refresh();
        }
    }
}
