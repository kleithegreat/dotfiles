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

    Text {
        id: btIcon
        text: connected ? "󰂱" : (powered ? "󰂯" : "󰂲")
        color: btArea.containsMouse ? Theme.yellowBright : (connected ? Theme.fg : Theme.fg4)
        font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize

        Behavior on text {
            SequentialAnimation {
                Components.Anim { target: btIcon; property: "opacity"; to: 0; duration: 120; easing.type: Easing.InQuad }
                PropertyAction { target: btIcon; property: "text" }
                Components.Anim { target: btIcon; property: "opacity"; to: 1; duration: 200; easing.type: Easing.OutCubic }
            }
        }
        Behavior on color { Components.CAnim { duration: 150 } }
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
