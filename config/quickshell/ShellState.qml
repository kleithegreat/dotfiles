import QtQuick

// Which surface is showing, and where it came from.
//
// Exclusivity is structural: one name can only hold one value, so "at most one
// surface is open" needs no coordinator. The old shell kept seven independent
// booleans plus a closeAll() that had to remember all seven, plus a 100ms
// debounce to stop the resulting double-toggles.
QtObject {
    id: root

    // "" · control · calendar · media · notifications · session · settings · menu
    property string current: ""
    // The DBus menu handle a tray item asked us to show.
    property var menu: null
    // Screen x of the control that opened it, so the surface can grow from there.
    property real anchor: 0
    // Where each surface's bar control currently sits, so one opened from a
    // keybind still grows from the button it belongs to rather than from the
    // left edge of the screen.
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
