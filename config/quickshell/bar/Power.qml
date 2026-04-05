import qs
import QtQuick
import "../components" as Components

Item {
    id: powerRoot; implicitWidth: powerIcon.implicitWidth + 2; implicitHeight: powerIcon.implicitHeight; signal clicked()
    Components.Icon {
        id: powerIcon; anchors.centerIn: parent; source: "../icons/power.svg"
        color: powerArea.containsMouse ? Theme.redBright : Theme.fg
    }
    MouseArea {
        id: powerArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
        onClicked: powerRoot.clicked()
        onContainsMouseChanged: {
            if (containsMouse) {
                let p = powerRoot.mapToGlobal(Qt.point(powerRoot.width / 2, powerRoot.height));
                TooltipService.show("Power / Session", p.x, p.y);
            } else {
                TooltipService.hide();
            }
        }
    }
}
