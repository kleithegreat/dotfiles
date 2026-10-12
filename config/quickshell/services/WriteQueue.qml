import QtQuick
import Quickshell.Io

// One serialised queue of `desktopctl` writes. A keyed write is staged
// optimistically, dropped once the backend's state agrees, and rolled back
// with a toast when the command fails; see [[quickshell]].
QtObject {
    id: root

    property string failureText: "Change failed"
    property var staged: ({})

    property var _queue: []

    function value(key, current) {
        return staged[key] !== undefined ? staged[key] : current;
    }

    function set(key, next, argv) {
        const pending = Object.assign({}, staged);
        pending[key] = next;
        staged = pending;

        run(argv, key);
    }

    function run(argv, key) {
        _queue = _queue.concat([{ argv: argv, key: key }]);
        _pump();
    }

    // Not a wholesale clear: that would discard optimism for writes still queued.
    function settle(state) {
        const remaining = {};
        for (const key in staged) {
            if (state[key] !== staged[key])
                remaining[key] = staged[key];
        }
        staged = remaining;
    }

    function _pump() {
        if (writer.running || _queue.length === 0)
            return;
        writer.command = _queue[0].argv;
        writer.running = true;
    }

    readonly property Process _writer: Process {
        id: writer
        stderr: StdioCollector {
            id: failure
        }
        onExited: code => {
            const job = root._queue[0];
            root._queue = root._queue.slice(1);

            if (code !== 0) {
                if (job.key !== undefined) {
                    const reverted = Object.assign({}, root.staged);
                    delete reverted[job.key];
                    root.staged = reverted;
                }
                Toast.failure(failure.text, root.failureText);
            }

            Qt.callLater(root._pump);
        }
    }
}
