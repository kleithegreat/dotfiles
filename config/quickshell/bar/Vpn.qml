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

    Components.Icon {
        id: vpnIcon
        source: "../icons/shield-lock.svg"
        color: vpnArea.containsMouse ? Theme.yellowBright : (vpnRoot.anyActive ? Theme.greenBright : Theme.fg4)

        Behavior on color { Components.CAnim { duration: Theme.animHover } }
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
