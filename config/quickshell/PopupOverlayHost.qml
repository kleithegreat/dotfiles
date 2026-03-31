import qs
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.popups as Popups
import "components" as Components

PanelWindow {
    id: overlayHost
    required property QtObject popupVisibility

    function popupList() {
        return [
            powerMenu,
            drawer,
            calendarPopup,
            trayPopup,
            mprisPopup,
            quickSettingsPopup,
            settingsPopup
        ];
    }

    function firstActivePopup() {
        let popups = popupList();
        for (let i = 0; i < popups.length; i++) {
            if (popups[i].active && popups[i].overlayVisible)
                return popups[i];
        }

        return null;
    }

    function firstVisiblePopup() {
        let popups = popupList();
        for (let i = 0; i < popups.length; i++) {
            if (popups[i].overlayVisible)
                return popups[i];
        }

        return null;
    }

    function firstScrimPopup() {
        let activePopup = firstActivePopup();
        if (activePopup)
            return activePopup.scrimEnabled ? activePopup : null;

        let popups = popupList();
        for (let i = 0; i < popups.length; i++) {
            if (popups[i].overlayVisible && popups[i].scrimEnabled)
                return popups[i];
        }

        return null;
    }

    function dismissAll() {
        if (overlayHost.popupVisibility)
            overlayHost.popupVisibility.closeAll();
    }

    readonly property var primaryPopup: {
        let popup = firstActivePopup();
        return popup ? popup : firstVisiblePopup();
    }
    readonly property var scrimPopup: firstScrimPopup()
    readonly property bool overlayVisible: primaryPopup !== null
    readonly property bool scrimVisible: scrimPopup !== null
    readonly property color scrimColor: scrimPopup ? scrimPopup.scrimColor : "transparent"
    readonly property real scrimTargetOpacity: scrimPopup ? scrimPopup.scrimOpacity : 0

    visible: overlayVisible
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell:popup-overlay"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: overlayVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // The overlay captures the whole screen while any popup is open so the host
    // can provide a single, reliable click-outside-to-dismiss path.
    mask: Region {
        width: overlayHost.overlayVisible ? overlayHost.width : 0
        height: overlayHost.overlayVisible ? overlayHost.height : 0
    }

    HyprlandFocusGrab {
        id: overlayGrab
        active: overlayHost.overlayVisible
        windows: overlayHost.overlayVisible ? [overlayHost] : []
        onCleared: overlayHost.dismissAll()
    }

    MouseArea {
        anchors.fill: parent
        enabled: overlayHost.overlayVisible && !overlayHost.scrimVisible
        acceptedButtons: Qt.AllButtons
        onPressed: overlayHost.dismissAll()
    }

    Rectangle {
        anchors.fill: parent
        color: overlayHost.scrimColor
        opacity: overlayHost.scrimTargetOpacity
        visible: opacity > 0.001
        Behavior on opacity {
            Components.Anim {
                duration: overlayHost.scrimVisible ? Theme.animPopupIn : Theme.animPopupOut
                easing.type: Easing.BezierSpline
                easing.bezierCurve: overlayHost.scrimVisible ? Theme.animCurveEmphasizedEnter : Theme.animCurveExit
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: overlayHost.scrimVisible
            acceptedButtons: Qt.AllButtons
            onPressed: overlayHost.dismissAll()
        }
    }

    Popups.CalendarPopup {
        id: calendarPopup
        anchors.fill: parent
        z: active ? 2 : (overlayVisible ? 1 : 0)
        active: overlayHost.popupVisibility.calendarVisible
        onClose: overlayHost.popupVisibility.calendarVisible = false
    }

    Popups.TrayPopup {
        id: trayPopup
        anchors.fill: parent
        z: active ? 2 : (overlayVisible ? 1 : 0)
        active: overlayHost.popupVisibility.trayVisible
        onClose: overlayHost.popupVisibility.trayVisible = false
    }

    Popups.MprisPopup {
        id: mprisPopup
        anchors.fill: parent
        z: active ? 2 : (overlayVisible ? 1 : 0)
        active: overlayHost.popupVisibility.mprisVisible
        onClose: overlayHost.popupVisibility.mprisVisible = false
    }

    Popups.SettingsPopup {
        id: settingsPopup
        anchors.fill: parent
        z: active ? 2 : (overlayVisible ? 1 : 0)
        active: overlayHost.popupVisibility.settingsVisible
        onClose: overlayHost.popupVisibility.settingsVisible = false
    }

    Popups.QuickSettingsPopup {
        id: quickSettingsPopup
        anchors.fill: parent
        z: active ? 2 : (overlayVisible ? 1 : 0)
        active: overlayHost.popupVisibility.quickSettingsVisible
        onClose: overlayHost.popupVisibility.quickSettingsVisible = false
        onSettingsRequested: overlayHost.popupVisibility.toggleSettings()
    }

    NotifDrawer {
        id: drawer
        anchors.fill: parent
        z: active ? 2 : (overlayVisible ? 1 : 0)
        active: overlayHost.popupVisibility.drawerVisible
        onClose: overlayHost.popupVisibility.drawerVisible = false
    }

    PowerMenu {
        id: powerMenu
        anchors.fill: parent
        z: active ? 2 : (overlayVisible ? 1 : 0)
        active: overlayHost.popupVisibility.powerMenuVisible
        onClose: overlayHost.popupVisibility.powerMenuVisible = false
    }
}
