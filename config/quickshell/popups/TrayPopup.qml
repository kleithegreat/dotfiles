import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray

PanelWindow {
    id: trayPop
    property bool active: false; signal close()
    visible: active && SystemTray.items.values.length > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell:tray"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // ── Backdrop with animated dim ──
    Rectangle {
        anchors.fill: parent; color: "transparent"; focus: true
        Keys.onEscapePressed: trayPop.close()
        MouseArea { anchors.fill: parent; onClicked: trayPop.close() }
    }

    Rectangle {
        id: trayPanel
        anchors.right: parent.right; anchors.top: parent.top
        anchors.topMargin: Theme.popupTopMargin; anchors.rightMargin: Theme.gapOut + 36
        width: trayGrid.implicitWidth + Theme.barPadding * 2
        height: trayGrid.implicitHeight + Theme.barPadding * 2
        radius: Theme.popupRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
        MouseArea { anchors.fill: parent }

        // ── Popup entrance: slide down + fade from bar ──
        opacity: trayPop.active ? 1 : 0
        scale: trayPop.active ? 1.0 : 0.92
        transformOrigin: Item.Top
        y: trayPop.active ? anchors.topMargin : anchors.topMargin - 12
        Behavior on opacity { NumberAnimation { duration: Theme.animPopupIn; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.animPopupIn; easing.type: Easing.OutCubic } }

        Grid {
            id: trayGrid; anchors.centerIn: parent; columns: Math.min(4, SystemTray.items.values.length); spacing: Theme.barSpacing
            Repeater {
                model: SystemTray.items
                Item {
                    id: trayItem; required property var modelData; required property int index
                    width: Theme.iconSize + 4; height: Theme.iconSize + 4

                    Image {
                        id: trayImg; anchors.centerIn: parent
                        width: Theme.iconSize; height: Theme.iconSize
                        source: Quickshell.iconPath(trayItem.modelData.id ?? "", true) || (trayItem.modelData.icon ?? "")
                        sourceSize.width: Theme.iconSize * 2; sourceSize.height: Theme.iconSize * 2
                        smooth: true; fillMode: Image.PreserveAspectFit
                        cache: false
                        visible: status === Image.Ready
                    }

                    // Fallback: nerd font icon for known apps, then first letter
                    Text {
                        anchors.centerIn: parent; visible: !trayImg.visible
                        text: {
                            let id = (trayItem.modelData.id ?? trayItem.modelData.title ?? "").toLowerCase();
                            // Known apps with broken pixmaps — add more here
                            if (id.includes("spotify")) return "󰓇";
                            return id.length > 0 ? id.charAt(0).toUpperCase() : "?";
                        }
                        color: Theme.fg3
                        font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize; font.bold: true
                    }

                    // ── Hover effect ──
                    Rectangle {
                        anchors.fill: parent; radius: 4; z: -1
                        color: Theme.bg2
                        opacity: trayMouseArea.containsMouse ? 1 : 0
                        border.width: 1; border.color: Theme.bg3
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }

                    // ── Staggered entrance animation ──
                    opacity: 0; scale: 0.8
                    Component.onCompleted: {
                        console.log("TRAY DEBUG:", modelData.id, "icon:", modelData.icon); // TODO: remove
                        staggerAnim.delay = index * 30;
                        staggerAnim.start();
                    }
                    SequentialAnimation {
                        id: staggerAnim
                        property int delay: 0
                        PauseAnimation { duration: staggerAnim.delay }
                        ParallelAnimation {
                            NumberAnimation { target: trayItem; property: "opacity"; to: 1; duration: 200; easing.type: Easing.OutCubic }
                            NumberAnimation { target: trayItem; property: "scale"; to: 1.0; duration: 250; easing.type: Easing.OutBack }
                        }
                    }

                    MouseArea {
                        id: trayMouseArea
                        anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.LeftButton) trayItem.modelData.activate();
                            else trayItem.modelData.secondaryActivate();
                        }
                    }
                }
            }
        }
    }
}
