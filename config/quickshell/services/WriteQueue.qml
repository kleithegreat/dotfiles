import QtQuick
import Quickshell.Io

// The one serialised `desktopctl` write queue ([[quickshell]]).
QtObject {
    id: root

    property string failureText: "Change failed"
    property var staged: ({})
    readonly property bool busy: writer.running || _queue.length > 0

    property var _queue: []

    signal settled(string key, bool ok)

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
            const hasNewer = job && job.key !== undefined && root._queue.some(item => item.key === job.key);

            if (job && job.key !== undefined && !hasNewer) {
                const next = Object.assign({}, root.staged);
                delete next[job.key];
                root.staged = next;
            }
            if (code !== 0)
                Toast.failure(failure.text, root.failureText);
            if (job)
                root.settled(job.key !== undefined ? String(job.key) : "", code === 0);

            Qt.callLater(root._pump);
        }
    }
}
