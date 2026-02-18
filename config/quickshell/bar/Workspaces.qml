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
            property bool hasWindows: ws !== undefined && ws !== null

            Layout.preferredWidth: pill.width
            Layout.preferredHeight: pill.height

            Rectangle {
                id: pill
                anchors.centerIn: parent
                width: isActive ? 20 : (hasWindows ? 12 : 8)
                height: 8
                radius: 4
                color: isActive ? Theme.blueBright : Theme.bg3

                Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Hyprland.dispatch("workspace " + wsItem.wsId)
            }
        }
    }
}
