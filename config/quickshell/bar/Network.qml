import qs
import QtQuick
import QtQuick.Layouts
import "../components" as Components

RowLayout {
    id: netRoot; spacing: 4; signal clicked()
    readonly property string connectionType: NetworkService.primaryConnectionType
    readonly property string networkName: NetworkService.primaryConnectionLabel
    readonly property bool connected: connectionType !== ""
    property string tooltipText: {
        if (!connected) return "Not connected";
        if (connectionType === "ethernet") return "Ethernet";
        return networkName || "Wi-Fi connected";
    }

    Text {
        id: netIcon
        text: !connected ? "󰖪" : (connectionType === "ethernet" ? "󰈀" : "󰖩")
        color: netArea.containsMouse ? Theme.yellowBright : (connected ? Theme.fg : Theme.fg4)
        font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize

        // Smooth icon swap: crossfade + subtle vertical slide
        Behavior on text {
            SequentialAnimation {
                Components.Anim { target: netIcon; property: "opacity"; to: 0; duration: 120; easing.type: Easing.InQuad }
                PropertyAction { target: netIcon; property: "text" }
                Components.Anim { target: netIcon; property: "opacity"; to: 1; duration: 200; easing.type: Easing.OutCubic }
            }
        }
        Behavior on color { Components.CAnim { duration: 150 } }
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
