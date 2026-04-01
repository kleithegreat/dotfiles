import qs
import QtQuick

Item {
    id: trayExpand
    implicitWidth: chevText.implicitWidth + 4; implicitHeight: chevText.implicitHeight
    signal clicked()

    Text {
        id: chevText; anchors.centerIn: parent; text: "󰅃"
        color: chevArea.containsMouse ? Theme.yellowBright : Theme.fg4
        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
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
