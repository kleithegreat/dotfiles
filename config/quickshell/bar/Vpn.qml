import qs
import QtQuick
import QtQuick.Layouts
import "../components" as Components

RowLayout {
    id: vpnRoot; spacing: 4; signal clicked()
    readonly property bool anyActive: VpnService.mullvadState === "connected" || VpnService.tailscaleState === "running"

    Text {
        id: vpnIcon
        text: "󰒃"
        color: vpnArea.containsMouse ? Theme.yellowBright : (vpnRoot.anyActive ? Theme.greenBright : Theme.fg4)
        font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize

        Behavior on color { Components.CAnim { duration: 150 } }
    }

    MouseArea {
        id: vpnArea; anchors.fill: parent
        cursorShape: Qt.PointingHandCursor; hoverEnabled: true
        onClicked: vpnRoot.clicked()
    }
}
