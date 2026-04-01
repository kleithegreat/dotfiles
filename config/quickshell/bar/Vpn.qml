import qs
import QtQuick
import QtQuick.Layouts
import "../components" as Components

RowLayout {
    id: vpnRoot; spacing: 4; signal clicked()
    readonly property bool anyActive: VpnService.mullvadState === "connected" || VpnService.tailscaleState === "running"
    property string tooltipText: {
        let parts = [];
        if (VpnService.mullvadState === "connected") {
            let loc = VpnService.mullvadCity || VpnService.mullvadCountry || "Connected";
            parts.push("Mullvad: " + loc);
        }
        if (VpnService.tailscaleState === "running") {
            let net = VpnService.tailscaleTailnet || "Connected";
            parts.push("Tailscale: " + net);
        }
        return parts.length > 0 ? parts.join(" · ") : "VPN off";
    }

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
        onContainsMouseChanged: {
            if (containsMouse) {
                let p = vpnRoot.mapToGlobal(Qt.point(vpnRoot.width / 2, vpnRoot.height));
                TooltipService.show(vpnRoot.tooltipText, p.x, p.y);
            } else {
                TooltipService.hide();
            }
        }
    }
}
