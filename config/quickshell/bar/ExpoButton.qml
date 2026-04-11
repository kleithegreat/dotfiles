import qs
import QtQuick
import Quickshell.Hyprland
import "../components" as Components

Item {
    id: expoRoot; implicitWidth: expoIcon.implicitWidth + 2; implicitHeight: expoIcon.implicitHeight
    Components.Icon {
        id: expoIcon; anchors.centerIn: parent; source: "../icons/layout.svg"
        color: expoArea.containsMouse ? Theme.blueBright : Theme.fg4
    }
    MouseArea {
        id: expoArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
        onClicked: Hyprland.dispatch("hyprexpo:expo toggle")
        onContainsMouseChanged: {
            if (containsMouse) {
                let p = expoRoot.mapToGlobal(Qt.point(expoRoot.width / 2, expoRoot.height));
                TooltipService.show("Workspace Overview", p.x, p.y);
            } else {
                TooltipService.hide();
            }
        }
    }
}
