import qs
import QtQuick

Item {
    id: powerRoot; implicitWidth: powerText.implicitWidth + 2; implicitHeight: powerText.implicitHeight; signal clicked()
    Text {
        id: powerText; anchors.centerIn: parent; text: "󰐥"
        color: powerArea.containsMouse ? Theme.redBright : Theme.fg
        font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
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
