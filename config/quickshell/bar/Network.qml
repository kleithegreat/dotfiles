import qs
import QtQuick
import QtQuick.Layouts
import "../components" as Components

RowLayout {
    id: netRoot; spacing: 4; signal clicked()
    readonly property string connectionType: NetworkService.primaryConnectionType
    readonly property string networkName: NetworkService.primaryConnectionLabel
    readonly property string displayName: connectionType === "ethernet"
        ? "Ethernet"
        : (networkName || "Wi-Fi")
    readonly property bool connected: connectionType !== ""
    property string tooltipText: {
        if (!connected) return "Not connected";
        return displayName;
    }

    Components.Icon {
        id: netIcon
        source: !connected ? "../icons/wifi-off.svg" : (connectionType === "ethernet" ? "../icons/ethernet.svg" : "../icons/wifi.svg")
        color: netArea.containsMouse ? Theme.yellowBright : (connected ? Theme.fg : Theme.fg4)

        // Smooth icon swap: crossfade
        Behavior on source {
            SequentialAnimation {
                Components.Anim { target: netIcon; property: "opacity"; to: 0; duration: Theme.animHover; easing.type: Easing.InQuad }
                PropertyAction { target: netIcon; property: "source" }
                Components.Anim { target: netIcon; property: "opacity"; to: 1; duration: Theme.animNormal; easing.type: Easing.OutCubic }
            }
        }
        Behavior on color { Components.CAnim { duration: Theme.animHover } }
    }

    MouseArea {
        id: netArea; anchors.fill: parent
        cursorShape: Qt.PointingHandCursor; hoverEnabled: true
        onClicked: netRoot.clicked()
        onContainsMouseChanged: {
            if (containsMouse) {
                let p = netRoot.mapToGlobal(Qt.point(netRoot.width / 2, netRoot.height));
                TooltipService.show(netRoot.tooltipText, p.x, p.y);
            } else {
                TooltipService.hide();
            }
        }
    }
}
