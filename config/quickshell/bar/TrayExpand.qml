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
    Components.BarTooltipArea {
        id: chevArea; tip: "System tray"
        onClicked: trayExpand.clicked()
    }
}
