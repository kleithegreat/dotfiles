import qs
import QtQuick
import "../components" as Components

Item {
    id: powerRoot; implicitWidth: powerIcon.implicitWidth + 2; implicitHeight: powerIcon.implicitHeight; signal clicked()
    Components.Icon {
        id: powerIcon; anchors.centerIn: parent; source: "../icons/power.svg"
        color: powerArea.containsMouse ? Theme.redBright : Theme.fg
    }
    Components.BarTooltipArea {
        id: powerArea; tip: "Power / Session"
        onClicked: powerRoot.clicked()
    }
}
