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
        width: trayGrid.implicitWidth + Theme.popupPadding * 2
        height: trayGrid.implicitHeight + Theme.popupPadding * 2
        radius: Theme.popupRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
        MouseArea { anchors.fill: parent }

        // ── Popup entrance: slide down + fade from bar ──
        opacity: trayPop.active ? 1 : 0
        scale: trayPop.active ? 1.0 : 0.96
        transformOrigin: Item.Top
        y: trayPop.active ? anchors.topMargin : anchors.topMargin - 12
        Behavior on opacity { NumberAnimation { duration: Theme.animPopupIn; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.animPopupIn; easing.type: Easing.OutBack; easing.overshoot: 0.5 } }

        Grid {
            id: trayGrid; anchors.centerIn: parent; columns: 4; spacing: 10
            Repeater {
                model: SystemTray.items
                Item {
                    id: trayItem; required property var modelData; required property int index
                    width: 32; height: 32

                    Image {
                        id: trayImg; anchors.fill: parent; anchors.margins: 2
                        source: trayItem.modelData.icon ?? ""
                        sourceSize.width: 28; sourceSize.height: 28; smooth: true
                        visible: status === Image.Ready
                    }

                    // Fallback: show first letter of app id in a styled circle
                    Rectangle {
                        anchors.centerIn: parent; visible: trayImg.status !== Image.Ready
                        width: 24; height: 24; radius: 12
                        color: Theme.bg2; border.width: 1; border.color: Theme.bg3
                        Text {
                            anchors.centerIn: parent
                            text: {
                                let id = trayItem.modelData.id ?? trayItem.modelData.title ?? "";
                                return id.length > 0 ? id.charAt(0).toUpperCase() : "?";
                            }
                            color: Theme.fg3
                            font.family: Theme.fontFamily; font.pixelSize: 11; font.bold: true
                        }
                    }

                    // ── Hover effect: subtle lift + glow ──
                    Rectangle {
                        anchors.fill: parent; radius: 6
                        color: trayMouseArea.containsMouse ? Theme.bg2 : "transparent"
                        border.width: trayMouseArea.containsMouse ? 1 : 0
                        border.color: Theme.bg3
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    // ── Staggered entrance animation ──
                    opacity: 0; scale: 0.8
                    Component.onCompleted: {
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
