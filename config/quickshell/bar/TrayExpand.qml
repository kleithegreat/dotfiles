import qs
import QtQuick
import "../components" as Components

Item {
    id: trayExpand
    implicitWidth: chevIcon.implicitWidth + 4; implicitHeight: chevIcon.implicitHeight
    signal clicked()

    Components.Icon {
        id: chevIcon; anchors.centerIn: parent; source: "../icons/chevron-up.svg"
        color: chevArea.containsMouse ? Theme.yellowBright : Theme.fg4
        iconSize: Theme.fontSizeSmall
    }
    MouseArea {
        id: chevArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
        onClicked: trayExpand.clicked()
        onContainsMouseChanged: {
            if (containsMouse) {
                let p = trayExpand.mapToGlobal(Qt.point(trayExpand.width / 2, trayExpand.height));
                TooltipService.show("System tray", p.x, p.y);
            } else {
                TooltipService.hide();
            }
        }
    }
}
