pragma Singleton

import QtQuick
import Quickshell

QtObject {
    id: root

    readonly property bool inhibited: idle.active
    readonly property bool lidInhibited: lid.active

    readonly property bool _bootDefault: {
        const raw = Quickshell.env("DESKTOPCTL_IDLE_INHIBIT_DEFAULT");
        if (raw === null || raw === undefined)
            return false;
        const value = String(raw).trim().toLowerCase();
        return value === "1" || value === "true" || value === "yes" || value === "on";
    }

    function toggle() {
        idle.toggle();
    }

    function toggleLid() {
        lid.toggle();
    }

    function set(enabled) {
        idle.set(enabled);
    }

    function applyBootDefault() {
        if (_bootDefault)
            idle.set(true);
    }

    readonly property Inhibitor _idle: Inhibitor {
        id: idle
        what: "idle"
        why: "Idle inhibited from the shell"
    }

    readonly property Inhibitor _lid: Inhibitor {
        id: lid
        what: "handle-lid-switch"
        why: "Lid switch inhibited from the shell"
    }
}
