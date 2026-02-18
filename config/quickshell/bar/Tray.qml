import qs
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray

RowLayout {
    spacing: 6

    Repeater {
        model: SystemTray.items

        Image {
            id: trayIcon
            required property var modelData

            source: modelData.icon ?? ""
            sourceSize.width: Theme.iconSize + 2
            sourceSize.height: Theme.iconSize + 2
            smooth: true

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (mouse) => {
                    if (mouse.button === Qt.LeftButton) {
                        trayIcon.modelData.activate();
                    } else {
                        trayIcon.modelData.secondaryActivate();
                    }
                }
            }
        }
    }
}
