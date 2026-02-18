import qs
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

RowLayout {
    spacing: 4
    Repeater {
        model: 10
        Item {
            id: wsItem
            required property int index
            property int wsId: index + 1
            property var ws: Hyprland.workspaces.values.find(w => w.id === wsId)
            property bool isActive: Hyprland.focusedWorkspace?.id === wsId
            property bool hasWindows: {
                if (ws === undefined || ws === null) return false;
                if (typeof ws.windows === "number") return ws.windows > 0;
                return true;
            }
            Layout.preferredWidth: pill.width
            Layout.preferredHeight: pill.height
            Rectangle {
                id: pill
                anchors.centerIn: parent
                width: isActive ? 20 : (hasWindows ? 12 : 8)
                height: 8; radius: 4
                color: {
                    if (wsItem.isActive) return Theme.blueBright;
                    if (wsArea.containsMouse) return Theme.fg3;
                    if (wsItem.hasWindows) return Theme.fg4;
                    return Theme.bg3;
                }
                Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                Behavior on color { ColorAnimation { duration: 150 } }
            }
            MouseArea {
                id: wsArea; anchors.fill: parent
                cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                onClicked: Hyprland.dispatch("workspace " + wsItem.wsId)
            }
        }
    }
}
