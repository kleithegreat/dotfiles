import QtQuick

// Which surface is showing, and where it came from. One name: exclusivity is structural.
QtObject {
    id: root

    // "" · control · calendar · media · notifications · session · settings · menu
    property string current: ""
    // The DBus menu handle a tray item asked us to show.
    property var menu: null
    // Screen x of the control that opened it, so the surface can grow from there.
    property real anchor: 0
    // Where each surface's bar control sits, for surfaces opened from a keybind.
    property var origins: ({})
    property string pane: "Network"

    readonly property bool open_: current !== ""

    function open(name, anchorX) {
        if (current === name) {
            close();
            return;
        }
        const at = anchorX !== undefined ? anchorX : origins[name];
        if (at !== undefined)
            anchor = at;
        current = name;
    }

    function setOrigin(name, at) {
        if (origins[name] === at)
            return;
        const next = Object.assign({}, origins);
        next[name] = at;
        origins = next;
    }

    function close() {
        current = "";
        menu = null;
    }

    function openMenu(handle, anchorX) {
        menu = handle;
        open("menu", anchorX);
    }

    function showSettings(paneName) {
        if (paneName !== undefined)
            pane = paneName;
        current = "settings";
    }

    function isOpen(name) {
        return current === name;
    }
}
