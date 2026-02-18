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

    Rectangle {
        anchors.fill: parent; color: "transparent"; focus: true
        Keys.onEscapePressed: trayPop.close()
        MouseArea { anchors.fill: parent; onClicked: trayPop.close() }
    }

    Rectangle {
        anchors.right: parent.right; anchors.top: parent.top
        anchors.topMargin: Theme.popupTopMargin; anchors.rightMargin: Theme.gapOut + 36
        width: trayGrid.implicitWidth + Theme.popupPadding * 2
        height: trayGrid.implicitHeight + Theme.popupPadding * 2
        radius: Theme.popupRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
        MouseArea { anchors.fill: parent }

        Grid {
            id: trayGrid; anchors.centerIn: parent; columns: 4; spacing: 10
            Repeater {
                model: SystemTray.items
                Item {
                    id: trayItem; required property var modelData
                    width: 28; height: 28

                    // Use iconPath with check=true to avoid purple/black square
                    Image {
                        id: trayImg; anchors.fill: parent
                        source: {
                            let iconName = trayItem.modelData.icon ?? "";
                            if (iconName === "") return "";
                            // Quickshell.iconPath with check returns "" for missing icons
                            let path = Quickshell.iconPath(iconName, true);
                            return path || "";
                        }
                        sourceSize.width: 24; sourceSize.height: 24; smooth: true
                        visible: status === Image.Ready
                    }
                    // Fallback generic icon
                    Text {
                        anchors.centerIn: parent; visible: trayImg.status !== Image.Ready
                        text: "󰘔"; color: Theme.fg3
                        font.family: Theme.fontFamily; font.pixelSize: 18
                    }

                    MouseArea {
                        anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
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
