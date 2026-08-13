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
    Components.BarTooltipArea {
        id: expoArea; tip: "Workspace Overview"
        // expo() returns nil, so hand the IPC a real dispatcher back.
        onClicked: Hyprland.dispatch('(function() hl.plugin.hyprexpo.expo("toggle") return hl.dsp.no_op() end)()')
    }
}
