import qs
import QtQuick
import QtQuick.Layouts
import "../components" as Components

RowLayout {
    id: btRoot; spacing: 4; signal clicked()
    readonly property string deviceName: BluetoothService.connectedName
    readonly property bool powered: BluetoothService.powered
    property bool connected: deviceName !== ""
    property string tooltipText: {
        if (connected) return deviceName;
        if (powered) return "Bluetooth on";
        return "Bluetooth off";
    }

    Components.Icon {
        id: btIcon
        source: connected ? "../icons/bluetooth-connected.svg" : (powered ? "../icons/bluetooth-on.svg" : "../icons/bluetooth-off.svg")
        color: btArea.containsMouse ? Theme.yellowBright : (connected ? Theme.fg : Theme.fg4)

        Behavior on source {
            SequentialAnimation {
                Components.Anim { target: btIcon; property: "opacity"; to: 0; duration: 120; easing.type: Easing.InQuad }
                PropertyAction { target: btIcon; property: "source" }
                Components.Anim { target: btIcon; property: "opacity"; to: 1; duration: 200; easing.type: Easing.OutCubic }
            }
        }
        Behavior on color { Components.CAnim { duration: Theme.animHover } }
    }

    MouseArea {
        id: btArea; anchors.fill: parent
        cursorShape: Qt.PointingHandCursor; hoverEnabled: true
        onClicked: btRoot.clicked()
        onContainsMouseChanged: {
            if (containsMouse) {
                let p = btRoot.mapToGlobal(Qt.point(btRoot.width / 2, btRoot.height));
                TooltipService.show(btRoot.tooltipText, p.x, p.y);
            } else {
                TooltipService.hide();
            }
        }
    }
}
